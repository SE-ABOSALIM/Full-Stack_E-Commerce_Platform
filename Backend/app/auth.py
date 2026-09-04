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
