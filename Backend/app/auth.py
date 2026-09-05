"""Small signed access credentials; no refresh tokens or server-side sessions.

The wire format is base64url(JSON).base64url(HMAC-SHA256), not JWT.
The role is signed so overlapping user/seller IDs cannot cross boundaries.
"""

import base64
import hashlib
import hmac
import json
import os
import time

from fastapi import HTTPException


def signing_key():
    key = os.getenv("AUTH_SECRET_KEY", "")
    if len(key.encode()) < 32:
        raise HTTPException(503, "Authentication is not configured")
    return key.encode()


def encode(value):
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def decode(value):
    return base64.b64decode(value + "=" * (-len(value) % 4), altchars=b"-_", validate=True)


def password_stamp(stored_password):
    # A password change also invalidates existing access credentials, without a blacklist.
    return hmac.new(signing_key(), ("password:" + stored_password).encode(), hashlib.sha256).hexdigest()


def issue_access_token(actor, role):
    payload = encode(json.dumps({
        "id": actor.id, "role": role, "exp": int(time.time()) + 3600,
        "stamp": password_stamp(actor.password),
    }, separators=(",", ":")).encode())
    signature = encode(hmac.new(signing_key(), payload.encode(), hashlib.sha256).digest())
    return payload + "." + signature


def read_access_token(token):
    key = signing_key()
    try:
        if len(token) > 2048:
            raise ValueError()
        payload, signature = token.split(".")
        expected = hmac.new(key, payload.encode("ascii"), hashlib.sha256).digest()
        if not hmac.compare_digest(expected, decode(signature)):
            raise ValueError()
        claims = json.loads(decode(payload))
        if (type(claims["id"]) is not int or claims["id"] <= 0
                or claims["role"] not in ("user", "seller")
                or type(claims["exp"]) is not int or claims["exp"] <= time.time()
                or not isinstance(claims["stamp"], str)):
            raise ValueError()
        return claims
    except (ValueError, KeyError, TypeError, UnicodeError):
        raise HTTPException(401, "Invalid or expired credentials", headers={"WWW-Authenticate": "Bearer"}) from None


PBKDF2_ITERATIONS = 100_000
SALT_BYTES = 16


def hash_password(plain_password: str) -> str:
    """Return a salted PBKDF2 hash for the given password."""
    salt = os.urandom(SALT_BYTES)
    pwd_hash = hashlib.pbkdf2_hmac(
        "sha256",
        plain_password.encode("utf-8"),
        salt,
        PBKDF2_ITERATIONS,
    )
    # Store as base64(salt):base64(hash) to keep column as string
    return f"{base64.b64encode(salt).decode('utf-8')}:{base64.b64encode(pwd_hash).decode('utf-8')}"


def verify_password(plain_password: str, stored_password: str) -> bool:
    """
    Check a plaintext password against a stored salted hash.
    Supports legacy plaintext records for backward compatibility.
    """
    if not stored_password:
        return False

    # Legacy plaintext support
    if ":" not in stored_password:
        return hmac.compare_digest(plain_password, stored_password)

    try:
        salt_b64, hash_b64 = stored_password.split(":", 1)
        salt = base64.b64decode(salt_b64.encode("utf-8"))
        stored_hash = base64.b64decode(hash_b64.encode("utf-8"))
        new_hash = hashlib.pbkdf2_hmac(
            "sha256",
            plain_password.encode("utf-8"),
            salt,
            PBKDF2_ITERATIONS,
        )
        return hmac.compare_digest(new_hash, stored_hash)
    except Exception:
        return False
