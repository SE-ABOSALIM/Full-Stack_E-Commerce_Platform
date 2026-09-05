"""Password reset, phone/email verification, and SMS utility routes."""

import hmac
import re
import secrets
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

import app.models as models
import app.schemas as schemas
from app.auth import hash_password
from app.dependencies import (
    current_actor,
    current_seller,
    current_user,
    get_db,
    optional_actor,
    owned_resource,
)
from app.phone_numbers import normalize_phone_number
from app.services.account_helpers import account_for_reset, phone_verification_owner
from app.services.email_service import email_service
from app.services.sms_language_manager import sms_language_manager
from app.services.twilio_sms_service import twilio_sms_service
from app.services.verification import (
    delete_phone_records,
    generate_verification_code,
    one_phone_record,
    reset_code_hash,
    send_sms_verification,
)

router = APIRouter()


@router.post("/auth/forgot-password/request")
def request_password_reset(payload: schemas.PasswordResetRequest, db: Session = Depends(get_db)):
    phone = normalize_phone_number(payload.phone_number)
    user = account_for_reset(db, phone)
    result = {"message": "If an account matches, a verification code has been sent", "success": True}
    if user is None:
        return result
    # Serialize requests for this account in PostgreSQL; each resend replaces the old code.
    db.query(models.User).filter_by(id=user.id).with_for_update().one()
    challenge = db.query(models.PasswordResetVerification).filter_by(user_id=user.id).first()
    now = datetime.utcnow()
    if challenge and challenge.created_at > now - timedelta(seconds=60):
        return result
    code = f"{secrets.randbelow(1_000_000):06d}"
    if challenge is None:
        challenge = models.PasswordResetVerification(user_id=user.id)
        db.add(challenge)
    challenge.phone_number = phone
    challenge.code_hash = reset_code_hash(phone, code)
    challenge.attempts = 0
    challenge.created_at = now
    challenge.expires_at = now + timedelta(minutes=5)
    challenge.consumed_at = None
    db.flush()
    if not send_sms_verification(phone, code, "tr"):
        db.rollback()
        raise HTTPException(503, "Verification message could not be sent")
    db.commit()
    return result


@router.post("/auth/forgot-password/reset")
def reset_password(payload: schemas.PasswordReset, db: Session = Depends(get_db)):
    phone = normalize_phone_number(payload.phone_number)
    user = account_for_reset(db, phone)
    challenge = (db.query(models.PasswordResetVerification).filter_by(user_id=user.id).first()
                 if user else None)
    now = datetime.utcnow()
    invalid = HTTPException(400, "Invalid or expired verification code; request a new code")
    if (challenge is None or challenge.phone_number != phone or challenge.consumed_at is not None
            or challenge.expires_at <= now or challenge.attempts >= 3):
        raise invalid
    # Conditional UPDATE makes attempt limits and consumption atomic, including on SQLite.
    available = db.query(models.PasswordResetVerification).filter(
        models.PasswordResetVerification.id == challenge.id,
        models.PasswordResetVerification.code_hash == challenge.code_hash,
        models.PasswordResetVerification.consumed_at.is_(None),
        models.PasswordResetVerification.expires_at > now,
        models.PasswordResetVerification.attempts < 3,
    )
    if not hmac.compare_digest(challenge.code_hash, reset_code_hash(phone, payload.verification_code)):
        available.update({"attempts": models.PasswordResetVerification.attempts + 1}, synchronize_session=False)
        db.commit()
        raise invalid
    if available.update({"consumed_at": now}, synchronize_session=False) != 1:
        db.rollback()
        raise invalid
    user.password = hash_password(payload.new_password)
    db.commit()
    return {"message": "Password reset; please sign in", "success": True}


@router.post("/send-verification-code", response_model=schemas.PhoneVerificationResponse)
def send_verification_code(verification: schemas.PhoneVerificationCreate, db: Session = Depends(get_db)):
    """Telefon numarasına doğrulama kodu gönder"""


    formatted_phone = normalize_phone_number(verification.phone_number)
    _, existing_user = one_phone_record(db, models.User, "phone_number", formatted_phone)

    if existing_user:
        raise HTTPException(
            status_code=400,
            detail="Bu telefon numarasına kayıtlı başka bir hesap vardır"
        )

    _, existing_verification = one_phone_record(
        db, models.PhoneVerification, "phone_number", formatted_phone
    )

    if existing_verification and existing_verification.is_verified == "verified":
        raise HTTPException(
            status_code=400,
            detail="Bu telefon numarası zaten doğrulanmış"
        )


    # Eski doğrulama kodlarını temizle
    delete_phone_records(db, models.PhoneVerification, "phone_number", formatted_phone)

    # Yeni doğrulama kodu oluştur
    verification_code = generate_verification_code()
    expires_at = datetime.now() + timedelta(minutes=5)  # 5 dakika geçerli


    try:
        # Veritabanına kaydet
        db_verification = models.PhoneVerification(
            phone_number=formatted_phone,
            verification_code=verification_code,
            is_verified="pending",
            attempts=0,
            created_at=datetime.now(),
            expires_at=expires_at
        )

        db.add(db_verification)
        db.commit()
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Veritabanı hatası: {str(e)}")

    # SMS gönder (Twilio ile çok dilli)
    send_sms_verification(formatted_phone, verification_code, verification.language)

    try:
        response = schemas.PhoneVerificationResponse(
            message="Doğrulama kodu gönderildi",
            success=True,
            expires_in=300  # 5 dakika
        )

        return response
    except Exception as e:

        raise HTTPException(status_code=500, detail=f"Response oluşturulamadı: {str(e)}")


@router.post("/verify-phone", response_model=schemas.PhoneVerificationResponse)
def verify_phone(verification: schemas.PhoneVerificationVerify, db: Session = Depends(get_db), actor=Depends(optional_actor)):
    """Telefon numarası doğrulama kodunu doğrula"""
    phone_number, account = phone_verification_owner(
        db, verification.phone_number, "user", actor
    )

    # Doğrulama kaydını bul
    _, db_verification = one_phone_record(
        db, models.PhoneVerification, "phone_number", phone_number
    )

    if not db_verification:
        raise HTTPException(
            status_code=404,
            detail="Doğrulama kodu bulunamadı. Lütfen yeni kod gönderin"
        )

    # Süre kontrolü
    if datetime.now() > db_verification.expires_at:
        db_verification.is_verified = "expired"
        db.commit()
        raise HTTPException(
            status_code=400,
            detail="Doğrulama kodu süresi dolmuş. Lütfen yeni kod gönderin"
        )

    # Deneme sayısı kontrolü
    if db_verification.attempts >= 3:
        raise HTTPException(
            status_code=400,
            detail="Çok fazla deneme. Lütfen yeni kod gönderin"
        )

    # Kodu doğrula
    if db_verification.verification_code != verification.verification_code:
        db_verification.attempts += 1
        db.commit()
        raise HTTPException(
            status_code=400,
            detail=f"Yanlış kod. Kalan deneme: {3 - db_verification.attempts}"
        )

    # Doğrulama başarılı
    db_verification.is_verified = "verified"
    if account is not None:
        account.phone_verified = "verified"
    db.commit()

    return schemas.PhoneVerificationResponse(
        message="Telefon numarası başarıyla doğrulandı",
        success=True
    )


@router.post("/users/{user_id}/send-phone-verification", response_model=schemas.PhoneVerificationResponse)
def send_user_phone_verification(user_id: int, db: Session = Depends(get_db), actor=Depends(current_user)):
    """Mevcut kullanıcının kayıtlı telefonuna doğrulama kodu gönder"""
    owned_resource(db, models.User, user_id, actor, "id")
    # Kullanıcıyı bul
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    if not user.phone_number:
        raise HTTPException(status_code=400, detail="Kullanıcının telefon numarası bulunamadı")

    phone_number = normalize_phone_number(user.phone_number)


    # Eski doğrulama kodlarını temizle
    delete_phone_records(db, models.PhoneVerification, "phone_number", phone_number)

    # Yeni doğrulama kodu oluştur
    verification_code = generate_verification_code()
    expires_at = datetime.now() + timedelta(minutes=5)  # 5 dakika geçerli


    try:
        # Veritabanına kaydet
        db_verification = models.PhoneVerification(
            phone_number=phone_number,
            verification_code=verification_code,
            is_verified="pending",
            attempts=0,
            created_at=datetime.now(),
            expires_at=expires_at
        )

        db.add(db_verification)
        db.commit()

    except Exception as e:

        db.rollback()
        raise HTTPException(status_code=500, detail=f"Veritabanı hatası: {str(e)}")

    # SMS gönder (Twilio ile çok dilli)
    send_sms_verification(phone_number, verification_code, "tr")

    try:
        response = schemas.PhoneVerificationResponse(
            message="Doğrulama kodu gönderildi",
            success=True,
            expires_in=300  # 5 dakika
        )

        return response
    except Exception as e:

        raise HTTPException(status_code=500, detail=f"Response oluşturulamadı: {str(e)}")


@router.post("/sms/welcome")
def send_welcome_sms(phone_number: str, language: str = None, user_name: str = "", actor=Depends(current_actor)):
    raise HTTPException(403, "Direct SMS utilities are disabled; use the application workflow")


@router.post("/sms/order-status")
def send_order_status_sms(phone_number: str, order_number: str, status: str, language: str = None, actor=Depends(current_actor)):
    raise HTTPException(403, "Direct SMS utilities are disabled; use the application workflow")


@router.post("/sms/promotional")
def send_promotional_sms(phone_number: str, discount: str, valid_until: str, language: str = None, actor=Depends(current_actor)):
    raise HTTPException(403, "Direct SMS utilities are disabled; use the application workflow")


@router.get("/sms/languages")
def get_supported_languages():
    """Desteklenen dilleri listele"""
    languages = sms_language_manager.get_supported_languages()
    return {
        "supported_languages": languages,
        "default_language": sms_language_manager.default_language,
        "brand_name": sms_language_manager.brand_name
    }


@router.get("/sms/check-sender-id")
def check_sender_id_support():
    """Alphanumeric Sender ID desteğini kontrol et"""
    try:
        result = twilio_sms_service.check_alphanumeric_support()
        return result
    except Exception as e:
        return {
            "success": False,
            "message": f"Sender ID kontrol hatası: {str(e)}",
            "brand_name": sms_language_manager.brand_name
        }


@router.get("/sms/balance")
def get_sms_balance():
    """Twilio SMS bakiyesini sorgula"""
    result = twilio_sms_service.get_balance()
    return result


@router.post("/send-seller-verification-code", response_model=schemas.PhoneVerificationResponse)
def send_seller_verification_code(verification: schemas.PhoneVerificationSellerCreate, db: Session = Depends(get_db)):
    """Satıcılar için telefon numarasına doğrulama kodu gönder"""

    formatted_phone = normalize_phone_number(verification.phone_number)

    # Bu telefon numarasına kayıtlı satıcı var mı kontrol et
    _, existing_seller = one_phone_record(db, models.Seller, "phone", formatted_phone)

    if existing_seller:

        raise HTTPException(
            status_code=400,
            detail="Bu telefon numarasına kayıtlı başka bir satıcı hesabı vardır"
        )

    # Daha önce doğrulanmış mı kontrol et (seller tablosunda)
    _, existing_verification = one_phone_record(
        db, models.PhoneVerificationSeller, "phone_number", formatted_phone
    )

    if existing_verification and existing_verification.is_verified == "verified":

        raise HTTPException(
            status_code=400,
            detail="Bu telefon numarası zaten doğrulanmış"
        )

    # Eski doğrulama kodlarını temizle
    delete_phone_records(db, models.PhoneVerificationSeller, "phone_number", formatted_phone)

    # Yeni doğrulama kodu oluştur
    verification_code = generate_verification_code()
    expires_at = datetime.now() + timedelta(minutes=5)  # 5 dakika geçerli


    try:
        # Veritabanına kaydet
        db_verification = models.PhoneVerificationSeller(
            phone_number=formatted_phone,
            verification_code=verification_code,
            is_verified="pending",
            attempts=0,
            created_at=datetime.now(),
            expires_at=expires_at
        )

        db.add(db_verification)
        db.commit()

    except Exception as e:

        db.rollback()
        raise HTTPException(status_code=500, detail=f"Veritabanı hatası: {str(e)}")

    # SMS gönder (Twilio ile çok dilli)
    send_sms_verification(formatted_phone, verification_code, verification.language)

    try:
        response = schemas.PhoneVerificationResponse(
            message="Doğrulama kodu gönderildi",
            success=True,
            expires_in=300  # 5 dakika
        )

        return response
    except Exception as e:

        raise HTTPException(status_code=500, detail=f"Response oluşturulamadı: {str(e)}")


@router.post("/verify-seller-phone", response_model=schemas.PhoneVerificationResponse)
def verify_seller_phone(verification: schemas.PhoneVerificationSellerVerify, db: Session = Depends(get_db), actor=Depends(optional_actor)):
    """Satıcılar için telefon numarası doğrulama kodunu doğrula"""
    phone_number, account = phone_verification_owner(
        db, verification.phone_number, "seller", actor
    )

    # Doğrulama kaydını bul
    _, db_verification = one_phone_record(
        db, models.PhoneVerificationSeller, "phone_number", phone_number
    )

    if not db_verification:
        raise HTTPException(
            status_code=404,
            detail="Doğrulama kodu bulunamadı. Lütfen yeni kod gönderin"
        )

    # Süre kontrolü
    if datetime.now() > db_verification.expires_at:
        db_verification.is_verified = "expired"
        db.commit()
        raise HTTPException(
            status_code=400,
            detail="Doğrulama kodu süresi dolmuş. Lütfen yeni kod gönderin"
        )

    # Deneme sayısı kontrolü
    if db_verification.attempts >= 3:
        raise HTTPException(
            status_code=400,
            detail="Çok fazla deneme. Lütfen yeni kod gönderin"
        )

    # Kodu doğrula
    if db_verification.verification_code != verification.verification_code:
        db_verification.attempts += 1
        db.commit()
        raise HTTPException(
            status_code=400,
            detail=f"Yanlış kod. Kalan deneme: {3 - db_verification.attempts}"
        )

    # Doğrulama başarılı
    db_verification.is_verified = "verified"
    if account is not None:
        account.phone_verified = "verified"
    db.commit()

    return schemas.PhoneVerificationResponse(
        message="Telefon numarası başarıyla doğrulandı",
        success=True
    )


@router.post("/send-email-verification-code", response_model=schemas.EmailVerificationResponse)
def send_email_verification_code(verification: schemas.EmailVerificationCreate, db: Session = Depends(get_db), actor=Depends(current_user)):
    """Kullanıcılar için email adresine doğrulama kodu gönder"""
    if verification.email != actor.email:
        raise HTTPException(403, "Email belongs to another account")

    # Email formatını doğrula
    import re
    email_pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    if not re.match(email_pattern, verification.email):

        raise HTTPException(
            status_code=400,
            detail="Geçersiz email formatı"
        )

    # Bu email adresine kayıtlı kullanıcı var mı kontrol et
    existing_user = db.query(models.User).filter(
        models.User.email == verification.email
    ).first()

    if not existing_user:

        raise HTTPException(
            status_code=404,
            detail="Bu email adresine kayıtlı kullanıcı bulunamadı"
        )

    # Email zaten doğrulanmış mı kontrol et
    if existing_user.email_verified == "verified":

        raise HTTPException(
            status_code=400,
            detail="Bu email adresi zaten doğrulanmış"
        )

    # Eski doğrulama kodlarını temizle
    db.query(models.EmailVerification).filter(
        models.EmailVerification.email == verification.email
    ).delete()

    # Yeni doğrulama kodu oluştur
    verification_code = generate_verification_code()
    expires_at = datetime.now() + timedelta(minutes=5)  # 5 dakika geçerli


    try:
        # Veritabanına kaydet
        db_verification = models.EmailVerification(
            email=verification.email,
            verification_code=verification_code,
            is_verified="pending",
            attempts=0,
            created_at=datetime.now(),
            expires_at=expires_at
        )

        db.add(db_verification)
        db.commit()

    except Exception as e:

        db.rollback()
        raise HTTPException(status_code=500, detail=f"Veritabanı hatası: {str(e)}")

    # Email gönder
    email_result = email_service.send_verification_email(verification.email, verification_code, verification.language)

    if not email_result['success']:

        raise HTTPException(status_code=500, detail=f"Email gönderilemedi: {email_result['message']}")

    try:
        response = schemas.EmailVerificationResponse(
            message="Email doğrulama kodu gönderildi",
            success=True,
            expires_in=300  # 5 dakika
        )

        return response
    except Exception as e:

        raise HTTPException(status_code=500, detail=f"Response oluşturulamadı: {str(e)}")


@router.post("/verify-email", response_model=schemas.EmailVerificationResponse)
def verify_email(verification: schemas.EmailVerificationVerify, db: Session = Depends(get_db), actor=Depends(current_user)):
    """Kullanıcılar için email doğrulama kodunu doğrula"""
    if verification.email != actor.email:
        raise HTTPException(403, "Email belongs to another account")

    # Doğrulama kaydını bul
    db_verification = db.query(models.EmailVerification).filter(
        models.EmailVerification.email == verification.email
    ).first()

    if not db_verification:
        raise HTTPException(
            status_code=404,
            detail="Doğrulama kodu bulunamadı. Lütfen yeni kod gönderin"
        )

    # Süre kontrolü
    if datetime.now() > db_verification.expires_at:
        db_verification.is_verified = "expired"
        db.commit()
        raise HTTPException(
            status_code=400,
            detail="Doğrulama kodu süresi dolmuş. Lütfen yeni kod gönderin"
        )

    # Deneme sayısı kontrolü
    if db_verification.attempts >= 3:
        raise HTTPException(
            status_code=400,
            detail="Çok fazla deneme. Lütfen yeni kod gönderin"
        )

    # Kodu doğrula
    if db_verification.verification_code != verification.verification_code:
        db_verification.attempts += 1
        db.commit()
        raise HTTPException(
            status_code=400,
            detail=f"Yanlış kod. Kalan deneme: {3 - db_verification.attempts}"
        )

    # Doğrulama başarılı - kullanıcının email_verified alanını güncelle
    db_verification.is_verified = "verified"

    # Kullanıcının email_verified alanını güncelle
    user = db.query(models.User).filter(models.User.email == verification.email).first()
    if user:
        user.email_verified = "verified"
        user.updated_at = datetime.now()

    db.commit()

    return schemas.EmailVerificationResponse(
        message="Email adresi başarıyla doğrulandı",
        success=True
    )


@router.post("/send-seller-email-verification-code", response_model=schemas.EmailVerificationSellerResponse)
def send_seller_email_verification_code(verification: schemas.EmailVerificationSellerCreate, db: Session = Depends(get_db), actor=Depends(current_seller)):
    """Satıcılar için email adresine doğrulama kodu gönder"""
    if verification.email != actor.email:
        raise HTTPException(403, "Email belongs to another account")

    # Email formatını doğrula
    import re
    email_pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    if not re.match(email_pattern, verification.email):

        raise HTTPException(
            status_code=400,
            detail="Geçersiz email formatı"
        )

    # Bu email adresine kayıtlı satıcı var mı kontrol et
    existing_seller = db.query(models.Seller).filter(
        models.Seller.email == verification.email
    ).first()

    if not existing_seller:

        raise HTTPException(
            status_code=404,
            detail="Bu email adresine kayıtlı satıcı bulunamadı"
        )

    # Email zaten doğrulanmış mı kontrol et
    if existing_seller.email_verified == "verified":

        raise HTTPException(
            status_code=400,
            detail="Bu email adresi zaten doğrulanmış"
        )

    # Eski doğrulama kodlarını temizle
    db.query(models.EmailVerificationSeller).filter(
        models.EmailVerificationSeller.email == verification.email
    ).delete()

    # Yeni doğrulama kodu oluştur
    verification_code = generate_verification_code()
    expires_at = datetime.now() + timedelta(minutes=5)  # 5 dakika geçerli


    try:
        # Veritabanına kaydet
        db_verification = models.EmailVerificationSeller(
            email=verification.email,
            verification_code=verification_code,
            is_verified="pending",
            attempts=0,
            created_at=datetime.now(),
            expires_at=expires_at
        )

        db.add(db_verification)
        db.commit()

    except Exception as e:

        db.rollback()
        raise HTTPException(status_code=500, detail=f"Veritabanı hatası: {str(e)}")

    # Email gönder
    email_result = email_service.send_verification_email(verification.email, verification_code, verification.language or "tr")

    if not email_result['success']:

        raise HTTPException(status_code=500, detail=f"Email gönderilemedi: {email_result['message']}")

    try:
        response = schemas.EmailVerificationSellerResponse(
            message="Email doğrulama kodu gönderildi",
            success=True,
            expires_in=300  # 5 dakika
        )

        return response
    except Exception as e:

        raise HTTPException(status_code=500, detail=f"Response oluşturulamadı: {str(e)}")


@router.post("/verify-seller-email", response_model=schemas.EmailVerificationSellerResponse)
def verify_seller_email(verification: schemas.EmailVerificationSellerVerify, db: Session = Depends(get_db), actor=Depends(current_seller)):
    """Satıcı email doğrulama kodunu doğrula"""
    if verification.email != actor.email:
        raise HTTPException(403, "Email belongs to another account")

    # Doğrulama kaydını bul
    db_verification = db.query(models.EmailVerificationSeller).filter(
        models.EmailVerificationSeller.email == verification.email
    ).first()

    if not db_verification:
        raise HTTPException(
            status_code=404,
            detail="Doğrulama kodu bulunamadı. Lütfen yeni kod gönderin"
        )

    # Süre kontrolü
    if datetime.now() > db_verification.expires_at:
        db_verification.is_verified = "expired"
        db.commit()
        raise HTTPException(
            status_code=400,
            detail="Doğrulama kodu süresi dolmuş. Lütfen yeni kod gönderin"
        )

    # Deneme sayısı kontrolü
    if db_verification.attempts >= 3:
        raise HTTPException(
            status_code=400,
            detail="Çok fazla deneme. Lütfen yeni kod gönderin"
        )

    # Kodu doğrula
    if db_verification.verification_code != verification.verification_code:
        db_verification.attempts += 1
        db.commit()
        raise HTTPException(
            status_code=400,
            detail=f"Yanlış kod. Kalan deneme: {3 - db_verification.attempts}"
        )

    # Doğrulama başarılı - satıcının email_verified durumunu güncelle
    seller = db.query(models.Seller).filter(models.Seller.email == verification.email).first()
    if seller:
        seller.email_verified = "verified"
        seller.updated_at = datetime.now()

    # Doğrulama kaydını güncelle
    db_verification.is_verified = "verified"
    db.commit()

    return schemas.EmailVerificationSellerResponse(
        message="Email adresi başarıyla doğrulandı",
        success=True
    )


@router.post("/sellers/{seller_id}/send-phone-verification", response_model=schemas.PhoneVerificationResponse)
def send_seller_phone_verification(seller_id: int, db: Session = Depends(get_db), actor=Depends(current_seller)):
    owned_resource(db, models.Seller, seller_id, actor, "id")
    phone_number = normalize_phone_number(actor.phone)
    code = generate_verification_code()
    delete_phone_records(db, models.PhoneVerificationSeller, "phone_number", phone_number)
    db.add(models.PhoneVerificationSeller(
        phone_number=phone_number, verification_code=code, is_verified="pending", attempts=0,
        created_at=datetime.now(), expires_at=datetime.now() + timedelta(minutes=5),
    ))
    if not send_sms_verification(phone_number, code, "tr"):
        db.rollback()
        raise HTTPException(503, "Verification message could not be sent")
    db.commit()
    return schemas.PhoneVerificationResponse(message="Verification code sent", success=True, expires_in=300)
