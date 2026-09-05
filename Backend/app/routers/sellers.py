"""Seller account, profile, catalog-view, and follower routes."""

import os
import shutil
import uuid
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session

import app.models as models
import app.schemas as schemas
from app.auth import hash_password, issue_access_token, verify_password
from app.dependencies import current_seller, get_db, require_owner
from app.phone_numbers import normalize_phone_number
from app.services.account_helpers import ensure_seller_phone_available
from app.services.files import delete_file_safely
from app.services.verification import (
    delete_phone_records,
    generate_verification_code,
    one_phone_record,
    send_sms_verification,
)

router = APIRouter()


@router.post("/sellers/signup", response_model=schemas.SellerBase)
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


@router.post("/sellers/login", response_model=schemas.SellerLoginResponse)
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


@router.get("/sellers/profile", response_model=schemas.SellerBase)
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


@router.get("/sellers/{seller_id}", response_model=schemas.SellerBase)
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


@router.get("/sellers/{seller_id}/products", response_model=list[schemas.ProductBase])
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


@router.put("/sellers/profile", response_model=schemas.SellerBase)
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


@router.get("/sellers/{seller_id}/followers-count")
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
