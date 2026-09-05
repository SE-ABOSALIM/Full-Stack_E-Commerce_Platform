"""Canonical phone identities shared by account, verification and SMS flows."""

import re

from fastapi import HTTPException


_PRESENTATION_CHARACTERS = re.compile(r"[\s()-]")
_TURKISH_MOBILE = re.compile(r"5[0-9]{9}")
_INTERNATIONAL = re.compile(r"\+[1-9][0-9]{7,14}")


def normalize_phone_number(raw_phone: str) -> str:
    """Return an E.164-compatible identity or reject unsupported input."""
    if not isinstance(raw_phone, str):
        raise HTTPException(422, "Invalid phone number")

    phone = _PRESENTATION_CHARACTERS.sub("", raw_phone)
    if phone.startswith("00"):
        phone = "+" + phone[2:]

    if _TURKISH_MOBILE.fullmatch(phone):
        phone = "+90" + phone
    elif re.fullmatch(r"0" + _TURKISH_MOBILE.pattern, phone):
        phone = "+90" + phone[1:]

    if phone.startswith("+90"):
        if not re.fullmatch(r"\+90" + _TURKISH_MOBILE.pattern, phone):
            raise HTTPException(422, "Invalid phone number")
    elif not _INTERNATIONAL.fullmatch(phone):
        raise HTTPException(422, "Invalid phone number")

    return phone
