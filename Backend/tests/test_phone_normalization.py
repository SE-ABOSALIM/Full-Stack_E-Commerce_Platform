"""Canonical phone identity regressions across account and verification flows."""

from datetime import datetime, timedelta
from unittest.mock import Mock

import pytest
from fastapi import HTTPException


CANONICAL = "+905556667711"
EQUIVALENT_TURKISH_NUMBERS = (
    "+90 555 666 77 11",
    "+905556667711",
    "0555 666 77 11",
    "05556667711",
    "555 666 77 11",
    "5556667711",
    "0555-666-77-11",
    "(0555) 666 77 11",
    "+90 (555) 666 77 11",
)
PASSWORD = "Original-password-123!"


@pytest.mark.parametrize("raw_phone", EQUIVALENT_TURKISH_NUMBERS)
def test_turkish_variants_normalize_to_one_identity(backend, raw_phone):
    assert backend.normalize_phone_number(raw_phone) == CANONICAL


@pytest.mark.parametrize(
    "raw_phone",
    ("555", "055566677110", "+9005556667711", "+90555666", "phone", "++905556667711"),
)
def test_invalid_phone_numbers_are_rejected(backend, raw_phone):
    with pytest.raises(HTTPException) as error:
        backend.normalize_phone_number(raw_phone)
    assert error.value.status_code == 422


def test_explicit_international_number_remains_supported(backend):
    assert backend.normalize_phone_number("+1 (415) 555-2671") == "+14155552671"
    assert backend.normalize_phone_number("0044 7700 900123") == "+447700900123"


def test_user_signup_otp_and_uniqueness_share_canonical_identity(
    client, backend, db, monkeypatch
):
    monkeypatch.setattr(backend, "generate_verification_code", lambda: "123456")
    sms = Mock(return_value=True)
    monkeypatch.setattr(backend, "send_sms_verification", sms)

    response = client.post(
        "/send-verification-code",
        json={"phone_number": "0555 666 77 11", "language": "tr"},
    )
    assert response.status_code == 200, response.text
    challenge = db.query(backend.models.PhoneVerification).one()
    assert challenge.phone_number == CANONICAL
    assert sms.call_args.args[0] == CANONICAL

    response = client.post(
        "/verify-phone",
        json={"phone_number": "+90 (555) 666 77 11", "verification_code": "123456"},
    )
    assert response.status_code == 200, response.text

    response = client.post(
        "/users",
        json={
            "name_surname": "Canonical User",
            "email": "canonical@example.com",
            "password": PASSWORD,
            "phone_number": "555-666-77-11",
        },
    )
    assert response.status_code == 200, response.text
    assert response.json()["phone_number"] == CANONICAL

    duplicate = client.post(
        "/users",
        json={
            "name_surname": "Duplicate User",
            "email": "duplicate@example.com",
            "password": PASSWORD,
            "phone_number": "+90 555 666 77 11",
        },
    )
    assert duplicate.status_code == 400
    assert db.query(backend.models.User).count() == 1


def test_seller_signup_otp_and_uniqueness_share_canonical_identity(
    client, backend, db, monkeypatch
):
    monkeypatch.setattr(backend, "generate_verification_code", lambda: "654321")
    monkeypatch.setattr(backend, "send_sms_verification", Mock(return_value=True))

    response = client.post(
        "/send-seller-verification-code",
        json={"phone_number": "(0555) 666 77 11", "language": "tr"},
    )
    assert response.status_code == 200, response.text
    challenge = db.query(backend.models.PhoneVerificationSeller).one()
    assert challenge.phone_number == CANONICAL

    response = client.post(
        "/verify-seller-phone",
        json={"phone_number": "+905556667711", "verification_code": "654321"},
    )
    assert response.status_code == 200, response.text

    seller = {
        "name": "Canonical Seller",
        "email": "seller@example.com",
        "password": PASSWORD,
        "phone": "555 666 77 11",
        "store_name": "Canonical Store",
    }
    response = client.post("/sellers/signup", data=seller)
    assert response.status_code == 200, response.text
    assert response.json()["phone"] == CANONICAL

    duplicate = client.post(
        "/sellers/signup",
        data={**seller, "email": "other-seller@example.com", "phone": "05556667711"},
    )
    assert duplicate.status_code == 400
    assert db.query(backend.models.Seller).count() == 1


def test_user_profile_formatting_only_change_preserves_verification(
    client, backend, db, auth_headers, monkeypatch
):
    user = backend.models.User(
        name_surname="Profile User",
        email="profile@example.com",
        password=backend.hash_password(PASSWORD),
        phone_number="+90 555 666 77 11",
        phone_verified="verified",
        email_verified="pending",
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    reset = backend.models.PasswordResetVerification(
        user_id=user.id,
        phone_number=CANONICAL,
        code_hash="hash",
        attempts=0,
        created_at=datetime.utcnow(),
        expires_at=datetime.utcnow() + timedelta(minutes=5),
    )
    db.add(reset)
    db.commit()
    headers = auth_headers(user)
    sms = Mock(return_value=True)
    monkeypatch.setattr(backend, "send_sms_verification", sms)

    response = client.put(
        "/users/me",
        headers=headers,
        json={
            "name_surname": user.name_surname,
            "email": user.email,
            "phone_number": "0555-666-77-11",
        },
    )
    assert response.status_code == 200, response.text
    db.refresh(user)
    assert user.phone_number == CANONICAL
    assert user.phone_verified == "verified"
    assert db.query(backend.models.PasswordResetVerification).count() == 1
    sms.assert_not_called()

    changed = client.put(
        "/users/me",
        headers=headers,
        json={
            "name_surname": user.name_surname,
            "email": user.email,
            "phone_number": "0532 000 00 01",
        },
    )
    assert changed.status_code == 200, changed.text
    db.refresh(user)
    assert user.phone_number == "+905320000001"
    assert user.phone_verified == "pending"
    assert db.query(backend.models.PasswordResetVerification).count() == 0
    assert db.query(backend.models.PhoneVerification).one().phone_number == "+905320000001"
    assert sms.call_args.args[0] == "+905320000001"


def test_seller_profile_compares_canonical_phone_identity(
    client, backend, db, auth_headers, monkeypatch
):
    seller = backend.models.Seller(
        name="Profile Seller",
        email="profile-seller@example.com",
        password=backend.hash_password(PASSWORD),
        phone="+90 555 666 77 11",
        phone_verified="verified",
        email_verified="pending",
        store_name="Profile Store",
        is_verified="pending",
    )
    db.add(seller)
    db.commit()
    db.refresh(seller)
    headers = auth_headers(seller, role="seller")
    sms = Mock(return_value=True)
    monkeypatch.setattr(backend, "send_sms_verification", sms)

    response = client.put(
        "/sellers/profile", headers=headers, data={"phone": "05556667711"}
    )
    assert response.status_code == 200, response.text
    db.refresh(seller)
    assert seller.phone == CANONICAL
    assert seller.phone_verified == "verified"
    sms.assert_not_called()

    changed = client.put(
        "/sellers/profile", headers=headers, data={"phone": "0533 000 00 01"}
    )
    assert changed.status_code == 200, changed.text
    db.refresh(seller)
    assert seller.phone == "+905330000001"
    assert seller.phone_verified == "pending"
    assert db.query(backend.models.PhoneVerificationSeller).one().phone_number == "+905330000001"
    assert sms.call_args.args[0] == "+905330000001"


def test_password_reset_request_and_reset_accept_equivalent_formats(
    client, backend, db, monkeypatch
):
    user = backend.models.User(
        name_surname="Reset User",
        email="reset@example.com",
        password=backend.hash_password(PASSWORD),
        phone_number="+90 555 666 77 11",
        phone_verified="verified",
        email_verified="pending",
    )
    db.add(user)
    db.commit()
    sms = Mock(return_value=True)
    monkeypatch.setattr(backend, "send_sms_verification", sms)

    response = client.post(
        "/auth/forgot-password/request", json={"phone_number": "0555 666 77 11"}
    )
    assert response.status_code == 200, response.text
    code = sms.call_args.args[1]
    challenge = db.query(backend.models.PasswordResetVerification).one()
    assert challenge.phone_number == CANONICAL

    response = client.post(
        "/auth/forgot-password/reset",
        json={
            "phone_number": "555-666-77-11",
            "verification_code": code,
            "new_password": "Changed-password-456!",
        },
    )
    assert response.status_code == 200, response.text
    db.refresh(user)
    assert backend.verify_password("Changed-password-456!", user.password)


def test_twilio_transport_receives_canonical_destination(backend):
    from app.services.twilio_sms_service import TwilioSMS

    service = TwilioSMS()
    service.client = Mock()
    service.client.messages.create.return_value = Mock(
        sid="message-id", status="queued", price=None
    )

    result = service.send_sms("0555 666 77 11", "test", "tr")

    assert result["success"] is True
    assert service.client.messages.create.call_args.kwargs["to"] == CANONICAL
