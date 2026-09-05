"""FastAPI application assembly."""

import os

from fastapi import FastAPI
from fastapi.exception_handlers import request_validation_exception_handler
from fastapi.exceptions import RequestValidationError
from fastapi.staticfiles import StaticFiles
from dotenv import load_dotenv

import app.models as models
from app.auth import hash_password, verify_password
from app.db import SessionLocal, engine
from app.phone_numbers import normalize_phone_number
from app.routers import orders as order_routes
from app.routers import payments as payment_routes
from app.routers import products as product_routes
from app.routers import reviews as review_routes
from app.routers import sellers as seller_routes
from app.routers import system as system_routes
from app.routers import users as user_routes
from app.routers import verification as verification_routes
from app.services import files as file_service
from app.services.email_service import email_service
from app.services.files import delete_file_safely, delete_unreferenced_product_image
from app.services.twilio_sms_service import twilio_sms_service
from app.services.verification import reset_code_hash


BASE_DIR = os.path.dirname(os.path.dirname(__file__))
load_dotenv(os.path.join(BASE_DIR, "config.env"))

models.Base.metadata.create_all(bind=engine)
app = FastAPI()


SENSITIVE_FIELDS = {
    "password",
    "current_password",
    "new_password",
    "new_password_again",
    "verification_code",
    "access_token",
    "authorization",
    "card_token",
    "card_number",
    "cvc",
}


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
            error.pop("input", None)
        elif "input" in error:
            error["input"] = omit_passwords(error["input"])
        errors.append(error)
    return await request_validation_exception_handler(
        request, RequestValidationError(errors)
    )


app.mount(
    "/uploads",
    StaticFiles(directory=os.path.join(BASE_DIR, "uploads")),
    name="uploads",
)

for router in (
    user_routes.router,
    payment_routes.router,
    product_routes.router,
    verification_routes.router,
    seller_routes.router,
    order_routes.router,
    review_routes.router,
    system_routes.router,
):
    app.include_router(router)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="127.0.0.1", port=8000)
