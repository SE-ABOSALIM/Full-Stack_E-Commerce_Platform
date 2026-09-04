from pydantic import BaseModel, ConfigDict, Field
from typing import Optional

# Product
class ProductBase(BaseModel):
    id: int
    product_name: str
    product_price: float
    product_description: str
    product_category: str
    product_image_url: str
    seller_id: Optional[int] = None

class ProductCreate(BaseModel):
    product_name: str
    product_price: float
    product_description: str
    product_category: str
    product_image_url: str
    seller_id: Optional[int] = None

class ProductUpdate(BaseModel):
    product_name: str
    product_price: float
    product_description: str
    product_category: str
    product_image_url: str
    seller_id: Optional[int] = None

# User
class UserBase(BaseModel):
    """Public user response; credentials belong only in input schemas."""

    id: int
    name_surname: str
    email: str
    phone_number: str
    phone_verified: str
    email_verified: str
    created_at: str
    updated_at: str

class UserCreate(BaseModel):
    name_surname: str
    password: str
    email: str
    phone_number: str

class UserUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name_surname: str
    email: str
    phone_number: str


class UserLoginResponse(UserBase):
    access_token: str
    token_type: str = "bearer"


class PasswordChange(BaseModel):
    model_config = ConfigDict(extra="forbid")
    current_password: str = Field(min_length=1, max_length=1024)
    new_password: str = Field(min_length=8, max_length=1024)
    new_password_again: str = Field(min_length=8, max_length=1024)


class PasswordResetRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    phone_number: str = Field(min_length=8, max_length=30)


class PasswordReset(PasswordResetRequest):
    verification_code: str = Field(pattern=r"^[0-9]{6}$")
    new_password: str = Field(min_length=8, max_length=1024)

# Address
class AddressBase(BaseModel):
    id: int
    city: str
    district: str
    neighbourhood: str
    street_name: str
    building_number: str
    apartment_number: str
    address_name: str

class AddressCreate(BaseModel):
    city: str
    district: str
    neighbourhood: str
    street_name: str
    building_number: str
    apartment_number: str
    address_name: str

class AddressUpdate(BaseModel):
    city: str
    district: str
    neighbourhood: str
    street_name: str
    building_number: str
    apartment_number: str
    address_name: str

# Credit Card
class CreditCardBase(BaseModel):
    id: int
    user_id: int | None = None
    provider: str
    card_token: str
    card_brand: str
    last4: str
    expiry_month: int
    expiry_year: int
    is_default: bool = False
    created_at: str | None = None
    updated_at: str | None = None

class CreditCardCreate(BaseModel):
    user_id: int
    provider: str
    card_token: str
    card_brand: str
    last4: str
    expiry_month: int
    expiry_year: int
    is_default: bool = False

class CreditCardUpdate(BaseModel):
    provider: str
    card_token: str
    card_brand: str
    last4: str
    expiry_month: int
    expiry_year: int
    is_default: bool = False

# Tokenization
class TokenizeCardRequest(BaseModel):
    user_id: int
    card_holder_name: str
    card_number: str
    expire_month: int
    expire_year: int
    cvc: str

class TokenizeCardResponse(BaseModel):
    card_token: str
    card_brand: str
    last4: str
    expiry_month: int
    expiry_year: int

class ChargeRequest(BaseModel):
    user_id: int
    price: float
    paid_price: float
    currency: str = 'TRY'
    card_token: str  # iyzico cardUserKey:cardToken veya tek token
    installment: int | None = None
    basket_id: str | None = None
    payment_channel: str | None = 'WEB'
    payment_group: str | None = 'PRODUCT'

class ChargeResponse(BaseModel):
    status: str
    payment_id: str | None = None
    error_message: str | None = None

# Order
class OrderBase(BaseModel):
    id: int
    order_code: Optional[str] = None
    order_created_date: Optional[str] = None  # ISO datetime string
    order_estimated_delivery: Optional[str] = None  # ISO datetime string
    order_cargo_company: Optional[str] = None
    order_address: Optional[int] = None
    order_status: Optional[str] = "pending"
    order_delivered_date: Optional[str] = None  # ISO datetime string

class OrderCreate(BaseModel):
    order_code: str
    order_created_date: str  # ISO datetime string
    order_estimated_delivery: str  # ISO datetime string
    order_cargo_company: str
    order_address: int
    order_status: Optional[str] = "pending"

class OrderUpdate(BaseModel):
    order_code: str
    order_created_date: str  # ISO datetime string
    order_estimated_delivery: str  # ISO datetime string
    order_cargo_company: str
    order_address: int
    order_status: Optional[str] = "pending"

# UsersAddress
class UsersAddressBase(BaseModel):
    id: int
    user_id: int
    address_id: int

class UsersAddressCreate(BaseModel):
    user_id: int
    address_id: int

class UsersAddressUpdate(BaseModel):
    user_id: int
    address_id: int

# UsersCreditCard
class UsersCreditCardBase(BaseModel):
    id: int
    user_id: int
    credit_card_id: int

class UsersCreditCardCreate(BaseModel):
    user_id: int
    credit_card_id: int

class UsersCreditCardUpdate(BaseModel):
    user_id: int
    credit_card_id: int

# UsersOrder
class UsersOrderBase(BaseModel):
    id: int
    user_id: int
    product_id: int
    order_id: int

class UsersOrderCreate(BaseModel):
    user_id: int
    product_id: int
    order_id: int

class UsersOrderUpdate(BaseModel):
    user_id: int
    product_id: int
    order_id: int

# Seller
class SellerBase(BaseModel):
    id: int
    name: str
    email: str
    phone: str
    phone_verified: str
    email_verified: str
    store_name: str
    store_description: Optional[str] = None
    store_logo_url: Optional[str] = None
    cargo_company: Optional[str] = "Araskargo"
    is_verified: str
    created_at: str  # ISO datetime string
    updated_at: str  # ISO datetime string

class SellerCreate(BaseModel):
    name: str
    email: str
    password: str
    phone: str
    store_name: str
    store_description: Optional[str] = None
    cargo_company: Optional[str] = "Araskargo"


class SellerLoginResponse(SellerBase):
    access_token: str
    token_type: str = "bearer"

class SellerUpdate(BaseModel):
    name: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    store_name: Optional[str] = None
    store_description: Optional[str] = None
    store_logo_url: Optional[str] = None
    cargo_company: Optional[str] = None



# Seller Product
class SellerProductBase(BaseModel):
    id: int
    seller_id: int
    product_id: int

class SellerProductCreate(BaseModel):
    seller_id: int
    product_id: int

class SellerProductUpdate(BaseModel):
    seller_id: int
    product_id: int

# Status update request
class StatusUpdateRequest(BaseModel):
    status: str

# Seller Review
class SellerReviewBase(BaseModel):
    id: int
    product_id: int
    seller_id: int
    user_id: int
    rating: int
    comment: Optional[str] = None
    created_at: Optional[str] = None  # ISO datetime string

class SellerReviewCreate(BaseModel):
    product_id: int
    seller_id: int
    user_id: int
    rating: int
    comment: Optional[str] = None

class SellerReviewUpdate(BaseModel):
    rating: Optional[int] = None
    comment: Optional[str] = None

# Phone Verification
class PhoneVerificationBase(BaseModel):
    id: int
    phone_number: str
    verification_code: str
    is_verified: str
    attempts: int
    created_at: str
    expires_at: str

class PhoneVerificationCreate(BaseModel):
    phone_number: str
    language: Optional[str] = None  # Dil kodu (tr, en, ar)

class PhoneVerificationVerify(BaseModel):
    phone_number: str
    verification_code: str

class PhoneVerificationResponse(BaseModel):
    message: str
    success: bool
    expires_in: Optional[int] = None

class PhoneVerificationSellerCreate(BaseModel):
    phone_number: str
    language: Optional[str] = None  # Dil kodu (tr, en, ar)

class PhoneVerificationSellerVerify(BaseModel):
    phone_number: str
    verification_code: str

# Email Verification
class EmailVerificationBase(BaseModel):
    id: int
    email: str
    verification_code: str
    is_verified: str
    attempts: int
    created_at: str
    expires_at: str

class EmailVerificationCreate(BaseModel):
    email: str
    language: Optional[str] = None  # Dil kodu (tr, en, ar)

class EmailVerificationVerify(BaseModel):
    email: str
    verification_code: str

class EmailVerificationResponse(BaseModel):
    message: str
    success: bool
    expires_in: Optional[int] = None

# Seller Email Verification
class EmailVerificationSellerCreate(BaseModel):
    email: str
    language: Optional[str] = None  # Dil kodu (tr, en, ar)

class EmailVerificationSellerVerify(BaseModel):
    email: str
    verification_code: str

class EmailVerificationSellerResponse(BaseModel):
    message: str
    success: bool
    expires_in: Optional[int] = None
