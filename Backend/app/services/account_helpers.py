"""Shared account lookup and contact-ownership helpers."""

from fastapi import HTTPException

import app.models as models
from app.dependencies import require_owner
from app.phone_numbers import normalize_phone_number
from app.services.verification import phone_records


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
