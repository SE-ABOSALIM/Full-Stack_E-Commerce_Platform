"""Shared database, authentication, and ownership dependencies."""

import hmac

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

import app.models as models
from app.auth import password_stamp, read_access_token
from app.db import SessionLocal


bearer = HTTPBearer(auto_error=False)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def current_actor(credentials: HTTPAuthorizationCredentials = Depends(bearer), db: Session = Depends(get_db)):
    if credentials is None:
        raise HTTPException(401, "Authentication required", headers={"WWW-Authenticate": "Bearer"})
    claims = read_access_token(credentials.credentials)
    model = models.User if claims["role"] == "user" else models.Seller
    actor = db.get(model, claims["id"])
    if actor is None or not hmac.compare_digest(claims["stamp"], password_stamp(actor.password)):
        raise HTTPException(401, "Invalid or expired credentials", headers={"WWW-Authenticate": "Bearer"})
    return actor


def current_user(actor=Depends(current_actor)):
    if not isinstance(actor, models.User):
        raise HTTPException(403, "User credentials required")
    return actor


def optional_actor(credentials: HTTPAuthorizationCredentials = Depends(bearer), db: Session = Depends(get_db)):
    return current_actor(credentials, db) if credentials else None


def current_seller(actor=Depends(current_actor)):
    if not isinstance(actor, models.Seller):
        raise HTTPException(403, "Seller credentials required")
    return actor


def require_owner(owner_id, actor):
    if owner_id != actor.id:
        raise HTTPException(403, "Resource belongs to another account")


def owned_resource(db, model, resource_id, actor, owner_field="user_id"):
    resource = db.get(model, resource_id)
    if resource is None:
        raise HTTPException(404, "Resource not found")
    require_owner(getattr(resource, owner_field), actor)
    return resource
