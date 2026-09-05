"""User accounts, profiles, addresses, and seller-following routes."""

from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, Form, HTTPException
from sqlalchemy import case, func
from sqlalchemy.orm import Session

import app.models as models
import app.schemas as schemas
from app.auth import hash_password, issue_access_token, verify_password
from app.dependencies import current_user, get_db, owned_resource, require_owner
from app.phone_numbers import normalize_phone_number
from app.services.account_helpers import ensure_user_contacts_available
from app.services.sms_language_manager import sms_language_manager
from app.services.twilio_sms_service import twilio_sms_service
from app.services.verification import (
    delete_phone_records,
    generate_verification_code,
    one_phone_record,
    send_sms_verification,
)

router = APIRouter()


def public_user(user):
    return schemas.UserBase(
        id=user.id, name_surname=user.name_surname, email=user.email,
        phone_number=user.phone_number, phone_verified=user.phone_verified,
        email_verified=user.email_verified,
        created_at=user.created_at.isoformat() if user.created_at else "",
        updated_at=user.updated_at.isoformat() if user.updated_at else "",
    )


@router.get("/users/me", response_model=schemas.UserBase)
def get_my_profile(actor=Depends(current_user)):
    return public_user(actor)


@router.put("/users/me", response_model=schemas.UserBase)
def update_my_profile(user: schemas.UserUpdate, actor=Depends(current_user), db: Session = Depends(get_db)):
    return update_user(actor.id, user, db, actor)


@router.put("/users/me/password")
def change_password(payload: schemas.PasswordChange, actor=Depends(current_user), db: Session = Depends(get_db)):
    if not verify_password(payload.current_password, actor.password):
        raise HTTPException(401, "Current password is incorrect")
    if payload.new_password != payload.new_password_again:
        raise HTTPException(400, "New password and confirmation must match")
    actor.password = hash_password(payload.new_password)
    db.query(models.PasswordResetVerification).filter_by(user_id=actor.id).delete()
    db.commit()
    return {"message": "Password changed; please sign in again"}


@router.post("/users", response_model=schemas.UserBase)
def create_user(user: schemas.UserCreate, db: Session = Depends(get_db)):
    formatted_phone = normalize_phone_number(user.phone_number)
    ensure_user_contacts_available(db, formatted_phone, user.email)

    # Telefon numarası doğrulanmış mı kontrol et (hem formatlanmış hem formatlanmamış)
    _, phone_verification = one_phone_record(
        db, models.PhoneVerification, "phone_number", formatted_phone
    )

    # Telefon doğrulanmamışsa hata ver
    if not phone_verification or phone_verification.is_verified != "verified":
        raise HTTPException(
            status_code=400,
            detail="Telefon numarası doğrulanmamış. Lütfen önce telefon numaranızı doğrulayın."
        )

    # Email kontrolü
    existing_user = db.query(models.User).filter(models.User.email == user.email).first()
    if existing_user:
        raise HTTPException(status_code=400, detail="Email already registered")

    # Kullanıcı oluştur
    from datetime import datetime

    try:
        hashed_password = hash_password(user.password)
        db_user = models.User(
            name_surname=user.name_surname,
            password=hashed_password,
            email=user.email,
            phone_number=formatted_phone,  # Formatlanmış telefon numarasını kullan
            phone_verified="verified",
            email_verified="pending",  # Yeni kullanıcılar için email doğrulama gerekli
            created_at=datetime.now(),
            updated_at=datetime.now()
        )

        db.add(db_user)
        db.commit()
        db.refresh(db_user)

    except Exception as e:

        raise

    # Doğrulama kaydını temizleme - kayıt kalmalı (güvenlik ve denetim için)
    # if phone_verification:
    #     db.delete(phone_verification)
    #     db.commit()

    # Hoş geldin SMS'i gönder (arka planda)
    try:
        # Telefon numarasından dil tahmini yap
        language = sms_language_manager.get_language_from_phone(formatted_phone)

        # Hoş geldin SMS'i gönder
        welcome_result = twilio_sms_service.send_welcome_sms(formatted_phone, language, user.name_surname)

        if welcome_result['success']:
            pass
        else:
            pass

    except Exception as e:
        pass
        # SMS hatası kullanıcı kaydını etkilemez

    return schemas.UserBase(
        id=db_user.id,
        name_surname=db_user.name_surname,
        email=db_user.email,
        phone_number=db_user.phone_number,
        phone_verified=db_user.phone_verified,
        email_verified=db_user.email_verified,
        created_at=db_user.created_at.isoformat(),
        updated_at=db_user.updated_at.isoformat()
    )


@router.get("/users", response_model=list[schemas.UserBase])
def get_users(db: Session = Depends(get_db)):
    users = db.query(models.User).all()
    return [
        schemas.UserBase(
            id=user.id,
            name_surname=user.name_surname,
            email=user.email,
            phone_number=user.phone_number,
            phone_verified=user.phone_verified,
            email_verified=user.email_verified,
            created_at=user.created_at.isoformat() if user.created_at else "",
            updated_at=user.updated_at.isoformat() if user.updated_at else ""
        )
        for user in users
    ]


@router.put("/users/{user_id}", response_model=schemas.UserBase)
def update_user(user_id: int, user: schemas.UserUpdate, db: Session = Depends(get_db), actor=Depends(current_user)):
    owned_resource(db, models.User, user_id, actor, "id")
    db_user = db.query(models.User).filter(models.User.id == user_id).first()
    if not db_user:
        raise HTTPException(status_code=404, detail="User not found")

    normalized_phone = normalize_phone_number(user.phone_number)
    current_phone = normalize_phone_number(actor.phone_number)
    ensure_user_contacts_available(db, normalized_phone, user.email, actor.id)
    phone_changed = normalized_phone != current_phone
    if phone_changed:
        db.query(models.PasswordResetVerification).filter_by(user_id=actor.id).delete()

    # Email değişikliği kontrolü
    if user.email and user.email != db_user.email:
        # Eski email doğrulama kayıtlarını temizle
        old_email_verifications = db.query(models.EmailVerification).filter(
            models.EmailVerification.email == db_user.email
        ).all()
        for verification in old_email_verifications:
            db.delete(verification)

        # Email doğrulama durumunu sıfırla
        db_user.email_verified = "pending"


    # Telefon numarası değişikliği kontrolü
    if phone_changed:
        old_phone = db_user.phone_number
        new_phone = normalized_phone

        # Eski telefon doğrulama kayıtlarını temizle
        delete_phone_records(db, models.PhoneVerification, "phone_number", old_phone)

        # Telefon doğrulama durumunu sıfırla
        db_user.phone_verified = "pending"


        # Yeni telefon numarasına otomatik kod gönder
        try:
            # Önce telefon numarasını güncelle
            db_user.phone_number = new_phone
            db.commit()
            db.refresh(db_user)

            # Yeni telefon numarasına kod oluştur
            verification_code = generate_verification_code()
            expires_at = datetime.now() + timedelta(minutes=5)



            # Eski doğrulama kayıtlarını temizle (yeni numara için)
            delete_phone_records(db, models.PhoneVerification, "phone_number", new_phone)

            # Yeni doğrulama kaydı oluştur
            phone_verification = models.PhoneVerification(
                phone_number=new_phone,
                verification_code=verification_code,
                is_verified="pending",
                attempts=0,
                created_at=datetime.now(),
                expires_at=expires_at
            )
            db.add(phone_verification)
            db.commit()

            # SMS gönder (global loglarla)
            send_sms_verification(new_phone, verification_code, "tr")


        except HTTPException:
            # Hata durumunda işlemi geri al
            db_user.phone_number = old_phone
            db.commit()
            raise
        except Exception as e:
            # Hata durumunda işlemi geri al
            db_user.phone_number = old_phone
            db.commit()
            raise HTTPException(
                status_code=500,
                detail=f"Telefon numarası güncellendi ancak doğrulama kodu gönderilemedi: {str(e)}"
            )

    # Diğer alanları güncelle
    updates = user.dict()
    updates["phone_number"] = normalized_phone
    for key, value in updates.items():
        if value is not None:
            setattr(db_user, key, value)

    db_user.updated_at = datetime.now()
    db.commit()
    db.refresh(db_user)

    return schemas.UserBase(
        id=db_user.id,
        name_surname=db_user.name_surname,
        email=db_user.email,
        phone_number=db_user.phone_number,
        phone_verified=db_user.phone_verified,
        email_verified=db_user.email_verified,
        created_at=db_user.created_at.isoformat() if db_user.created_at else "",
        updated_at=db_user.updated_at.isoformat() if db_user.updated_at else ""
    )


@router.delete("/users/{user_id}")
def delete_user(user_id: int, db: Session = Depends(get_db), actor=Depends(current_user)):
    owned_resource(db, models.User, user_id, actor, "id")
    db_user = db.query(models.User).filter(models.User.id == user_id).first()
    if not db_user:
        raise HTTPException(status_code=404, detail="User not found")
    db.delete(db_user)
    db.commit()
    return {"ok": True}


@router.post("/address", response_model=schemas.AddressBase)
def create_address(address: schemas.AddressCreate, db: Session = Depends(get_db), actor=Depends(current_user)):
    db_address = models.Address(**address.dict(), user_id=actor.id)
    db.add(db_address)
    db.commit()
    db.refresh(db_address)
    return db_address


@router.get("/address", response_model=list[schemas.AddressBase])
def get_addresses(db: Session = Depends(get_db), actor=Depends(current_user)):
    return db.query(models.Address).filter_by(user_id=actor.id).all()


@router.put("/address/{address_id}", response_model=schemas.AddressBase)
def update_address(address_id: int, address: schemas.AddressUpdate, db: Session = Depends(get_db), actor=Depends(current_user)):
    owned_resource(db, models.Address, address_id, actor)
    db_address = db.query(models.Address).filter(models.Address.id == address_id).first()
    if not db_address:
        raise HTTPException(status_code=404, detail="Address not found")
    for key, value in address.dict().items():
        setattr(db_address, key, value)
    db.commit()
    db.refresh(db_address)
    return db_address


@router.delete("/address/{address_id}")
def delete_address(address_id: int, db: Session = Depends(get_db), actor=Depends(current_user)):
    owned_resource(db, models.Address, address_id, actor)
    db_address = db.query(models.Address).filter(models.Address.id == address_id).first()
    if not db_address:
        raise HTTPException(status_code=404, detail="Address not found")
    db.delete(db_address)
    db.commit()
    return {"ok": True}


@router.post("/users_address", response_model=schemas.UsersAddressBase)
def create_users_address(ua: schemas.UsersAddressCreate, db: Session = Depends(get_db), actor=Depends(current_user)):
    require_owner(ua.user_id, actor)
    owned_resource(db, models.Address, ua.address_id, actor)
    try:
        db_ua = models.UsersAddress(**ua.dict())
        db.add(db_ua)
        db.commit()
        db.refresh(db_ua)
        return db_ua
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Error creating users_address: {str(e)}")


@router.get("/users_address", response_model=list[schemas.UsersAddressBase])
def get_users_addresses(db: Session = Depends(get_db), actor=Depends(current_user)):
    return db.query(models.UsersAddress).filter_by(user_id=actor.id).all()


@router.put("/users_address/{ua_id}", response_model=schemas.UsersAddressBase)
def update_users_address(ua_id: int, ua: schemas.UsersAddressUpdate, db: Session = Depends(get_db), actor=Depends(current_user)):
    owned_resource(db, models.UsersAddress, ua_id, actor)
    require_owner(ua.user_id, actor)
    owned_resource(db, models.Address, ua.address_id, actor)
    db_ua = db.query(models.UsersAddress).filter(models.UsersAddress.id == ua_id).first()
    if not db_ua:
        raise HTTPException(status_code=404, detail="UsersAddress not found")
    for key, value in ua.dict().items():
        setattr(db_ua, key, value)
    db.commit()
    db.refresh(db_ua)
    return db_ua


@router.delete("/users_address/{ua_id}")
def delete_users_address(ua_id: int, db: Session = Depends(get_db), actor=Depends(current_user)):
    owned_resource(db, models.UsersAddress, ua_id, actor)
    db_ua = db.query(models.UsersAddress).filter(models.UsersAddress.id == ua_id).first()
    if not db_ua:
        raise HTTPException(status_code=404, detail="UsersAddress not found")
    db.delete(db_ua)
    db.commit()
    return {"ok": True}


@router.post("/users/login", response_model=schemas.UserLoginResponse)
def login_user(email: str = Form(...), password: str = Form(...), db: Session = Depends(get_db)):
    try:
        user = db.query(models.User).filter(models.User.email == email).first()

        if not user or not verify_password(password, user.password):
            raise HTTPException(status_code=401, detail="E-posta veya şifre hatalı!")

        return schemas.UserLoginResponse(
            access_token=issue_access_token(user, "user"),
            id=user.id,
            name_surname=user.name_surname,
            email=user.email,
            phone_number=user.phone_number,
            phone_verified=user.phone_verified,
            email_verified=user.email_verified,
            created_at=user.created_at.isoformat(),
            updated_at=user.updated_at.isoformat()
        )
    except HTTPException:
        # HTTPException'ları tekrar fırlat (401, 404, 400 gibi)
        raise
    except Exception as e:
        # Sadece gerçek sunucu hatalarında 500 döndür
        raise HTTPException(status_code=500, detail="Internal server error")


@router.post("/users/{user_id}/follow-seller/{seller_id}")
def follow_seller(user_id: int, seller_id: int, db: Session = Depends(get_db), actor=Depends(current_user)):
    """Kullanıcı satıcıyı takip etsin"""
    owned_resource(db, models.User, user_id, actor, "id")
    try:
        # Kullanıcı ve satıcı var mı kontrol et
        user = db.query(models.User).filter(models.User.id == user_id).first()
        seller = db.query(models.Seller).filter(models.Seller.id == seller_id).first()

        if not user:
            raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı")
        if not seller:
            raise HTTPException(status_code=404, detail="Satıcı bulunamadı")

        # Zaten takip ediliyor mu kontrol et
        existing_follow = db.query(models.UsersSellers).filter(
            models.UsersSellers.user_id == user_id,
            models.UsersSellers.seller_id == seller_id
        ).first()

        if existing_follow:
            raise HTTPException(status_code=400, detail="Bu satıcıyı zaten takip ediyorsunuz")

        # Takip kaydı oluştur
        new_follow = models.UsersSellers(
            user_id=user_id,
            seller_id=seller_id
        )
        db.add(new_follow)

        # Satıcının takipçi sayısını SQL ile güncelle
        db.query(models.Seller).filter_by(id=seller_id).update({
            "followers_count": func.coalesce(models.Seller.followers_count, 0) + 1,
        })

        db.commit()

        return {"message": "Satıcı başarıyla takip edildi", "success": True}

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail="Takip işlemi başarısız")


@router.delete("/users/{user_id}/unfollow-seller/{seller_id}")
def unfollow_seller(user_id: int, seller_id: int, db: Session = Depends(get_db), actor=Depends(current_user)):
    """Kullanıcı satıcıyı takipten çıkarsın"""
    owned_resource(db, models.User, user_id, actor, "id")
    try:
        # Takip kaydını bul ve sil
        follow_record = db.query(models.UsersSellers).filter(
            models.UsersSellers.user_id == user_id,
            models.UsersSellers.seller_id == seller_id
        ).first()

        if not follow_record:
            raise HTTPException(status_code=404, detail="Takip kaydı bulunamadı")

        # Satıcının takipçi sayısını SQL ile güncelle
        db.query(models.Seller).filter_by(id=seller_id).update({
            "followers_count": case(
                (models.Seller.followers_count > 0, models.Seller.followers_count - 1), else_=0,
            ),
        })

        db.delete(follow_record)
        db.commit()

        return {"message": "Satıcı takipten çıkarıldı", "success": True}

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail="Takipten çıkarma işlemi başarısız")


@router.get("/users/{user_id}/followed-sellers")
def get_followed_sellers(user_id: int, db: Session = Depends(get_db)):
    """Kullanıcının takip ettiği satıcıları getir"""
    try:
        # Kullanıcı var mı kontrol et
        user = db.query(models.User).filter(models.User.id == user_id).first()
        if not user:
            raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı")

        # Takip edilen satıcıları getir
        followed_sellers = db.query(models.Seller).join(
            models.UsersSellers,
            models.Seller.id == models.UsersSellers.seller_id
        ).filter(
            models.UsersSellers.user_id == user_id
        ).all()

        # Basit satıcı bilgilerini döndür
        seller_list = []
        for seller in followed_sellers:
            seller_list.append({
                "id": seller.id,
                "store_name": seller.store_name,
                "store_logo_url": seller.store_logo_url,
                "store_description": seller.store_description
            })

        return {"followed_sellers": seller_list, "count": len(seller_list)}

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail="Takip edilen satıcılar getirilemedi")


@router.get("/users/{user_id}/is-following/{seller_id}")
def check_if_following(user_id: int, seller_id: int, db: Session = Depends(get_db)):
    """Kullanıcı bu satıcıyı takip ediyor mu kontrol et"""
    try:
        follow_record = db.query(models.UsersSellers).filter(
            models.UsersSellers.user_id == user_id,
            models.UsersSellers.seller_id == seller_id
        ).first()

        return {"is_following": follow_record is not None}

    except Exception as e:
        return {"is_following": False}
