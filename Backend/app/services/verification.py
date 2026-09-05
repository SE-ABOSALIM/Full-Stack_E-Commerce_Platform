"""Reusable phone and verification challenge operations."""

import hashlib
import hmac
import random
import string

from fastapi import HTTPException

from app.auth import signing_key
from app.phone_numbers import normalize_phone_number
from app.services.sms_language_manager import sms_language_manager
from app.services.twilio_sms_service import twilio_sms_service


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


def reset_code_hash(phone, code):
    return hmac.new(signing_key(), ("password-reset:" + phone + ":" + code).encode(), hashlib.sha256).hexdigest()


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
