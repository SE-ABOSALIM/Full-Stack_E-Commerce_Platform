from sqlalchemy import Column, Integer, String, Float, Date, DateTime, ForeignKey, Boolean
from app.db import Base
from sqlalchemy.dialects.postgresql import ARRAY, TIMESTAMP
from datetime import datetime

class Address(Base):
    __tablename__ = "address"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), index=True)
    city = Column(String)
    district = Column(String)
    neighbourhood = Column(String)
    street_name = Column(String)
    building_number = Column(String)
    apartment_number = Column(String)
    address_name = Column(String)

class CreditCard(Base):
    __tablename__ = "credit_card"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"))
    provider = Column(String(50))
    card_token = Column(String(255))
    card_brand = Column(String(20))
    last4 = Column(String(4))
    expiry_month = Column(Integer)
    expiry_year = Column(Integer)
    is_default = Column(Boolean, default=False)
    created_at = Column(TIMESTAMP, default=datetime.utcnow)
    updated_at = Column(TIMESTAMP, default=datetime.utcnow, onupdate=datetime.utcnow)

class Order(Base):
    __tablename__ = "order"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), index=True)
    order_code = Column(String)
    order_created_date = Column(DateTime)
    order_estimated_delivery = Column(DateTime)
    order_delivered_date = Column(DateTime)
    order_cargo_company = Column(String)
    order_address = Column(Integer, ForeignKey("address.id", ondelete="CASCADE"))
    order_status = Column(String, default="pending")  # pending, processing, shipped, delivered, cancelled

class Product(Base):
    __tablename__ = "products"
    id = Column(Integer, primary_key=True, index=True)
    product_name = Column(String)
    product_price = Column(Float)
    product_description = Column(String)
    product_category = Column(String)
    product_image_url = Column(String)  # Tek fotoğraf için String
    seller_id = Column(Integer, ForeignKey("sellers.id", ondelete="CASCADE"), nullable=True)

class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    name_surname = Column(String)
    password = Column(String)
    email = Column(String)
    phone_number = Column(String, unique=True, index=True)
    phone_verified = Column(String, default="pending")  # pending, verified
    email_verified = Column(String, default="pending")  # pending, verified
    created_at = Column(TIMESTAMP, default=datetime.utcnow)
    updated_at = Column(TIMESTAMP, default=datetime.utcnow, onupdate=datetime.utcnow)

class UsersAddress(Base):
    __tablename__ = "users_address"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"))
    address_id = Column(Integer, ForeignKey("address.id", ondelete="CASCADE"))

class UsersCreditCard(Base):
    __tablename__ = "users_credit_card"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"))
    credit_card_id = Column(Integer, ForeignKey("credit_card.id", ondelete="CASCADE"))

class UsersOrder(Base):
    __tablename__ = "users_order"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"))
    product_id = Column(Integer, ForeignKey("products.id", ondelete="CASCADE"))
    order_id = Column(Integer, ForeignKey("order.id", ondelete="CASCADE"))

class Seller(Base):
    __tablename__ = "sellers"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String)
    email = Column(String, unique=True, index=True)
    password = Column(String)
    phone = Column(String, unique=True, index=True)
    phone_verified = Column(String, default="pending")  # pending, verified
    email_verified = Column(String, default="pending")  # pending, verified
    store_name = Column(String)
    store_description = Column(String, nullable=True)
    store_logo_url = Column(String, nullable=True)
    cargo_company = Column(String, default="Araskargo")
    is_verified = Column(String, default="pending")
    followers_count = Column(Integer, nullable=False, default=0)
    created_at = Column(TIMESTAMP, default=datetime.utcnow)
    updated_at = Column(TIMESTAMP, default=datetime.utcnow, onupdate=datetime.utcnow)



class SellerProduct(Base):
    __tablename__ = "seller_products"
    id = Column(Integer, primary_key=True, index=True)
    seller_id = Column(Integer, ForeignKey("sellers.id", ondelete="CASCADE"))
    product_id = Column(Integer, ForeignKey("products.id", ondelete="CASCADE"))

class SellerReview(Base):
    __tablename__ = "seller_reviews"
    id = Column(Integer, primary_key=True, index=True)
    product_id = Column(Integer, ForeignKey("products.id", ondelete="CASCADE"))
    seller_id = Column(Integer, ForeignKey("sellers.id", ondelete="CASCADE"))
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"))
    rating = Column(Integer)  # 1-5 arası
    comment = Column(String, nullable=True)
    created_at = Column(DateTime)

class PhoneVerification(Base):
    __tablename__ = "phone_verifications"
    id = Column(Integer, primary_key=True, index=True)
    phone_number = Column(String, unique=True, index=True)
    verification_code = Column(String)
    is_verified = Column(String, default="pending")  # pending, verified, expired
    attempts = Column(Integer, default=0)
    created_at = Column(TIMESTAMP, default=datetime.utcnow)
    expires_at = Column(TIMESTAMP)

class PhoneVerificationSeller(Base):
    __tablename__ = "phone_verification_sellers"
    id = Column(Integer, primary_key=True, index=True)
    phone_number = Column(String, unique=True, index=True)
    verification_code = Column(String)
    is_verified = Column(String, default="pending")  # pending, verified, expired
    attempts = Column(Integer, default=0)
    created_at = Column(TIMESTAMP, default=datetime.utcnow)
    expires_at = Column(TIMESTAMP)

class EmailVerification(Base):
    __tablename__ = "email_verifications"
    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True)
    verification_code = Column(String)
    is_verified = Column(String, default="pending")  # pending, verified, expired
    attempts = Column(Integer, default=0)
    created_at = Column(TIMESTAMP, default=datetime.utcnow)
    expires_at = Column(TIMESTAMP)

class EmailVerificationSeller(Base):
    __tablename__ = "email_verifications_seller"
    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True)
    verification_code = Column(String)
    is_verified = Column(String, default="pending")  # pending, verified, expired
    attempts = Column(Integer, default=0)
    created_at = Column(TIMESTAMP, default=datetime.utcnow)
    expires_at = Column(TIMESTAMP)

class UsersSellers(Base):
    __tablename__ = "users_sellers"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"))
    seller_id = Column(Integer, ForeignKey("sellers.id", ondelete="CASCADE"))
    created_at = Column(TIMESTAMP, default=datetime.utcnow)


class PasswordResetVerification(Base):
    """Dedicated purpose: registration and phone-change codes never enter this table."""
    __tablename__ = "password_reset_verifications"
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False)
    phone_number = Column(String, nullable=False)
    code_hash = Column(String, nullable=False)
    attempts = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    expires_at = Column(DateTime, nullable=False)
    consumed_at = Column(DateTime, nullable=True)
