"""Payment tokenization, charging, and stored-card routes."""

import os
import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

import app.models as models
import app.schemas as schemas
from app.dependencies import current_user, get_db, owned_resource, require_owner

router = APIRouter()


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


@router.post("/tokenize", response_model=schemas.TokenizeCardResponse)
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


@router.post("/charge", response_model=schemas.ChargeResponse)
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


@router.post("/credit_card", response_model=schemas.CreditCardBase)
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


@router.get("/credit_card", response_model=list[schemas.CreditCardBase])
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


@router.put("/credit_card/{card_id}", response_model=schemas.CreditCardBase)
def update_credit_card(card_id: int, card: schemas.CreditCardUpdate, db: Session = Depends(get_db), actor=Depends(current_user)):
    db_card = owned_resource(db, models.CreditCard, card_id, actor)
    for field in ("card_token", "provider", "card_brand", "last4", "expiry_month", "expiry_year"):
        if getattr(card, field) != getattr(db_card, field):
            raise HTTPException(403, "Saved payment credentials cannot be replaced; tokenize a new card")
    db_card.is_default = card.is_default
    db.commit()
    return card_response(db_card)


@router.delete("/credit_card/{card_id}")
def delete_credit_card(card_id: int, db: Session = Depends(get_db), actor=Depends(current_user)):
    owned_resource(db, models.CreditCard, card_id, actor)
    db_card = db.query(models.CreditCard).filter(models.CreditCard.id == card_id).first()
    if not db_card:
        raise HTTPException(status_code=404, detail="Credit card not found")
    db.delete(db_card)
    db.commit()
    return {"ok": True}


@router.post("/users_credit_card", response_model=schemas.UsersCreditCardBase)
def create_users_credit_card(ucc: schemas.UsersCreditCardCreate, db: Session = Depends(get_db), actor=Depends(current_user)):
    require_owner(ucc.user_id, actor)
    owned_resource(db, models.CreditCard, ucc.credit_card_id, actor)
    db_ucc = models.UsersCreditCard(**ucc.dict())
    db.add(db_ucc)
    db.commit()
    db.refresh(db_ucc)
    return db_ucc


@router.get("/users_credit_card", response_model=list[schemas.UsersCreditCardBase])
def get_users_credit_cards(db: Session = Depends(get_db), actor=Depends(current_user)):
    return db.query(models.UsersCreditCard).filter_by(user_id=actor.id).all()


@router.put("/users_credit_card/{ucc_id}", response_model=schemas.UsersCreditCardBase)
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


@router.delete("/users_credit_card/{ucc_id}")
def delete_users_credit_card(ucc_id: int, db: Session = Depends(get_db), actor=Depends(current_user)):
    owned_resource(db, models.UsersCreditCard, ucc_id, actor)
    db_ucc = db.query(models.UsersCreditCard).filter(models.UsersCreditCard.id == ucc_id).first()
    if not db_ucc:
        raise HTTPException(status_code=404, detail="UsersCreditCard not found")
    db.delete(db_ucc)
    db.commit()
    return {"ok": True}
