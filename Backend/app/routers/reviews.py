"""Seller review routes."""

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

import app.models as models
import app.schemas as schemas
from app.dependencies import current_user, get_db, owned_resource, require_owner

router = APIRouter()


@router.post("/seller_reviews", response_model=schemas.SellerReviewBase)
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


@router.get("/seller_reviews", response_model=list[schemas.SellerReviewBase])
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


@router.put("/seller_reviews/{review_id}", response_model=schemas.SellerReviewBase)
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


@router.delete("/seller_reviews/{review_id}")
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
