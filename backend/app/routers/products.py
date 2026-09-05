"""Product mutation, listing, and image-upload routes."""

import os
import shutil
import uuid

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from sqlalchemy.orm import Session

import app.models as models
import app.schemas as schemas
from app.dependencies import current_seller, get_db, owned_resource, require_owner
from app.services.files import delete_unreferenced_product_image

router = APIRouter()


@router.post("/products", response_model=schemas.ProductBase)
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


@router.get("/products", response_model=list[schemas.ProductBase])
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


@router.put("/products/{product_id}", response_model=schemas.ProductBase)
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


@router.delete("/products/{product_id}")
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


@router.post('/upload-image')
async def upload_image(file: UploadFile = File(...), actor=Depends(current_seller)):
    upload_dir = 'uploads/Product_Image'
    os.makedirs(upload_dir, exist_ok=True)
    ext = file.filename.split('.')[-1]
    unique_name = f"{uuid.uuid4()}.{ext}"
    file_path = os.path.join(upload_dir, unique_name)
    with open(file_path, 'wb') as buffer:
        shutil.copyfileobj(file.file, buffer)
    return {"url": f"/uploads/Product_Image/{unique_name}"}
