from fastapi import FastAPI, File, UploadFile, Depends, HTTPException, Form, Body
from fastapi.exception_handlers import request_validation_exception_handler
from fastapi.exceptions import RequestValidationError
from fastapi.staticfiles import StaticFiles
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from sqlalchemy import text, case, func
from app.db import SessionLocal, engine
import app.models as models
import app.schemas as schemas
import os
import shutil
import uuid
import random
import string
from datetime import datetime, timedelta
import base64
import hashlib
import hmac
import secrets
import re
from app.auth import issue_access_token, read_access_token, password_stamp, signing_key
from app.phone_numbers import normalize_phone_number
from app.services.twilio_sms_service import twilio_sms_service
from app.services.sms_language_manager import sms_language_manager
from app.services.email_service import email_service
from dotenv import load_dotenv

# Environment variables'ları yükle
BASE_DIR = os.path.dirname(os.path.dirname(__file__))
load_dotenv(os.path.join(BASE_DIR, "config.env"))

models.Base.metadata.create_all(bind=engine)
app = FastAPI()


SENSITIVE_FIELDS = {"password", "current_password", "new_password", "new_password_again", "verification_code",
                    "access_token", "authorization", "card_token", "card_number", "cvc"}


def omit_passwords(value):
    """Remove password fields from echoed validation input, including nested bodies."""
    if isinstance(value, dict):
        return {
            key: omit_passwords(child)
            for key, child in value.items()
            if str(key).lower() not in SENSITIVE_FIELDS
        }
    if isinstance(value, list):
        return [omit_passwords(child) for child in value]
    return value


@app.exception_handler(RequestValidationError)
async def password_safe_validation_error(request, exc):
    errors = []
    for error in exc.errors():
        error = dict(error)
        location = error.get("loc", ())
        if any(str(part).lower() in SENSITIVE_FIELDS for part in location) or (
            tuple(location) == ("body",)
            and not isinstance(error.get("input"), (dict, list))
        ):
            # A rejected password or unparsed body can contain raw credentials.
            error.pop("input", None)
        elif "input" in error:
            error["input"] = omit_passwords(error["input"])
        errors.append(error)
    return await request_validation_exception_handler(
        request, RequestValidationError(errors)
    )


# Statik dosya servisi ekle
app.mount("/uploads", StaticFiles(directory=os.path.join(BASE_DIR, "uploads")), name="uploads")

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


bearer = HTTPBearer(auto_error=False)


def current_actor(credentials: HTTPAuthorizationCredentials = Depends(bearer), db: Session = Depends(get_db)):
    if credentials is None:
        raise HTTPException(401, "Authentication required", headers={"WWW-Authenticate": "Bearer"})
    claims = read_access_token(credentials.credentials)
    model = models.User if claims["role"] == "user" else models.Seller
    actor = db.get(model, claims["id"])
    if actor is None or not hmac.compare_digest(claims["stamp"], password_stamp(actor.password)):
        raise HTTPException(401, "Invalid or expired credentials", headers={"WWW-Authenticate": "Bearer"})
    return actor


def current_user(actor=Depends(current_actor)):
    if not isinstance(actor, models.User):
        raise HTTPException(403, "User credentials required")
    return actor


def optional_actor(credentials: HTTPAuthorizationCredentials = Depends(bearer), db: Session = Depends(get_db)):
    return current_actor(credentials, db) if credentials else None


def current_seller(actor=Depends(current_actor)):
    if not isinstance(actor, models.Seller):
        raise HTTPException(403, "Seller credentials required")
    return actor


def require_owner(owner_id, actor):
    if owner_id != actor.id:
        raise HTTPException(403, "Resource belongs to another account")


def owned_resource(db, model, resource_id, actor, owner_field="user_id"):
    resource = db.get(model, resource_id)
    if resource is None:
        raise HTTPException(404, "Resource not found")
    require_owner(getattr(resource, owner_field), actor)
    return resource


def account_for_reset(db, phone):
    # Legacy profiles used several phone formats; never pick arbitrarily if duplicated.
    matches = []
    for user in db.query(models.User).all():
        try:
            if normalize_phone_number(user.phone_number or "") == phone:
                matches.append(user)
        except HTTPException:
            continue
    return matches[0] if len(matches) == 1 else None


def ensure_user_contacts_available(db, phone, email, except_id=None):
    normalized = normalize_phone_number(phone)
    for user in db.query(models.User).filter(models.User.id != except_id).all():
        if user.email == email:
            raise HTTPException(400, "Email is already registered")
        try:
            other_phone = normalize_phone_number(user.phone_number or "")
        except HTTPException:
            continue
        if other_phone == normalized:
            raise HTTPException(400, "Phone number is already registered")


def phone_records(db, model, field, phone):
    """Find canonical matches while old development data is being migrated."""
    normalized = normalize_phone_number(phone)
    matches = []
    for record in db.query(model).all():
        try:
            if normalize_phone_number(getattr(record, field) or "") == normalized:
                matches.append(record)
        except HTTPException:
            continue
    return normalized, matches


def one_phone_record(db, model, field, phone):
    normalized, matches = phone_records(db, model, field, phone)
    if len(matches) > 1:
        raise HTTPException(409, "Phone identity has conflicting records")
    return normalized, matches[0] if matches else None


def delete_phone_records(db, model, field, phone):
    normalized, matches = phone_records(db, model, field, phone)
    for record in matches:
        db.delete(record)
    return normalized


def ensure_seller_phone_available(db, phone, except_id=None):
    normalized, matches = phone_records(db, models.Seller, "phone", phone)
    if any(record.id != except_id for record in matches):
        raise HTTPException(400, "Phone number is already registered")
    return normalized


def phone_verification_owner(db, phone, role, actor):
    model = models.User if role == "user" else models.Seller
    field = "phone_number" if role == "user" else "phone"
    normalized, matches = phone_records(db, model, field, phone)
    if not matches:
        return normalized, None  # Public registration challenge, not an existing account mutation.
    if len(matches) > 1:
        raise HTTPException(409, "Phone identity has conflicting records")
    if actor is None:
        raise HTTPException(401, "Authentication required")
    if not isinstance(actor, model):
        raise HTTPException(403, "Wrong account type")
    for account in matches:
        require_owner(account.id, actor)
    return normalized, matches[0]


def reset_code_hash(phone, code):
    return hmac.new(signing_key(), ("password-reset:" + phone + ":" + code).encode(), hashlib.sha256).hexdigest()


def public_user(user):
    return schemas.UserBase(
        id=user.id, name_surname=user.name_surname, email=user.email,
        phone_number=user.phone_number, phone_verified=user.phone_verified,
        email_verified=user.email_verified,
        created_at=user.created_at.isoformat() if user.created_at else "",
        updated_at=user.updated_at.isoformat() if user.updated_at else "",
    )


@app.get("/users/me", response_model=schemas.UserBase)
def get_my_profile(actor=Depends(current_user)):
    return public_user(actor)


@app.put("/users/me", response_model=schemas.UserBase)
def update_my_profile(user: schemas.UserUpdate, actor=Depends(current_user), db: Session = Depends(get_db)):
    return update_user(actor.id, user, db, actor)


@app.put("/users/me/password")
def change_password(payload: schemas.PasswordChange, actor=Depends(current_user), db: Session = Depends(get_db)):
    if not verify_password(payload.current_password, actor.password):
        raise HTTPException(401, "Current password is incorrect")
    if payload.new_password != payload.new_password_again:
        raise HTTPException(400, "New password and confirmation must match")
    actor.password = hash_password(payload.new_password)
    db.query(models.PasswordResetVerification).filter_by(user_id=actor.id).delete()
    db.commit()
    return {"message": "Password changed; please sign in again"}


@app.post("/auth/forgot-password/request")
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


@app.post("/auth/forgot-password/reset")
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

# --- PASSWORD HASHING HELPERS ---
PBKDF2_ITERATIONS = 100_000
SALT_BYTES = 16

def hash_password(plain_password: str) -> str:
    """Return a salted PBKDF2 hash for the given password."""
    salt = os.urandom(SALT_BYTES)
    pwd_hash = hashlib.pbkdf2_hmac(
        "sha256",
        plain_password.encode("utf-8"),
        salt,
        PBKDF2_ITERATIONS,
    )
    # Store as base64(salt):base64(hash) to keep column as string
    return f"{base64.b64encode(salt).decode('utf-8')}:{base64.b64encode(pwd_hash).decode('utf-8')}"

def verify_password(plain_password: str, stored_password: str) -> bool:
    """
    Check a plaintext password against a stored salted hash.
    Supports legacy plaintext records for backward compatibility.
    """
    if not stored_password:
        return False

    # Legacy plaintext support
    if ":" not in stored_password:
        return hmac.compare_digest(plain_password, stored_password)

    try:
        salt_b64, hash_b64 = stored_password.split(":", 1)
        salt = base64.b64decode(salt_b64.encode("utf-8"))
        stored_hash = base64.b64decode(hash_b64.encode("utf-8"))
        new_hash = hashlib.pbkdf2_hmac(
            "sha256",
            plain_password.encode("utf-8"),
            salt,
            PBKDF2_ITERATIONS,
        )
        return hmac.compare_digest(new_hash, stored_hash)
    except Exception:
        return False

# --- PAYMENT TOKENIZATION MOCK (replace with iyzico/iyzipay or similar in prod) ---
def card_response(card):
    return schemas.CreditCardBase(
        id=card.id, user_id=card.user_id, provider=card.provider,
        card_token=card.card_token, card_brand=card.card_brand, last4=card.last4,
        expiry_month=card.expiry_month, expiry_year=card.expiry_year,
        is_default=card.is_default,
        created_at=card.created_at.isoformat() if card.created_at else None,
        updated_at=card.updated_at.isoformat() if card.updated_at else None,
    )


def remember_tokenized_card(db, actor, **data):
    if not data.get("card_token"):
        raise HTTPException(400, "Card tokenization failed")
    card = db.query(models.CreditCard).filter_by(card_token=data["card_token"]).first()
    if card is not None:
        require_owner(card.user_id, actor)
    else:
        card = models.CreditCard(
            **data, user_id=actor.id,
            provider="mock" if data["card_token"].startswith("mock_") else "iyzico",
        )
        db.add(card)
    db.commit()
    return schemas.TokenizeCardResponse(**data)


@app.post("/tokenize", response_model=schemas.TokenizeCardResponse)
def tokenize_card(req: schemas.TokenizeCardRequest, db: Session = Depends(get_db), actor=Depends(current_user)):
    require_owner(req.user_id, actor)
    # Basit validasyonlar (gerçek dünyada iyzico gibi bir gateway ile doğrulayın)
    digits = ''.join([c for c in req.card_number if c.isdigit()])
    if len(digits) < 12 or len(digits) > 19:
        raise HTTPException(status_code=400, detail="Geçersiz kart numarası")

    # Luhn
    def luhn_ok(num: str) -> bool:
        total = 0
        alt = False
        for ch in num[::-1]:
            n = ord(ch) - 48
            if alt:
                n *= 2
                if n > 9:
                    n -= 9
            total += n
            alt = not alt
        return total % 10 == 0

    if not luhn_ok(digits):
        raise HTTPException(status_code=400, detail="Kart doğrulaması başarısız (Luhn)")

    # Tarih kontrolü
    now = datetime.utcnow()
    exp_year = req.expire_year
    exp_month = req.expire_month
    if exp_month < 1 or exp_month > 12:
        raise HTTPException(status_code=400, detail="Geçersiz ay")
    # Son gün olarak ayın 28'ini varsayalım
    exp_cmp = datetime(exp_year, exp_month, 28)
    if exp_cmp < datetime(now.year, now.month, 1):
        raise HTTPException(status_code=400, detail="Kart son kullanma tarihi geçmiş")

    # Marka
    brand = 'unknown'
    if digits.startswith('4'):
        brand = 'visa'
    elif digits.startswith('34') or digits.startswith('37'):
        brand = 'amex'
    elif digits[:2].isdigit() and (51 <= int(digits[:2]) <= 55):
        brand = 'mastercard'
    elif digits.startswith('6'):
        brand = 'discover'

    # Gerçek kart doğrulama ve tokenization
    import os
    api_key = os.getenv('IYZIPAY_API_KEY')
    secret_key = os.getenv('IYZIPAY_SECRET_KEY')
    base_url = os.getenv('IYZIPAY_BASE_URL', 'https://api.iyzipay.com')
    test_mode = os.getenv('PAYMENT_TEST_MODE', 'true').lower() == 'true'
    placeholder_keys = any([
        not api_key,
        not secret_key,
        'XXXX' in (api_key or ''),
        'XXXX' in (secret_key or '')
    ])
    
    # Geliştirme ortamı veya eksik anahtarlar için mock token üret
    if test_mode or placeholder_keys:
        mock_token = f"mock_{uuid.uuid4().hex}"
        return remember_tokenized_card(db, actor,
            card_token=mock_token,
            card_brand=brand,
            last4=digits[-4:],
            expiry_month=req.expire_month,
            expiry_year=req.expire_year,
        )
    
    # URL'den protokolü kaldır
    if base_url.startswith('https://'):
        base_url = base_url.replace('https://', '')
    elif base_url.startswith('http://'):
        base_url = base_url.replace('http://', '')
    
    try:
        import iyzipay
        user = db.query(models.User).filter(models.User.id == req.user_id).first()
        user_email = user.email if user else None
        
        # Türkçe karakterleri temizle
        card_holder_name = req.card_holder_name.encode('ascii', 'ignore').decode('ascii')
        
        options = {
            'api_key': api_key,
            'secret_key': secret_key,
            'base_url': base_url
        }

        request = {
            'locale': 'tr',
            'conversationId': str(uuid.uuid4()),
            'email': user_email,
            'externalId': f'user-{req.user_id}',
            'card': {
                'cardAlias': 'AppCard',
                'cardHolderName': card_holder_name,
                'cardNumber': digits,
                'expireMonth': str(req.expire_month).zfill(2),
                'expireYear': str(req.expire_year),
            }
        }
        
        card_instance = iyzipay.Card()
        res = card_instance.create(request, options)
        
        import json
        data = json.loads(res.read().decode('utf-8')) if hasattr(res, 'read') else res
        
        if data.get('status') != 'success':
            raise HTTPException(status_code=400, detail=data.get('errorMessage', 'Kart doğrulanamadı'))
            
        card_user_key = data.get('cardUserKey')
        card_token = data.get('cardToken')
        merged_token = f"{card_user_key}:{card_token}" if card_user_key and card_token else card_token
        
        return remember_tokenized_card(db, actor,
            card_token=merged_token,
            card_brand=brand,
            last4=digits[-4:],
            expiry_month=req.expire_month,
            expiry_year=req.expire_year,
        )
    except ImportError:
        # SDK yoksa da mock token üret, kullanıcıya gerçek ortam için uyarı ver
        mock_token = f"mock_{uuid.uuid4().hex}"
        return remember_tokenized_card(db, actor,
            card_token=mock_token,
            card_brand=brand,
            last4=digits[-4:],
            expiry_month=req.expire_month,
            expiry_year=req.expire_year,
        )
    except Exception as e:
        raise HTTPException(status_code=400, detail=f'Kart doğrulanamadı: {str(e)}')

# --- CHARGE PAYMENT ---
@app.post("/charge", response_model=schemas.ChargeResponse)
def charge_payment(req: schemas.ChargeRequest, db: Session = Depends(get_db), actor=Depends(current_user)):
    require_owner(req.user_id, actor)
    card = db.query(models.CreditCard).filter_by(card_token=req.card_token).first()
    if card is None:
        raise HTTPException(404, "Credit card not found")
    require_owner(card.user_id, actor)
    import os, json
    api_key = os.getenv('IYZIPAY_API_KEY')
    secret_key = os.getenv('IYZIPAY_SECRET_KEY')
    base_url = os.getenv('IYZIPAY_BASE_URL', 'https://api.iyzipay.com')
    # URL'den protokolü kaldır
    if base_url.startswith('https://'):
        base_url = base_url.replace('https://', '')
    elif base_url.startswith('http://'):
        base_url = base_url.replace('http://', '')

    if not api_key or not secret_key:
        return schemas.ChargeResponse(status='failure', error_message='Iyzico API anahtarları eksik')

    try:
        import iyzipay
        user = db.query(models.User).filter(models.User.id == req.user_id).first()
        if not user:
            return schemas.ChargeResponse(status='failure', error_message='Kullanıcı bulunamadı')

        # iyzipay SDK'nın beklediği options formatı
        options = {
            'api_key': api_key,
            'secret_key': secret_key,
            'base_url': base_url
        }

        # Token string birleştirilmiş ise ayır
        card_user_key, card_token = None, req.card_token
        if ':' in req.card_token:
            parts = req.card_token.split(':', 1)
            card_user_key, card_token = parts[0], parts[1]

        request = {
            'locale': 'tr',
            'conversationId': str(uuid.uuid4()),
            'price': str(req.price),
            'paidPrice': str(req.paid_price),
            'currency': req.currency,
            'installment': req.installment or 1,
            'paymentChannel': req.payment_channel or 'WEB',
            'paymentGroup': req.payment_group or 'PRODUCT',
            'buyer': {
                'id': str(user.id),
                'name': (user.name_surname.split(' ')[0] if user.name_surname else 'Name').encode('ascii', 'ignore').decode('ascii'),
                'surname': (user.name_surname.split(' ')[-1] if user.name_surname else 'Surname').encode('ascii', 'ignore').decode('ascii'),
                'email': user.email,
                'identityNumber': '11111111111',
                'registrationAddress': 'Address',
                'ip': '85.34.78.112',
                'city': 'Istanbul',
                'country': 'Turkey',
            },
            'paymentCard': {
                'cardUserKey': card_user_key,
                'cardToken': card_token,
            },
            'basketItems': [
                {
                    'id': req.basket_id or 'BASKET',
                    'name': 'Sipariş',
                    'category1': 'Genel',
                    'itemType': 'PHYSICAL',
                    'price': str(req.price),
                }
            ]
        }

        payment = iyzipay.Payment.create(request, options)
        data = json.loads(payment.read().decode('utf-8')) if hasattr(payment, 'read') else payment
        if data.get('status') == 'success':
            return schemas.ChargeResponse(status='success', payment_id=data.get('paymentId'))
        return schemas.ChargeResponse(status='failure', error_message=data.get('errorMessage'))
    except ImportError:
        return schemas.ChargeResponse(status='failure', error_message='iyzipay SDK kurulu değil (pip install iyzipay)')
    except Exception as e:
        return schemas.ChargeResponse(status='failure', error_message=str(e))

# Yardımcı fonksiyonlar
def delete_file_safely(file_path: str, file_type: str = "dosya"):
    """Güvenli dosya silme fonksiyonu"""
    try:
        import os
        if os.path.exists(file_path):
            os.remove(file_path)
            return True
        else:
            return False
    except Exception as e:
        return False


def delete_unreferenced_product_image(db, image_url, product_id):
    # A seller may reuse a public image URL; that does not authorize deleting
    # an image still referenced by another product (or a path outside uploads).
    filename = image_url.rsplit("/", 1)[-1]
    if not filename or "\\" in filename or ":" in filename or filename in (".", ".."):
        return
    other_images = db.query(models.Product.product_image_url).filter(models.Product.id != product_id).all()
    if any(url and url.rsplit("/", 1)[-1] == filename for (url,) in other_images):
        return
    delete_file_safely(os.path.join("uploads", "Product_Image", filename), "Product image")

def generate_verification_code():
    """6 haneli doğrulama kodu oluştur"""
    return ''.join(random.choices(string.digits, k=6))

def send_sms_verification(phone_number: str, code: str, language: str = None):
    """Global SMS doğrulama kodu gönder (çok dilli)"""
    try:
        formatted_phone = normalize_phone_number(phone_number)

        # Dil belirtilmemişse telefon numarasından tahmin et
        if not language:
            language = sms_language_manager.get_language_from_phone(formatted_phone)


        # Çok dilli SMS gönder (marka adı ile)
        result = twilio_sms_service.send_verification_sms(formatted_phone, code, language)

        if result['success']:
            return True
        else:
            return False

    except Exception as e:
        return False

# --- PRODUCT CRUD ---
@app.post("/products", response_model=schemas.ProductBase)
def create_product(product: schemas.ProductCreate, db: Session = Depends(get_db), actor=Depends(current_seller)):
    if product.seller_id is not None:
        require_owner(product.seller_id, actor)
    product.seller_id = actor.id
    db_product = models.Product(**product.dict())
    db.add(db_product)
    db.commit()
    db.refresh(db_product)
    return schemas.ProductBase(
        id=db_product.id,
        product_name=db_product.product_name,
        product_price=db_product.product_price,
        product_description=db_product.product_description,
        product_category=db_product.product_category,
        product_image_url=db_product.product_image_url,
        seller_id=db_product.seller_id
    )

@app.get("/products", response_model=list[schemas.ProductBase])
def get_products(db: Session = Depends(get_db)):
    products = db.query(models.Product).all()
    return [
        schemas.ProductBase(
            id=product.id,
            product_name=product.product_name,
            product_price=product.product_price,
            product_description=product.product_description,
            product_category=product.product_category,
            product_image_url=product.product_image_url,
            seller_id=product.seller_id
        )
        for product in products
    ]

@app.put("/products/{product_id}", response_model=schemas.ProductBase)
def update_product(product_id: int, product: schemas.ProductUpdate, db: Session = Depends(get_db), actor=Depends(current_seller)):
    owned_resource(db, models.Product, product_id, actor, "seller_id")
    if product.seller_id is not None:
        require_owner(product.seller_id, actor)
    product.seller_id = actor.id
    db_product = db.query(models.Product).filter(models.Product.id == product_id).first()
    if not db_product:
        raise HTTPException(status_code=404, detail="Product not found")

    # Eski fotoğraf URL'ini sakla
    old_image_url = db_product.product_image_url

    # Ürün bilgilerini güncelle
    for key, value in product.dict().items():
        setattr(db_product, key, value)

    # Eğer fotoğraf değiştiyse eski fotoğrafı sil
    if old_image_url and old_image_url != db_product.product_image_url:
        delete_unreferenced_product_image(db, old_image_url, product_id)

    db.commit()
    db.refresh(db_product)
    return schemas.ProductBase(
        id=db_product.id,
        product_name=db_product.product_name,
        product_price=db_product.product_price,
        product_description=db_product.product_description,
        product_category=db_product.product_category,
        product_image_url=db_product.product_image_url,
        seller_id=db_product.seller_id
    )

@app.delete("/products/{product_id}")
def delete_product(product_id: int, db: Session = Depends(get_db), actor=Depends(current_seller)):
    owned_resource(db, models.Product, product_id, actor, "seller_id")
    db_product = db.query(models.Product).filter(models.Product.id == product_id).first()
    if not db_product:
        raise HTTPException(status_code=404, detail="Product not found")

    # Ürün fotoğrafını sil
    if db_product.product_image_url:
        delete_unreferenced_product_image(db, db_product.product_image_url, product_id)

    # Ürünü veritabanından sil
    db.delete(db_product)
    db.commit()
    return {"ok": True}

# --- PHONE VERIFICATION ---
@app.post("/send-verification-code", response_model=schemas.PhoneVerificationResponse)
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

@app.post("/verify-phone", response_model=schemas.PhoneVerificationResponse)
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

@app.post("/users/{user_id}/send-phone-verification", response_model=schemas.PhoneVerificationResponse)
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

# --- SMS ENDPOINTS ---
@app.post("/sms/welcome")
def send_welcome_sms(phone_number: str, language: str = None, user_name: str = "", actor=Depends(current_actor)):
    raise HTTPException(403, "Direct SMS utilities are disabled; use the application workflow")

@app.post("/sms/order-status")
def send_order_status_sms(phone_number: str, order_number: str, status: str, language: str = None, actor=Depends(current_actor)):
    raise HTTPException(403, "Direct SMS utilities are disabled; use the application workflow")

@app.post("/sms/promotional")
def send_promotional_sms(phone_number: str, discount: str, valid_until: str, language: str = None, actor=Depends(current_actor)):
    raise HTTPException(403, "Direct SMS utilities are disabled; use the application workflow")

@app.get("/sms/languages")
def get_supported_languages():
    """Desteklenen dilleri listele"""
    languages = sms_language_manager.get_supported_languages()
    return {
        "supported_languages": languages,
        "default_language": sms_language_manager.default_language,
        "brand_name": sms_language_manager.brand_name
    }

@app.get("/sms/check-sender-id")
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

# --- USER CRUD ---
@app.post("/users", response_model=schemas.UserBase)
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

@app.get("/users", response_model=list[schemas.UserBase])
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

@app.put("/users/{user_id}", response_model=schemas.UserBase)
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

@app.delete("/users/{user_id}")
def delete_user(user_id: int, db: Session = Depends(get_db), actor=Depends(current_user)):
    owned_resource(db, models.User, user_id, actor, "id")
    db_user = db.query(models.User).filter(models.User.id == user_id).first()
    if not db_user:
        raise HTTPException(status_code=404, detail="User not found")
    db.delete(db_user)
    db.commit()
    return {"ok": True}

# --- ADDRESS CRUD ---
@app.post("/address", response_model=schemas.AddressBase)
def create_address(address: schemas.AddressCreate, db: Session = Depends(get_db), actor=Depends(current_user)):
    db_address = models.Address(**address.dict(), user_id=actor.id)
    db.add(db_address)
    db.commit()
    db.refresh(db_address)
    return db_address

@app.get("/address", response_model=list[schemas.AddressBase])
def get_addresses(db: Session = Depends(get_db), actor=Depends(current_user)):
    return db.query(models.Address).filter_by(user_id=actor.id).all()

@app.put("/address/{address_id}", response_model=schemas.AddressBase)
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

@app.delete("/address/{address_id}")
def delete_address(address_id: int, db: Session = Depends(get_db), actor=Depends(current_user)):
    owned_resource(db, models.Address, address_id, actor)
    db_address = db.query(models.Address).filter(models.Address.id == address_id).first()
    if not db_address:
        raise HTTPException(status_code=404, detail="Address not found")
    db.delete(db_address)
    db.commit()
    return {"ok": True}

# --- CREDIT CARD CRUD (tokenized) ---
@app.post("/credit_card", response_model=schemas.CreditCardBase)
def create_credit_card(card: schemas.CreditCardCreate, db: Session = Depends(get_db), actor=Depends(current_user)):
    require_owner(card.user_id, actor)
    db_card = db.query(models.CreditCard).filter_by(card_token=card.card_token).first()
    if db_card is None:
        raise HTTPException(400, "Tokenize this card before saving it")
    require_owner(db_card.user_id, actor)
    # Tokenization already saved authoritative metadata and its owner.
    db_card.is_default = card.is_default
    db.commit()
    return card_response(db_card)

@app.get("/credit_card", response_model=list[schemas.CreditCardBase])
def get_credit_cards(db: Session = Depends(get_db), actor=Depends(current_user)):
    cards = db.query(models.CreditCard).filter_by(user_id=actor.id).all()
    response_cards = []
    for card in cards:
        response_cards.append({
            'id': card.id,
            'user_id': card.user_id,
            'provider': card.provider,
            'card_token': card.card_token,
            'card_brand': card.card_brand,
            'last4': card.last4,
            'expiry_month': card.expiry_month,
            'expiry_year': card.expiry_year,
            'is_default': card.is_default,
            'created_at': card.created_at.isoformat() if card.created_at else None,
            'updated_at': card.updated_at.isoformat() if card.updated_at else None,
        })
    return response_cards

@app.put("/credit_card/{card_id}", response_model=schemas.CreditCardBase)
def update_credit_card(card_id: int, card: schemas.CreditCardUpdate, db: Session = Depends(get_db), actor=Depends(current_user)):
    db_card = owned_resource(db, models.CreditCard, card_id, actor)
    for field in ("card_token", "provider", "card_brand", "last4", "expiry_month", "expiry_year"):
        if getattr(card, field) != getattr(db_card, field):
            raise HTTPException(403, "Saved payment credentials cannot be replaced; tokenize a new card")
    db_card.is_default = card.is_default
    db.commit()
    return card_response(db_card)

@app.delete("/credit_card/{card_id}")
def delete_credit_card(card_id: int, db: Session = Depends(get_db), actor=Depends(current_user)):
    owned_resource(db, models.CreditCard, card_id, actor)
    db_card = db.query(models.CreditCard).filter(models.CreditCard.id == card_id).first()
    if not db_card:
        raise HTTPException(status_code=404, detail="Credit card not found")
    db.delete(db_card)
    db.commit()
    return {"ok": True}

# --- ORDER CRUD ---
@app.post("/order", response_model=schemas.OrderBase)
def create_order(order_data: dict, db: Session = Depends(get_db), actor=Depends(current_user)):
    if order_data.get('user_id') is not None:
        require_owner(order_data['user_id'], actor)
    owned_resource(db, models.Address, order_data.get('order_address'), actor)
    if order_data.get('card_id') is not None:
        owned_resource(db, models.CreditCard, order_data['card_id'], actor)
    try:

        # Parse dates from DD/MM/YYYY format to datetime objects
        from datetime import datetime

        def parse_date(date_str):
            if isinstance(date_str, str):
                try:
                    return datetime.strptime(date_str, '%d/%m/%Y')
                except ValueError:
                    # Try alternative format if the first one fails
                    try:
                        return datetime.strptime(date_str, '%Y-%m-%d')
                    except ValueError:
                        return datetime.now()  # Fallback to current date
            return date_str

        # Extract order details and payment info
        order_info = {
            'order_code': order_data.get('order_code'),
            'order_created_date': parse_date(order_data.get('order_created_date')),
            'order_estimated_delivery': parse_date(order_data.get('order_estimated_delivery')),
            'order_cargo_company': order_data.get('order_cargo_company'),
            'order_address': order_data.get('order_address'),
            'order_status': 'pending',
            'order_delivered_date': None
        }
        # Eğer sipariş delivered olarak oluşturuluyorsa bugünün tarihi ata
        if order_info['order_status'] == 'delivered':
            order_info['order_delivered_date'] = datetime.now()

        # Eğer kargo şirketi belirtilmemişse, sipariş edilen ürünlerin satıcılarının kargo şirketini kullan
        if not order_info['order_cargo_company']:
            # Sipariş edilen ürünlerin satıcılarını bul
            cart_items = order_data.get('cart_items', [])
            if cart_items:
                # İlk ürünün satıcısının kargo şirketini kullan
                first_product_id = cart_items[0].get('product', {}).get('seller_id')
                if first_product_id:
                    seller = db.query(models.Seller).filter(models.Seller.id == first_product_id).first()
                    if seller and seller.cargo_company:
                        order_info['order_cargo_company'] = seller.cargo_company
                    else:
                        order_info['order_cargo_company'] = "Araskargo"  # Varsayılan
                else:
                    order_info['order_cargo_company'] = "Araskargo"  # Varsayılan
            else:
                order_info['order_cargo_company'] = "Araskargo"  # Varsayılan

        card_id = order_data.get('card_id')
        amount = order_data.get('amount')


        # Transaction başlat
        # The authentication lookup already opened this transaction.

        # Önce siparişi oluştur
        db_order = models.Order(**order_info, user_id=actor.id)
        db.add(db_order)
        db.flush()  # ID'yi almak için flush yap ama commit etme


        # Eğer kart bilgisi verilmişse temel doğrulamalar yap
        if card_id and amount:
            db_card = db.query(models.CreditCard).filter(models.CreditCard.id == card_id).first()
            if not db_card:
                raise HTTPException(status_code=404, detail="Credit card not found")

            # Son kullanma tarihi kontrolü
            from datetime import datetime
            now = datetime.utcnow()
            exp_year = db_card.expiry_year if db_card.expiry_year >= 100 else 2000 + db_card.expiry_year
            exp_date = datetime(exp_year, db_card.expiry_month, 1)
            if exp_date < datetime(now.year, now.month, 1):
                raise HTTPException(status_code=400, detail="Card expired")

            # Gerçek çekim entegrasyonu burada yapılmalı (ödeme sağlayıcısı)
        else:
            pass

        # Transaction'ı commit et
        db.commit()

        # Şimdi seller_orders tablosuna kayıt ekle
        # Bu siparişteki ürünlerin satıcılarını bul ve seller_orders'a ekle

        # Sipariş edilen ürünleri al (users_order tablosundan)
        user_orders = db.query(models.UsersOrder).filter(
            models.UsersOrder.order_id == db_order.id
        ).all()

        # Her ürün için satıcıyı bul ve seller_orders'a ekle
        for user_order in user_orders:
            product = db.query(models.Product).filter(
                models.Product.id == user_order.product_id
            ).first()



        # Return order with proper string formatting for dates
        return schemas.OrderBase(
            id=db_order.id,
            order_code=db_order.order_code,
            order_created_date=db_order.order_created_date.strftime('%Y-%m-%d') if hasattr(db_order.order_created_date, 'strftime') else str(db_order.order_created_date),
            order_estimated_delivery=db_order.order_estimated_delivery.strftime('%Y-%m-%d') if hasattr(db_order.order_estimated_delivery, 'strftime') else str(db_order.order_estimated_delivery),
            order_cargo_company=db_order.order_cargo_company,
            order_address=db_order.order_address,
            order_status=db_order.order_status,
            order_delivered_date=db_order.order_delivered_date.strftime('%Y-%m-%d') if db_order.order_delivered_date and hasattr(db_order.order_delivered_date, 'strftime') else None
        )

    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        # Hata durumunda transaction'ı rollback et
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Error creating order: {str(e)}")

@app.get("/order", response_model=list[schemas.OrderBase])
def get_orders(db: Session = Depends(get_db), actor=Depends(current_user)):
    orders = db.query(models.Order).filter_by(user_id=actor.id).all()
    result = []
    for order in orders:



        # order_delivered_date'i manuel olarak kontrol et
        delivered_date_str = None
        if order.order_delivered_date:
            if hasattr(order.order_delivered_date, 'strftime'):
                delivered_date_str = order.order_delivered_date.strftime('%Y-%m-%d')
            else:
                delivered_date_str = str(order.order_delivered_date)

        order_data = schemas.OrderBase(
            id=order.id,
            order_code=order.order_code,
            order_created_date=order.order_created_date.strftime('%Y-%m-%d') if order.order_created_date and hasattr(order.order_created_date, 'strftime') else None,
            order_estimated_delivery=order.order_estimated_delivery.strftime('%Y-%m-%d') if order.order_estimated_delivery and hasattr(order.order_estimated_delivery, 'strftime') else None,
            order_cargo_company=order.order_cargo_company,
            order_address=order.order_address,
            order_status=order.order_status,
            order_delivered_date=delivered_date_str
        )


        result.append(order_data)

    return result

@app.put("/order/{order_id}", response_model=schemas.OrderBase)
def update_order(order_id: int, order: schemas.OrderUpdate, db: Session = Depends(get_db), actor=Depends(current_user)):
    owned_resource(db, models.Address, order.order_address, actor)
    existing = db.get(models.Order, order_id)
    if order.order_status != existing.order_status:
        raise HTTPException(403, "Only the fulfilling seller may change order status")
    owned_resource(db, models.Order, order_id, actor)
    db_order = db.query(models.Order).filter(models.Order.id == order_id).first()
    if not db_order:
        raise HTTPException(status_code=404, detail="Order not found")
    for key, value in order.dict().items():
        setattr(db_order, key, datetime.fromisoformat(value) if key in ("order_created_date", "order_estimated_delivery") else value)
    db.commit()
    db.refresh(db_order)
    return schemas.OrderBase(
        id=db_order.id,
        order_code=db_order.order_code,
        order_created_date=db_order.order_created_date.strftime('%Y-%m-%d') if hasattr(db_order.order_created_date, 'strftime') else str(db_order.order_created_date),
        order_estimated_delivery=db_order.order_estimated_delivery.strftime('%Y-%m-%d') if hasattr(db_order.order_estimated_delivery, 'strftime') else str(db_order.order_estimated_delivery),
        order_cargo_company=db_order.order_cargo_company,
        order_address=db_order.order_address,
        order_status=db_order.order_status,
        order_delivered_date=db_order.order_delivered_date.strftime('%Y-%m-%d') if db_order.order_delivered_date and hasattr(db_order.order_delivered_date, 'strftime') else None
    )

@app.delete("/order/{order_id}")
def delete_order(order_id: int, db: Session = Depends(get_db), actor=Depends(current_user)):
    owned_resource(db, models.Order, order_id, actor)
    db_order = db.query(models.Order).filter(models.Order.id == order_id).first()
    if not db_order:
        raise HTTPException(status_code=404, detail="Order not found")
    db.delete(db_order)
    db.commit()
    return {"ok": True}

# --- USERS_ADDRESS CRUD ---
@app.post("/users_address", response_model=schemas.UsersAddressBase)
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

@app.get("/users_address", response_model=list[schemas.UsersAddressBase])
def get_users_addresses(db: Session = Depends(get_db), actor=Depends(current_user)):
    return db.query(models.UsersAddress).filter_by(user_id=actor.id).all()

@app.put("/users_address/{ua_id}", response_model=schemas.UsersAddressBase)
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

@app.delete("/users_address/{ua_id}")
def delete_users_address(ua_id: int, db: Session = Depends(get_db), actor=Depends(current_user)):
    owned_resource(db, models.UsersAddress, ua_id, actor)
    db_ua = db.query(models.UsersAddress).filter(models.UsersAddress.id == ua_id).first()
    if not db_ua:
        raise HTTPException(status_code=404, detail="UsersAddress not found")
    db.delete(db_ua)
    db.commit()
    return {"ok": True}

# --- USERS_CREDIT_CARD CRUD ---
@app.post("/users_credit_card", response_model=schemas.UsersCreditCardBase)
def create_users_credit_card(ucc: schemas.UsersCreditCardCreate, db: Session = Depends(get_db), actor=Depends(current_user)):
    require_owner(ucc.user_id, actor)
    owned_resource(db, models.CreditCard, ucc.credit_card_id, actor)
    db_ucc = models.UsersCreditCard(**ucc.dict())
    db.add(db_ucc)
    db.commit()
    db.refresh(db_ucc)
    return db_ucc

@app.get("/users_credit_card", response_model=list[schemas.UsersCreditCardBase])
def get_users_credit_cards(db: Session = Depends(get_db), actor=Depends(current_user)):
    return db.query(models.UsersCreditCard).filter_by(user_id=actor.id).all()

@app.put("/users_credit_card/{ucc_id}", response_model=schemas.UsersCreditCardBase)
def update_users_credit_card(ucc_id: int, ucc: schemas.UsersCreditCardUpdate, db: Session = Depends(get_db), actor=Depends(current_user)):
    owned_resource(db, models.UsersCreditCard, ucc_id, actor)
    require_owner(ucc.user_id, actor)
    owned_resource(db, models.CreditCard, ucc.credit_card_id, actor)
    db_ucc = db.query(models.UsersCreditCard).filter(models.UsersCreditCard.id == ucc_id).first()
    if not db_ucc:
        raise HTTPException(status_code=404, detail="UsersCreditCard not found")
    for key, value in ucc.dict().items():
        setattr(db_ucc, key, value)
    db.commit()
    db.refresh(db_ucc)
    return db_ucc

@app.delete("/users_credit_card/{ucc_id}")
def delete_users_credit_card(ucc_id: int, db: Session = Depends(get_db), actor=Depends(current_user)):
    owned_resource(db, models.UsersCreditCard, ucc_id, actor)
    db_ucc = db.query(models.UsersCreditCard).filter(models.UsersCreditCard.id == ucc_id).first()
    if not db_ucc:
        raise HTTPException(status_code=404, detail="UsersCreditCard not found")
    db.delete(db_ucc)
    db.commit()
    return {"ok": True}

@app.get("/sms/balance")
def get_sms_balance():
    """Twilio SMS bakiyesini sorgula"""
    result = twilio_sms_service.get_balance()
    return result

# --- USERS_ORDER CRUD ---
@app.post("/users_order", response_model=schemas.UsersOrderBase)
def create_users_order(uo: schemas.UsersOrderCreate, db: Session = Depends(get_db), actor=Depends(current_user)):
    require_owner(uo.user_id, actor)
    owned_resource(db, models.Order, uo.order_id, actor)
    if db.get(models.Product, uo.product_id) is None:
        raise HTTPException(404, "Product not found")
    try:

        db_uo = models.UsersOrder(**uo.dict())

        db.add(db_uo)
        db.commit()
        db.refresh(db_uo)

        return db_uo
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to create users_order: {str(e)}")

@app.get("/users_order", response_model=list[schemas.UsersOrderBase])
def get_users_orders(db: Session = Depends(get_db), actor=Depends(current_user)):
    return db.query(models.UsersOrder).filter_by(user_id=actor.id).all()

@app.put("/users_order/{uo_id}", response_model=schemas.UsersOrderBase)
def update_users_order(uo_id: int, uo: schemas.UsersOrderUpdate, db: Session = Depends(get_db), actor=Depends(current_user)):
    owned_resource(db, models.UsersOrder, uo_id, actor)
    require_owner(uo.user_id, actor)
    owned_resource(db, models.Order, uo.order_id, actor)
    if db.get(models.Product, uo.product_id) is None:
        raise HTTPException(404, "Product not found")
    db_uo = db.query(models.UsersOrder).filter(models.UsersOrder.id == uo_id).first()
    if not db_uo:
        raise HTTPException(status_code=404, detail="UsersOrder not found")
    for key, value in uo.dict().items():
        setattr(db_uo, key, value)
    db.commit()
    db.refresh(db_uo)
    return db_uo

@app.delete("/users_order/{uo_id}")
def delete_users_order(uo_id: int, db: Session = Depends(get_db), actor=Depends(current_user)):
    owned_resource(db, models.UsersOrder, uo_id, actor)
    db_uo = db.query(models.UsersOrder).filter(models.UsersOrder.id == uo_id).first()
    if not db_uo:
        raise HTTPException(status_code=404, detail="UsersOrder not found")
    db.delete(db_uo)
    db.commit()
    return {"ok": True}

@app.post('/upload-image')
async def upload_image(file: UploadFile = File(...), actor=Depends(current_seller)):
    upload_dir = 'uploads/Product_Image'
    os.makedirs(upload_dir, exist_ok=True)
    ext = file.filename.split('.')[-1]
    unique_name = f"{uuid.uuid4()}.{ext}"
    file_path = os.path.join(upload_dir, unique_name)
    with open(file_path, 'wb') as buffer:
        shutil.copyfileobj(file.file, buffer)
    return {"url": f"/uploads/Product_Image/{unique_name}"}

@app.get("/check-db")
def check_database(db: Session = Depends(get_db)):
    try:
        # Check if sellers table exists
        from sqlalchemy import text
        result = db.execute(text("SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'sellers')"))
        sellers_exists = result.scalar()

        return {
            "sellers_table_exists": sellers_exists,
            "message": "Database check completed"
        }
    except Exception as e:
        return {"error": str(e)}

@app.get("/")
def root():
    return {"message": "Backend is running!"}

# --- SELLER CRUD ---
@app.post("/sellers/signup", response_model=schemas.SellerBase)
async def create_seller(
    name: str = Form(...),
    email: str = Form(...),
    password: str = Form(...),
    phone: str = Form(...),
    store_name: str = Form(...),
    store_description: str = Form(None),
    cargo_company: str = Form("Araskargo"),
    logo: UploadFile = File(None),
    db: Session = Depends(get_db)
):
    try:
        formatted_phone = ensure_seller_phone_available(db, phone)

        # Telefon numarası doğrulanmış mı kontrol et (seller tablosunda)
        _, phone_verification = one_phone_record(
            db, models.PhoneVerificationSeller, "phone_number", formatted_phone
        )

        if not phone_verification or phone_verification.is_verified != "verified":
            raise HTTPException(
                status_code=400,
                detail="Telefon numarası doğrulanmamış. Lütfen önce telefon numaranızı doğrulayın"
            )

        # Email kontrolü
        existing_seller = db.query(models.Seller).filter(models.Seller.email == email).first()
        if existing_seller:
            raise HTTPException(status_code=400, detail="Email already registered")

        # Logo yükleme
        logo_url = None
        if logo:
            upload_dir = "uploads/Stores_Logo"
            if not os.path.exists(upload_dir):
                os.makedirs(upload_dir)

            file_extension = os.path.splitext(logo.filename)[1]
            unique_filename = f"logo_{uuid.uuid4()}{file_extension}"
            file_path = os.path.join(upload_dir, unique_filename)

            with open(file_path, "wb") as buffer:
                shutil.copyfileobj(logo.file, buffer)

            logo_url = f"/uploads/Stores_Logo/{unique_filename}"

        # Seller oluştur
        from datetime import datetime
        hashed_password = hash_password(password)
        db_seller = models.Seller(
            name=name,
            email=email,
            password=hashed_password,
            phone=formatted_phone,
            phone_verified="verified",
            email_verified="pending",
            store_name=store_name,
            store_description=store_description,
            cargo_company=cargo_company,
            store_logo_url=logo_url,
            is_verified="pending",
            created_at=datetime.now(),
            updated_at=datetime.now()
        )

        db.add(db_seller)
        db.commit()
        db.refresh(db_seller)

        # Doğrulama kaydını temizleme - kayıt kalmalı (güvenlik ve denetim için)
        # db.delete(phone_verification)
        # db.commit()

        return schemas.SellerBase(
            id=db_seller.id,
            name=db_seller.name,
            email=db_seller.email,
            phone=db_seller.phone,
            phone_verified=db_seller.phone_verified,
            email_verified=db_seller.email_verified,
            store_name=db_seller.store_name,
            store_description=db_seller.store_description,
            store_logo_url=db_seller.store_logo_url,
            cargo_company=db_seller.cargo_company,
            is_verified=db_seller.is_verified,
            created_at=db_seller.created_at.isoformat(),
            updated_at=db_seller.updated_at.isoformat()
        )
    except HTTPException:
        # HTTPException'ları tekrar fırlat (401, 404, 400 gibi)
        raise
    except Exception as e:
        # Sadece gerçek sunucu hatalarında 500 döndür
        raise HTTPException(status_code=500, detail="Internal server error")

@app.post("/sellers/login", response_model=schemas.SellerLoginResponse)
def login_seller(email: str = Form(...), password: str = Form(...), db: Session = Depends(get_db)):
    try:
        seller = db.query(models.Seller).filter(models.Seller.email == email).first()

        if not seller or not verify_password(password, seller.password):
            raise HTTPException(status_code=401, detail="E-posta veya şifre hatalı!")

        return schemas.SellerLoginResponse(
            access_token=issue_access_token(seller, "seller"),
            id=seller.id,
            name=seller.name,
            email=seller.email,
            phone=seller.phone,
            phone_verified=seller.phone_verified,
            email_verified=seller.email_verified,
            store_name=seller.store_name,
            store_description=seller.store_description,
            store_logo_url=seller.store_logo_url,
            cargo_company=seller.cargo_company,
            is_verified=seller.is_verified,
            created_at=seller.created_at.isoformat(),
            updated_at=seller.updated_at.isoformat()
        )
    except HTTPException:
        # HTTPException'ları tekrar fırlat (401, 404, 400 gibi)
        raise
    except Exception as e:
        # Sadece gerçek sunucu hatalarında 500 döndür
        raise HTTPException(status_code=500, detail="Internal server error")

@app.get("/sellers/profile", response_model=schemas.SellerBase)
def get_seller_profile(seller_id: int | None = None, db: Session = Depends(get_db), actor=Depends(current_seller)):
    if seller_id is not None:
        require_owner(seller_id, actor)
    seller_id = actor.id
    seller = db.query(models.Seller).filter(models.Seller.id == seller_id).first()
    if not seller:
        raise HTTPException(status_code=404, detail="Seller not found")

    return schemas.SellerBase(
        id=seller.id,
        name=seller.name,
        email=seller.email,
        phone=seller.phone,
        phone_verified=seller.phone_verified,
        email_verified=seller.email_verified,
        store_name=seller.store_name,
        store_description=seller.store_description,
        store_logo_url=seller.store_logo_url,
        cargo_company=seller.cargo_company,
        is_verified=seller.is_verified,
        created_at=seller.created_at.isoformat(),
        updated_at=seller.updated_at.isoformat()
    )

@app.get("/sellers/{seller_id}", response_model=schemas.SellerBase)
def get_seller_by_id(seller_id: int, db: Session = Depends(get_db)):
    seller = db.query(models.Seller).filter(models.Seller.id == seller_id).first()
    if not seller:
        raise HTTPException(status_code=404, detail="Seller not found")

    return schemas.SellerBase(
        id=seller.id,
        name=seller.name,
        email=seller.email,
        phone=seller.phone,
        phone_verified=seller.phone_verified,
        email_verified=seller.email_verified,
        store_name=seller.store_name,
        store_description=seller.store_description,
        store_logo_url=seller.store_logo_url,
        cargo_company=seller.cargo_company,
        is_verified=seller.is_verified,
        created_at=seller.created_at.isoformat(),
        updated_at=seller.updated_at.isoformat()
    )

@app.get("/sellers/{seller_id}/products", response_model=list[schemas.ProductBase])
def get_seller_products(seller_id: int, db: Session = Depends(get_db)):
    # Check if seller exists
    seller = db.query(models.Seller).filter(models.Seller.id == seller_id).first()
    if not seller:
        raise HTTPException(status_code=404, detail="Seller not found")

    # Get all products for this seller
    products = db.query(models.Product).filter(models.Product.seller_id == seller_id).all()

    return [
        schemas.ProductBase(
            id=product.id,
            product_name=product.product_name,
            product_price=product.product_price,
            product_description=product.product_description,
            product_category=product.product_category,
            product_image_url=product.product_image_url,
            seller_id=product.seller_id
        )
        for product in products
    ]

@app.put("/sellers/profile", response_model=schemas.SellerBase)
async def update_seller_profile(
    seller_id: int | None = None,
    name: str = Form(None),
    email: str = Form(None),
    phone: str = Form(None),
    store_name: str = Form(None),
    store_description: str = Form(None),
    cargo_company: str = Form(None),
    logo: UploadFile = File(None),
    db: Session = Depends(get_db), actor=Depends(current_seller)
):
    if seller_id is not None:
        require_owner(seller_id, actor)
    seller_id = actor.id
    seller = db.query(models.Seller).filter(models.Seller.id == seller_id).first()
    if not seller:
        raise HTTPException(status_code=404, detail="Seller not found")

    normalized_phone = (
        ensure_seller_phone_available(db, phone, actor.id)
        if phone is not None
        else normalize_phone_number(seller.phone)
    )
    current_phone = normalize_phone_number(seller.phone)
    phone_changed = normalized_phone != current_phone

    # Eski logo URL'ini sakla
    old_logo_url = seller.store_logo_url

    # Logo güncelleme - sadece yeni logo seçilmişse güncelle
    if logo and logo.filename:
        upload_dir = "uploads/Stores_Logo"
        if not os.path.exists(upload_dir):
            os.makedirs(upload_dir)

        file_extension = os.path.splitext(logo.filename)[1]
        unique_filename = f"logo_{uuid.uuid4()}{file_extension}"
        file_path = os.path.join(upload_dir, unique_filename)

        with open(file_path, "wb") as buffer:
            shutil.copyfileobj(logo.file, buffer)

        seller.store_logo_url = f"/uploads/Stores_Logo/{unique_filename}"

        # Eski logo varsa sil
        if old_logo_url:
            old_file_name = old_logo_url.split('/')[-1]
            old_file_path = f"uploads/Stores_Logo/{old_file_name}"
            delete_file_safely(old_file_path, "Eski mağaza logosu")

    # Email değişikliği kontrolü
    if email is not None and email != seller.email:
        # Eski email doğrulama kayıtlarını temizle
        old_email_verifications = db.query(models.EmailVerificationSeller).filter(
            models.EmailVerificationSeller.email == seller.email
        ).all()
        for verification in old_email_verifications:
            db.delete(verification)

        # Email doğrulama durumunu sıfırla
        seller.email_verified = "pending"


    # Telefon numarası değişikliği kontrolü
    if phone_changed:
        old_phone = seller.phone
        new_phone = normalized_phone

        # Eski telefon doğrulama kayıtlarını temizle
        delete_phone_records(db, models.PhoneVerificationSeller, "phone_number", old_phone)

        # Telefon doğrulama durumunu sıfırla
        seller.phone_verified = "pending"


        # Yeni telefon numarasına otomatik kod gönder
        try:
            # Önce telefon numarasını güncelle
            seller.phone = new_phone

            # Yeni telefon numarasına kod oluştur
            verification_code = generate_verification_code()
            expires_at = datetime.now() + timedelta(minutes=5)



            # Eski doğrulama kayıtlarını temizle (yeni numara için)
            delete_phone_records(db, models.PhoneVerificationSeller, "phone_number", new_phone)

            # Yeni doğrulama kaydı oluştur
            phone_verification = models.PhoneVerificationSeller(
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


        except Exception as e:
            # Hata durumunda işlemi geri al
            seller.phone = old_phone
            db.commit()
            raise HTTPException(
                status_code=500,
                detail=f"Telefon numarası güncellendi ancak doğrulama kodu gönderilemedi: {str(e)}"
            )

    # Diğer alanları güncelle - sadece değer verilmişse güncelle
    if name is not None:
        seller.name = name
    if email is not None:
        seller.email = email
    if phone is not None:
        seller.phone = normalized_phone
    if store_name is not None:
        seller.store_name = store_name
    if store_description is not None:
        seller.store_description = store_description
    if cargo_company is not None:
        seller.cargo_company = cargo_company

    seller.updated_at = datetime.now()

    db.commit()
    db.refresh(seller)

    return schemas.SellerBase(
        id=seller.id,
        name=seller.name,
        email=seller.email,
        phone=seller.phone,
        phone_verified=seller.phone_verified,
        email_verified=seller.email_verified,
        store_name=seller.store_name,
        store_description=seller.store_description,
        store_logo_url=seller.store_logo_url,
        cargo_company=seller.cargo_company,
        is_verified=seller.is_verified,
        created_at=seller.created_at.isoformat(),
        updated_at=seller.updated_at.isoformat()
    )

# --- SELLER ORDERS (NEW - using users_order table) ---
@app.get("/seller_orders/{seller_id}", response_model=list[dict])
def get_seller_orders(seller_id: int, db: Session = Depends(get_db), actor=Depends(current_seller)):
    """Satıcıya ait siparişleri getir - users_order tablosunu kullanarak"""
    owned_resource(db, models.Seller, seller_id, actor, "id")
    try:
        # Bu satıcıya ait ürünlerin ID'lerini al
        seller_products = db.query(models.Product).filter(
            models.Product.seller_id == seller_id
        ).all()

        seller_product_ids = [product.id for product in seller_products]

        if not seller_product_ids:
            return []

        # Bu satıcının ürünlerini içeren siparişleri al
        user_orders = db.query(models.UsersOrder).filter(
            models.UsersOrder.product_id.in_(seller_product_ids)
        ).all()

        result = []
        processed_orders = set()  # Aynı siparişi tekrar eklememek için

        for user_order in user_orders:
            if user_order.order_id in processed_orders:
                continue

            processed_orders.add(user_order.order_id)

            # Sipariş bilgilerini al
            order = db.query(models.Order).filter(
                models.Order.id == user_order.order_id
            ).first()

            if not order:
                continue

            # Kullanıcı bilgilerini al
            user = db.query(models.User).filter(
                models.User.id == user_order.user_id
            ).first()

            if not user:
                continue

            # Adres bilgilerini al
            address = None
            if order.order_address:
                address = db.query(models.Address).filter(
                    models.Address.id == order.order_address
                ).first()

            # Bu siparişteki bu satıcıya ait ürünleri al
            order_products = []
            for uo in db.query(models.UsersOrder).filter(
                models.UsersOrder.order_id == user_order.order_id,
                models.UsersOrder.product_id.in_(seller_product_ids)
            ).all():
                product = db.query(models.Product).filter(
                    models.Product.id == uo.product_id
                ).first()

                if product:
                    order_products.append({
                        "product_id": product.id,
                        "product_name": product.product_name,
                        "product_price": product.product_price,
                        "quantity": getattr(uo, 'quantity', 1),  # quantity alanı yoksa 1 varsay
                        "total_price": getattr(uo, 'price', product.product_price)  # price alanı yoksa product_price varsay
                    })

            result.append({
                "order_id": order.id,
                "order_code": order.order_code,
                "order_created_date": order.order_created_date.strftime('%Y-%m-%d') if hasattr(order.order_created_date, 'strftime') else str(order.order_created_date),
                "order_estimated_delivery": order.order_estimated_delivery.strftime('%Y-%m-%d') if hasattr(order.order_estimated_delivery, 'strftime') else str(order.order_estimated_delivery),
                "order_cargo_company": order.order_cargo_company,
                "status": order.order_status or "pending",  # Gerçek durum
                "user": {
                    "id": user.id,
                    "name_surname": user.name_surname,
                    "email": user.email,
                    "phone_number": user.phone_number
                },
                "address": {
                    "id": address.id if address else None,
                    "city": address.city if address else "",
                    "district": address.district if address else "",
                    "neighbourhood": address.neighbourhood if address else "",
                    "street_name": address.street_name if address else "",
                    "building_number": address.building_number if address else "",
                    "apartment_number": address.apartment_number if address else "",
                    "address_name": address.address_name if address else ""
                } if address else None,
                "products": order_products
            })

        return result

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error getting seller orders: {str(e)}")

@app.put("/seller_orders/{order_id}/status")
def update_seller_order_status(order_id: int, status: str, db: Session = Depends(get_db), actor=Depends(current_seller)):
    """Satıcı sipariş durumunu güncelle - UPDATED"""
    order = db.get(models.Order, order_id)
    if order is None:
        raise HTTPException(404, "Order not found")
    owners = {row[0] for row in db.query(models.Product.seller_id).join(
        models.UsersOrder, models.UsersOrder.product_id == models.Product.id
    ).filter(models.UsersOrder.order_id == order_id).all()}
    # Status is stored on the whole order. Mixed-seller legacy orders cannot safely be changed here.
    if owners != {actor.id}:
        raise HTTPException(403, "Order is not exclusively fulfilled by this seller")
    if status not in {"pending", "processing", "shipped", "delivered", "cancelled"}:
        raise HTTPException(422, "Invalid order status")
    try:

        if not status:
            raise HTTPException(status_code=400, detail="Status is required")

        # Order'ı bul
        order = db.query(models.Order).filter(models.Order.id == order_id).first()

        if not order:
            raise HTTPException(status_code=404, detail=f"Order with ID {order_id} not found")

        # Status'u güncelle
        order.order_status = status

        # Eğer status "delivered" ise teslim tarihini de güncelle
        if status == 'delivered':
            from datetime import datetime
            order.order_delivered_date = datetime.now()

        db.commit()

        return {"message": "Order status updated successfully", "order_id": order_id, "status": status}

    except HTTPException:
        # Re-raise HTTP exceptions as-is
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error updating order status: {str(e)}")

@app.get("/seller_statistics/{seller_id}")
def get_seller_statistics(seller_id: int, db: Session = Depends(get_db), actor=Depends(current_seller)):
    """Satıcı istatistiklerini getir"""
    owned_resource(db, models.Seller, seller_id, actor, "id")
    try:
        # Satıcının ürünlerini al
        seller_products = db.query(models.Product).filter(models.Product.seller_id == seller_id).all()
        product_ids = [product.id for product in seller_products]

        # Toplam ürün sayısı
        total_products = len(seller_products)

        # Satıcının siparişlerini al
        seller_orders = []
        if product_ids:
            # Bu satıcının ürünlerini içeren siparişleri bul
            for uo in db.query(models.UsersOrder).filter(
                models.UsersOrder.product_id.in_(product_ids)
            ).all():
                order = db.query(models.Order).filter(models.Order.id == uo.order_id).first()
                if order and order not in seller_orders:
                    seller_orders.append(order)

        # Toplam sipariş sayısı
        total_orders = len(seller_orders)

        # Durum bazında sipariş sayıları
        pending_orders = len([o for o in seller_orders if o.order_status == 'pending'])
        processing_orders = len([o for o in seller_orders if o.order_status == 'processing'])
        shipped_orders = len([o for o in seller_orders if o.order_status == 'shipped'])
        delivered_orders = len([o for o in seller_orders if o.order_status == 'delivered'])

        # En çok satın alan müşteri
        customer_orders = {}
        for uo in db.query(models.UsersOrder).filter(
            models.UsersOrder.product_id.in_(product_ids)
        ).all():
            order = db.query(models.Order).filter(models.Order.id == uo.order_id).first()
            if order:
                # Order'ın user_id'sini bul
                user_order = db.query(models.UsersOrder).filter(
                    models.UsersOrder.order_id == order.id
                ).first()
                if user_order:
                    user = db.query(models.User).filter(models.User.id == user_order.user_id).first()
                    if user:
                        customer_name = user.name_surname
                        customer_orders[customer_name] = customer_orders.get(customer_name, 0) + 1

        favorite_customer = max(customer_orders.items(), key=lambda x: x[1]) if customer_orders else ("Henüz müşteri yok", 0)

        # En çok satılan ürün
        product_sales = {}
        for uo in db.query(models.UsersOrder).filter(
            models.UsersOrder.product_id.in_(product_ids)
        ).all():
            product = db.query(models.Product).filter(models.Product.id == uo.product_id).first()
            if product:
                product_sales[product.product_name] = product_sales.get(product.product_name, 0) + 1

        best_selling_product = max(product_sales.items(), key=lambda x: x[1]) if product_sales else ("Henüz satış yok", 0)

        return {
            "total_products": total_products,
            "total_orders": total_orders,
            "pending_orders": pending_orders,
            "processing_orders": processing_orders,
            "shipped_orders": shipped_orders,
            "delivered_orders": delivered_orders,
            "favorite_customer": {
                "name": favorite_customer[0],
                "order_count": favorite_customer[1]
            },
            "best_selling_product": {
                "name": best_selling_product[0],
                "sales_count": best_selling_product[1]
            }
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error getting seller statistics: {str(e)}")

@app.get("/seller_active_orders/{seller_id}", response_model=list[dict])
def get_seller_active_orders(seller_id: int, db: Session = Depends(get_db), actor=Depends(current_seller)):
    """Satıcının aktif siparişlerini getir (pending, processing, shipped)"""
    owned_resource(db, models.Seller, seller_id, actor, "id")
    try:
        # Satıcının ürünlerini al
        seller_products = db.query(models.Product).filter(models.Product.seller_id == seller_id).all()
        product_ids = [product.id for product in seller_products]

        active_orders = []
        if product_ids:
            # Bu satıcının ürünlerini içeren aktif siparişleri bul
            for uo in db.query(models.UsersOrder).filter(
                models.UsersOrder.product_id.in_(product_ids)
            ).all():
                order = db.query(models.Order).filter(models.Order.id == uo.order_id).first()
                if order and order.order_status in ['pending', 'processing', 'shipped']:
                    # Sipariş zaten eklenmiş mi kontrol et
                    if not any(active_order['order_id'] == order.id for active_order in active_orders):
                        # Kullanıcı bilgilerini al
                        user_order = db.query(models.UsersOrder).filter(
                            models.UsersOrder.order_id == order.id
                        ).first()
                        user = None
                        if user_order:
                            user = db.query(models.User).filter(models.User.id == user_order.user_id).first()

                        # Adres bilgilerini al
                        address = None
                        if order.order_address:
                            address = db.query(models.Address).filter(models.Address.id == order.order_address).first()

                        # Ürün bilgilerini al
                        products = []
                        for uo_product in db.query(models.UsersOrder).filter(models.UsersOrder.order_id == order.id).all():
                            product = db.query(models.Product).filter(models.Product.id == uo_product.product_id).first()
                            if product and product.seller_id == seller_id:  # Sadece bu satıcının ürünlerini ekle
                                products.append({
                                    'product_name': product.product_name,
                                    'quantity': getattr(uo_product, 'quantity', 1),
                                    'total_price': getattr(uo_product, 'total_price', product.product_price)
                                })

                        if products:  # Sadece bu satıcının ürünleri varsa ekle
                            active_orders.append({
                                'order_id': order.id,
                                'order_code': order.order_code,
                                'order_created_date': order.order_created_date.strftime('%Y-%m-%d') if order.order_created_date else None,
                                'order_estimated_delivery': order.order_estimated_delivery.strftime('%Y-%m-%d') if order.order_estimated_delivery else None,
                                'order_cargo_company': order.order_cargo_company,
                                'status': order.order_status,
                                'user': {
                                    'name_surname': user.name_surname if user else 'Bilinmeyen',
                                    'email': user.email if user else 'Bilinmeyen',
                                    'phone_number': user.phone_number if user else 'Bilinmeyen'
                                } if user else None,
                                'address': {
                                    'city': address.city if address else 'Bilinmeyen',
                                    'district': address.district if address else 'Bilinmeyen',
                                    'neighbourhood': address.neighbourhood if address else 'Bilinmeyen',
                                    'street_name': address.street_name if address else 'Bilinmeyen',
                                    'building_number': address.building_number if address else 'Bilinmeyen',
                                    'apartment_number': address.apartment_number if address else 'Bilinmeyen'
                                } if address else None,
                                'products': products
                            })

        # Siparişleri tarihe göre sırala (en yeni önce)
        active_orders.sort(key=lambda x: x['order_created_date'] or '', reverse=True)

        return active_orders

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error getting seller active orders: {str(e)}")

# --- SELLER REVIEWS ---
@app.post("/seller_reviews", response_model=schemas.SellerReviewBase)
def create_seller_review(review: schemas.SellerReviewCreate, db: Session = Depends(get_db), actor=Depends(current_user)):
    """Ürün değerlendirmesi oluştur"""
    require_owner(review.user_id, actor)
    product = db.get(models.Product, review.product_id)
    if product is None:
        raise HTTPException(404, "Product not found")
    if product.seller_id != review.seller_id:
        raise HTTPException(403, "Product belongs to another seller")
    try:

        # Rating kontrolü (1-5 arası)
        if review.rating < 1 or review.rating > 5:
            raise HTTPException(status_code=400, detail="Rating must be between 1 and 5")

        # Aynı kullanıcının aynı ürün için daha önce değerlendirme yapıp yapmadığını kontrol et
        existing_review = db.query(models.SellerReview).filter(
            models.SellerReview.user_id == review.user_id,
            models.SellerReview.product_id == review.product_id
        ).first()

        if existing_review:
            raise HTTPException(status_code=400, detail="User has already reviewed this product")

        # Yeni değerlendirme oluştur
        db_review = models.SellerReview(
            product_id=review.product_id,
            seller_id=review.seller_id,
            user_id=review.user_id,
            rating=review.rating,
            comment=review.comment,
            created_at=datetime.now()
        )

        db.add(db_review)
        db.commit()
        db.refresh(db_review)

        return schemas.SellerReviewBase(
            id=db_review.id,
            product_id=db_review.product_id,
            seller_id=db_review.seller_id,
            user_id=db_review.user_id,
            rating=db_review.rating,
            comment=db_review.comment,
            created_at=db_review.created_at.strftime('%Y-%m-%d %H:%M:%S') if db_review.created_at else None
        )

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error creating seller review: {str(e)}")

@app.get("/seller_reviews", response_model=list[schemas.SellerReviewBase])
def get_seller_reviews(
    seller_id: int = None,
    product_id: int = None,
    db: Session = Depends(get_db)
):
    """Değerlendirmeleri getir (filtreleme ile)"""
    try:
        query = db.query(models.SellerReview)

        if seller_id:
            query = query.filter(models.SellerReview.seller_id == seller_id)

        if product_id:
            query = query.filter(models.SellerReview.product_id == product_id)

        reviews = query.all()

        return [
            schemas.SellerReviewBase(
                id=review.id,
                product_id=review.product_id,
                seller_id=review.seller_id,
                user_id=review.user_id,
                rating=review.rating,
                comment=review.comment,
                created_at=review.created_at.strftime('%Y-%m-%d %H:%M:%S') if review.created_at else None
            )
            for review in reviews
        ]

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error getting seller reviews: {str(e)}")

@app.put("/seller_reviews/{review_id}", response_model=schemas.SellerReviewBase)
def update_seller_review(review_id: int, review: schemas.SellerReviewUpdate, db: Session = Depends(get_db), actor=Depends(current_user)):
    """Değerlendirme güncelle"""
    owned_resource(db, models.SellerReview, review_id, actor)
    try:
        db_review = db.query(models.SellerReview).filter(models.SellerReview.id == review_id).first()
        if not db_review:
            raise HTTPException(status_code=404, detail="Review not found")

        if review.rating is not None:
            if review.rating < 1 or review.rating > 5:
                raise HTTPException(status_code=400, detail="Rating must be between 1 and 5")
            db_review.rating = review.rating

        if review.comment is not None:
            db_review.comment = review.comment

        db.commit()
        db.refresh(db_review)

        return schemas.SellerReviewBase(
            id=db_review.id,
            product_id=db_review.product_id,
            seller_id=db_review.seller_id,
            user_id=db_review.user_id,
            rating=db_review.rating,
            comment=db_review.comment,
            created_at=db_review.created_at.strftime('%Y-%m-%d %H:%M:%S') if db_review.created_at else None
        )

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error updating seller review: {str(e)}")

@app.delete("/seller_reviews/{review_id}")
def delete_seller_review(review_id: int, db: Session = Depends(get_db), actor=Depends(current_user)):
    """Değerlendirme sil"""
    owned_resource(db, models.SellerReview, review_id, actor)
    try:
        db_review = db.query(models.SellerReview).filter(models.SellerReview.id == review_id).first()
        if not db_review:
            raise HTTPException(status_code=404, detail="Review not found")

        db.delete(db_review)
        db.commit()

        return {"message": "Review deleted successfully"}

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error deleting seller review: {str(e)}")

# --- PHONE VERIFICATION FOR SELLERS ---
@app.post("/send-seller-verification-code", response_model=schemas.PhoneVerificationResponse)
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

@app.post("/verify-seller-phone", response_model=schemas.PhoneVerificationResponse)
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

# --- EMAIL VERIFICATION FOR USERS ---
@app.post("/send-email-verification-code", response_model=schemas.EmailVerificationResponse)
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

@app.post("/verify-email", response_model=schemas.EmailVerificationResponse)
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

# --- EMAIL VERIFICATION FOR SELLERS ---
@app.post("/send-seller-email-verification-code", response_model=schemas.EmailVerificationSellerResponse)
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

@app.post("/verify-seller-email", response_model=schemas.EmailVerificationSellerResponse)
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

@app.post("/users/login", response_model=schemas.UserLoginResponse)
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

# ===== SATICI TAKİP SİSTEMİ =====

@app.post("/users/{user_id}/follow-seller/{seller_id}")
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

@app.delete("/users/{user_id}/unfollow-seller/{seller_id}")
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

@app.get("/users/{user_id}/followed-sellers")
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

@app.get("/sellers/{seller_id}/followers-count")
def get_seller_followers_count(seller_id: int, db: Session = Depends(get_db)):
    """Satıcının takipçi sayısını getir"""
    try:
        # Satıcı var mı kontrol et
        seller = db.query(models.Seller).filter(models.Seller.id == seller_id).first()
        if not seller:
            raise HTTPException(status_code=404, detail="Satıcı bulunamadı")

        # Takipçi sayısını hesapla
        followers_count = db.query(models.UsersSellers).filter(
            models.UsersSellers.seller_id == seller_id
        ).count()

        return {"seller_id": seller_id, "followers_count": followers_count}

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail="Takipçi sayısı getirilemedi")

@app.get("/users/{user_id}/is-following/{seller_id}")
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

@app.post("/sellers/{seller_id}/send-phone-verification", response_model=schemas.PhoneVerificationResponse)
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


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8000)
