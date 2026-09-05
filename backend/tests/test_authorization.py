"""Real bearer verification and cross-account requests against the disposable DB."""
import base64
import json
import time
from datetime import datetime, timedelta
from unittest.mock import Mock

import pytest

PASSWORD = "Original-password-123!"
NEW_PASSWORD = "Changed-password-456!"
ADDRESS = dict(city="City", district="District", neighbourhood="Area", street_name="Street",
               building_number="1", apartment_number="2", address_name="Home")
PRODUCT = dict(product_name="Product", product_price=10, product_description="Description",
               product_category="Test", product_image_url="")


@pytest.fixture
def actors(backend, db):
    users, sellers = [], []
    for index in (1, 2):
        users.append(backend.models.User(
            name_surname=f"User {index}", email=f"user{index}@example.com",
            phone_number=f"+90532000000{index}", password=backend.hash_password(PASSWORD),
            phone_verified="verified", email_verified="pending"))
        sellers.append(backend.models.Seller(
            name=f"Seller {index}", email=f"seller{index}@example.com", phone=f"+90533000000{index}",
            password=backend.hash_password(PASSWORD), store_name=f"Store {index}"))
    db.add_all(users + sellers)
    db.commit()
    return users, sellers


def profile(user):
    return dict(name_surname="Updated", email=user.email, phone_number=user.phone_number)


def test_user_profile_ownership_and_password_contract(client, db, actors, auth_headers):
    a, b = actors[0]
    original = b.password
    assert client.put(f"/users/{a.id}", json=profile(a)).status_code == 401
    headers = auth_headers(a)
    assert client.put(f"/users/{b.id}", json=profile(b), headers=headers).status_code == 403
    assert client.delete(f"/users/{b.id}", headers=headers).status_code == 403
    assert client.put("/users/me", json=profile(a), headers=headers).status_code == 200
    assert client.get("/users/me", headers=headers).json()["id"] == a.id
    assert client.put(f"/users/{a.id}", json=profile(a), headers=headers).status_code == 200
    response = client.put("/users/me", json={**profile(a), "password": NEW_PASSWORD}, headers=headers)
    assert response.status_code == 422
    assert NEW_PASSWORD not in response.text
    db.refresh(b)
    assert b.password == original


def test_password_change_is_self_only_and_invalidates_old_credentials(client, backend, db, actors, auth_headers):
    a, b = actors[0]
    original_b = b.password
    headers = auth_headers(a)
    body = {"current_password": PASSWORD, "new_password": NEW_PASSWORD, "new_password_again": NEW_PASSWORD}
    assert client.put("/users/me/password", json=body).status_code == 401
    assert client.put("/users/me/password", headers=headers, json={**body, "current_password": "wrong"}).status_code == 401
    assert client.put("/users/me/password", headers=headers, json={**body, "user_id": b.id}).status_code == 422
    response = client.put("/users/me/password", headers=headers, json=body)
    assert response.status_code == 200
    assert PASSWORD not in response.text and NEW_PASSWORD not in response.text
    assert client.get("/users/me", headers=headers).status_code == 401
    assert client.post("/users/login", data={"email": a.email, "password": PASSWORD}).status_code == 401
    new_headers = auth_headers(a, NEW_PASSWORD)
    assert client.get("/users/me", headers=new_headers).status_code == 200
    db.refresh(a)
    db.refresh(b)
    assert backend.verify_password(NEW_PASSWORD, a.password)
    assert b.password == original_b


def test_invalid_expired_tampered_and_wrong_role_tokens(client, actors, auth_headers, monkeypatch):
    import app.auth as auth
    user = actors[0][0]
    seller = actors[1][0]
    assert user.id == seller.id  # Numeric overlap must not imply the same principal.
    seller_headers = auth_headers(seller, role="seller")
    assert client.put("/users/me", json=profile(user), headers=seller_headers).status_code == 403
    headers = auth_headers(user)
    assert client.put(f"/sellers/profile?seller_id={seller.id}", data={"name": "Bad"}, headers=headers).status_code == 403
    token = headers["Authorization"].split()[1]
    payload, signature = token.split('.')
    claims = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4)))
    claims['id'] = actors[0][1].id
    forged_payload = auth.encode(json.dumps(claims).encode())
    for invalid in ("junk", forged_payload + '.' + signature, token + '.extra', 'x' * 3000):
        assert client.get("/users/me", headers={"Authorization": "Bearer " + invalid}).status_code == 401
    with monkeypatch.context() as patch:
        patch.setattr(auth.time, "time", lambda: time.time_ns() // 1_000_000_000 - 4000)
        expired = auth.issue_access_token(user, "user")
    assert client.get("/users/me", headers={"Authorization": "Bearer " + expired}).status_code == 401
    monkeypatch.delenv("AUTH_SECRET_KEY")
    assert client.post("/users/login", data={"email": user.email, "password": PASSWORD}).status_code == 503


@pytest.fixture
def reset_setup(client, backend, db, actors, monkeypatch):
    user = actors[0][0]
    sms = Mock(return_value=True)
    monkeypatch.setattr(backend.verification_routes, "send_sms_verification", sms)
    def request():
        response = client.post("/auth/forgot-password/request", json={"phone_number": user.phone_number})
        assert response.status_code == 200, response.text
        return sms.call_args.args[1]
    return user, sms, request


def reset_body(user, code):
    return dict(phone_number=user.phone_number, verification_code=code, new_password=NEW_PASSWORD)


def test_reset_requests_fresh_challenges_throttles_resend_and_invalidates_old_code(client, backend, db, reset_setup):
    user, sms, request = reset_setup
    code = request()
    row = db.query(backend.models.PasswordResetVerification).one()
    assert row.user_id == user.id and row.phone_number == user.phone_number
    assert row.code_hash != code and row.attempts == 0 and row.consumed_at is None
    assert 290 <= (row.expires_at - datetime.utcnow()).total_seconds() <= 300
    request()
    assert sms.call_count == 1  # A rapid resend cannot reset the attempt budget.
    row.created_at = datetime.utcnow() - timedelta(seconds=61)
    db.commit()
    new_code = request()
    assert sms.call_count == 2
    db.refresh(row)
    assert row.code_hash == backend.reset_code_hash(user.phone_number, new_code)
    if code != new_code:
        assert client.post("/auth/forgot-password/reset", json=reset_body(user, code)).status_code == 400


@pytest.mark.parametrize("purpose", ["registration", "phone_change", "seller_registration"])
def test_other_verification_or_historical_phone_cannot_reset(client, backend, db, actors, purpose):
    user = actors[0][0]
    model = backend.models.PhoneVerificationSeller if purpose == "seller_registration" else backend.models.PhoneVerification
    db.add(model(phone_number=user.phone_number, verification_code="123456", is_verified="verified",
                 attempts=0, created_at=datetime.utcnow(), expires_at=datetime.utcnow() + timedelta(minutes=5)))
    db.commit()
    assert client.post("/auth/forgot-password/reset", json=reset_body(user, "123456")).status_code == 400
    db.refresh(user)
    assert backend.verify_password(PASSWORD, user.password)


def test_wrong_code_attempt_limit(client, backend, db, reset_setup):
    user, sms, request = reset_setup
    code = request()
    wrong = "000000" if code != "000000" else "111111"
    for _ in range(4):
        assert client.post("/auth/forgot-password/reset", json=reset_body(user, wrong)).status_code == 400
    assert db.query(backend.models.PasswordResetVerification).one().attempts == 3
    assert client.post("/auth/forgot-password/reset", json=reset_body(user, code)).status_code == 400


def test_expired_code_rejected(client, backend, db, reset_setup):
    user, sms, request = reset_setup
    code = request()
    db.query(backend.models.PasswordResetVerification).one().expires_at = datetime.utcnow() - timedelta(seconds=1)
    db.commit()
    assert client.post("/auth/forgot-password/reset", json=reset_body(user, code)).status_code == 400


def test_reset_changes_password_once_and_rejects_other_phone(client, backend, db, actors, reset_setup, auth_headers, capsys):
    user, sms, request = reset_setup
    headers = auth_headers(user)
    code = request()
    assert client.post("/auth/forgot-password/reset", json=reset_body(actors[0][1], code)).status_code == 400
    response = client.post("/auth/forgot-password/reset", json=reset_body(user, code))
    assert response.status_code == 200
    assert client.post("/auth/forgot-password/reset", json=reset_body(user, code)).status_code == 400
    assert client.post("/users/login", data={"email": user.email, "password": PASSWORD}).status_code == 401
    auth_headers(user, NEW_PASSWORD)
    assert client.get("/users/me", headers=headers).status_code == 401
    db.refresh(user)
    assert backend.verify_password(NEW_PASSWORD, user.password)
    output = capsys.readouterr()
    for secret in (code, PASSWORD, NEW_PASSWORD, user.phone_number, headers["Authorization"]):
        assert secret not in output.out + output.err
        assert secret not in response.text


def test_failed_sms_and_unknown_phone_do_not_authorize_reset(client, backend, db, reset_setup):
    user, sms, request = reset_setup
    sms.return_value = False
    assert client.post("/auth/forgot-password/request", json={"phone_number": user.phone_number}).status_code == 503
    assert db.query(backend.models.PasswordResetVerification).count() == 0
    sms.reset_mock()
    assert client.post("/auth/forgot-password/request", json={"phone_number": "+905320009999"}).status_code == 200
    sms.assert_not_called()


def test_seller_profile_products_and_ownership_transfer(client, backend, db, actors, auth_headers):
    a, b = actors[1]
    headers = auth_headers(a, role="seller")
    assert client.put(f"/sellers/profile?seller_id={a.id}", data={"name": "Updated"}).status_code == 401
    assert client.put(f"/sellers/profile?seller_id={b.id}", headers=headers, data={"name": "Bad"}).status_code == 403
    assert client.put("/sellers/profile", headers=headers, data={"name": "Updated"}).status_code == 200
    assert client.get("/sellers/profile", headers=headers).json()["id"] == a.id
    other = backend.models.Product(**PRODUCT, seller_id=b.id)
    db.add(other)
    db.commit()
    for method in ("put", "delete"):
        kwargs = {"json": PRODUCT} if method == "put" else {}
        assert client.request(method, f"/products/{other.id}", **kwargs).status_code == 401
        assert client.request(method, f"/products/{other.id}", headers=headers, **kwargs).status_code == 403
    assert client.post("/products", json={**PRODUCT, "seller_id": b.id}, headers=headers).status_code == 403
    product = client.post("/products", json=PRODUCT, headers=headers)
    assert product.status_code == 200
    assert product.json()["seller_id"] == a.id
    path = f"/products/{product.json()['id']}"
    assert client.put(path, json={**PRODUCT, "seller_id": b.id}, headers=headers).status_code == 403
    assert client.put(path, json={**PRODUCT, "product_name": "Updated"}, headers=headers).status_code == 200
    assert client.delete(path, headers=headers).status_code == 200
    assert client.delete(path, headers=headers).status_code == 404
    assert client.post("/upload-image", files={"file": ("image.png", b"test")}).status_code == 401


@pytest.fixture
def resources(backend, db, actors):
    m = backend.models
    groups = []
    for user, seller in zip(*actors):
        address = m.Address(**ADDRESS, user_id=user.id)
        card = m.CreditCard(user_id=user.id, provider="mock", card_token=f"private-card-{user.id}",
                           last4="1111", card_brand="visa", expiry_month=12, expiry_year=2099)
        product = m.Product(**PRODUCT, seller_id=seller.id)
        db.add_all([address, card, product])
        db.flush()
        order = m.Order(user_id=user.id, order_address=address.id, order_status="pending")
        db.add(order)
        db.flush()
        links = [m.UsersAddress(user_id=user.id, address_id=address.id),
                 m.UsersCreditCard(user_id=user.id, credit_card_id=card.id),
                 m.UsersOrder(user_id=user.id, order_id=order.id, product_id=product.id)]
        review = m.SellerReview(user_id=user.id, seller_id=seller.id, product_id=product.id, rating=4)
        db.add_all(links + [review])
        groups.append((address, card, product, order, links, review))
    db.commit()
    return groups


def test_other_user_mutations_and_links_reject_idor(client, db, actors, resources, auth_headers):
    a, b = actors[0]
    headers = auth_headers(a)
    address, card, product, order, links, review = resources[1]
    order_body = dict(order_code="test", order_created_date="2026-01-01", order_estimated_delivery="2026-01-02",
                      order_cargo_company="Test", order_address=address.id, order_status="pending")
    card_body = dict(provider="mock", card_token=card.card_token, card_brand="visa", last4="1111", expiry_month=12, expiry_year=2099)
    operations = [
        ("/address/" + str(address.id), ADDRESS),
        ("/credit_card/" + str(card.id), card_body),
        ("/order/" + str(order.id), order_body),
        ("/seller_reviews/" + str(review.id), {"rating": 1}),
        ("/users_address/" + str(links[0].id), {"user_id": a.id, "address_id": address.id}),
        ("/users_credit_card/" + str(links[1].id), {"user_id": a.id, "credit_card_id": card.id}),
        ("/users_order/" + str(links[2].id), {"user_id": a.id, "order_id": order.id, "product_id": product.id}),
    ]
    for path, body in operations:
        for method in ("put", "delete"):
            kwargs = {"json": body} if method == "put" else {}
            assert client.request(method, path, **kwargs).status_code == 401
            response = client.request(method, path, headers=headers, **kwargs)
            assert response.status_code == 403, (path, response.text)
    for path, body in operations[4:]:
        assert client.post(path.rsplit('/', 1)[0], json=body, headers=headers).status_code == 403
        assert client.post(path.rsplit('/', 1)[0], json={**body, "user_id": b.id}, headers=headers).status_code == 403
    assert client.post("/order", json=order_body, headers=headers).status_code == 403
    own_address = resources[0][0]
    assert client.post("/order", json={**order_body, "order_address": own_address.id, "card_id": card.id}, headers=headers).status_code == 403
    assert client.post("/credit_card", json={**card_body, "user_id": a.id}, headers=headers).status_code == 403
    for path in ("/address", "/order", "/credit_card", "/users_address", "/users_credit_card", "/users_order"):
        assert client.get(path).status_code == 401
        response = client.get(path, headers=headers)
        assert response.status_code == 200
        assert len(response.json()) == 1
    assert client.post(f"/users/{b.id}/follow-seller/{actors[1][0].id}", headers=headers).status_code == 403
    assert client.delete(f"/users/{b.id}/unfollow-seller/{actors[1][0].id}", headers=headers).status_code == 403
    assert client.post(f"/users/{a.id}/follow-seller/{actors[1][0].id}", headers=headers).status_code == 200
    assert client.delete(f"/users/{a.id}/unfollow-seller/{actors[1][0].id}", headers=headers).status_code == 200


def test_owned_address_order_links_and_review_mutations_work(client, backend, db, actors, resources, auth_headers):
    user = actors[0][0]
    headers = auth_headers(user)
    address = client.post("/address", json=ADDRESS, headers=headers)
    assert address.status_code == 200
    aid = address.json()['id']
    assert db.get(backend.models.Address, aid).user_id == user.id
    assert client.put(f"/address/{aid}", json={**ADDRESS, "city": "Updated"}, headers=headers).status_code == 200
    link = client.post("/users_address", json={"user_id": user.id, "address_id": aid}, headers=headers)
    assert link.status_code == 200
    assert client.delete(f"/users_address/{link.json()['id']}", headers=headers).status_code == 200
    card = resources[0][1]
    response = client.post("/order", json={"order_address": aid, "card_id": card.id, "amount": 10,
        "order_created_date": "01/01/2026", "order_estimated_delivery": "02/01/2026", "order_status": "delivered"}, headers=headers)
    assert response.status_code == 200, response.text
    oid = response.json()['id']
    assert response.json()['order_status'] == "pending"
    assert db.get(backend.models.Order, oid).user_id == user.id
    product = resources[0][2]
    link = client.post("/users_order", json={"user_id": user.id, "order_id": oid, "product_id": product.id}, headers=headers)
    assert link.status_code == 200
    assert client.delete(f"/users_order/{link.json()['id']}", headers=headers).status_code == 200
    review = resources[0][-1]
    assert client.put(f"/seller_reviews/{review.id}", json={"rating": 5}, headers=headers).status_code == 200
    assert client.delete(f"/seller_reviews/{review.id}", headers=headers).status_code == 200
    assert client.post("/seller_reviews", json={"user_id": user.id, "product_id": product.id,
        "seller_id": product.seller_id, "rating": 4}, headers=headers).status_code == 200


def test_seller_order_status_and_mixed_seller_order(client, backend, db, actors, resources, auth_headers):
    a, b = actors[1]
    headers = auth_headers(a, role="seller")
    order = resources[0][3]
    path = f"/seller_orders/{order.id}/status?status=shipped"
    assert client.put(path).status_code == 401
    assert client.put(f"/seller_orders/{resources[1][3].id}/status?status=shipped", headers=headers).status_code == 403
    assert client.put(path, headers=headers).status_code == 200
    assert client.put(f"/seller_orders/{order.id}/status?status=anything", headers=headers).status_code == 422
    db.add(backend.models.UsersOrder(user_id=actors[0][0].id, order_id=order.id, product_id=resources[1][2].id))
    db.commit()
    assert client.put(path, headers=headers).status_code == 403
    assert client.put(path, headers=auth_headers(b, role="seller")).status_code == 403


def test_card_tokenization_and_charge_enforce_owner(client, backend, db, actors, resources, auth_headers, monkeypatch):
    a, b = actors[0]
    headers = auth_headers(a)
    monkeypatch.setenv("PAYMENT_TEST_MODE", "true")
    request = dict(user_id=b.id, card_holder_name="Buyer", card_number="4111111111111111",
                   expire_month=12, expire_year=2099, cvc="123")
    assert client.post("/tokenize", json=request).status_code == 401
    assert client.post("/tokenize", json=request, headers=headers).status_code == 403
    request['user_id'] = a.id
    response = client.post("/tokenize", json=request, headers=headers)
    assert response.status_code == 200
    token = response.json()['card_token']
    assert db.query(backend.models.CreditCard).filter_by(card_token=token).one().user_id == a.id
    saved = client.post("/credit_card", headers=headers, json={**response.json(), "provider": "mock", "user_id": a.id})
    assert saved.status_code == 200
    own_card = resources[0][1]
    body = dict(provider="mock", card_token=resources[1][1].card_token, card_brand="visa", last4="1111", expiry_month=12, expiry_year=2099)
    assert client.put(f"/credit_card/{own_card.id}", headers=headers, json=body).status_code == 403
    charge = dict(user_id=a.id, price=10, paid_price=10, card_token=resources[1][1].card_token)
    assert client.post("/charge", headers=headers, json=charge).status_code == 403
    assert client.post("/charge", json=charge).status_code == 401
    assert client.post("/credit_card", headers=headers, json={**body, "card_token": "unissued", "user_id": a.id}).status_code == 400


@pytest.mark.parametrize("role", ["user", "seller"])
def test_account_verification_requires_owner(client, backend, db, actors, auth_headers, monkeypatch, role):
    a, b = actors[0 if role == "user" else 1]
    headers = auth_headers(a, role=role)
    email_prefix = "seller-" if role == "seller" else ""
    for path, body in [
        (f"/send-{email_prefix}email-verification-code", {"email": b.email}),
        (f"/verify-{email_prefix}email", {"email": b.email, "verification_code": "123456"}),
    ]:
        assert client.post(path, json=body).status_code == 401
        assert client.post(path, json=body, headers=headers).status_code == 403
    assert client.post(f"/{role}s/{b.id}/send-phone-verification", headers=headers).status_code == 403
    assert client.post(f"/{role}s/{a.id}/send-phone-verification").status_code == 401
    monkeypatch.setattr(backend.verification_routes, "generate_verification_code", lambda: "123456")
    monkeypatch.setattr(backend.verification_routes, "send_sms_verification", Mock(return_value=True))
    assert client.post(f"/{role}s/{a.id}/send-phone-verification", headers=headers).status_code == 200
    phone = a.phone_number if role == "user" else a.phone
    path = "/verify-phone" if role == "user" else "/verify-seller-phone"
    body = {"phone_number": phone, "verification_code": "123456"}
    assert client.post(path, json=body).status_code == 401
    assert client.post(path, json=body, headers=auth_headers(b, role=role)).status_code == 403
    assert client.post(path, json=body, headers=headers).status_code == 200
    db.refresh(a)
    assert a.phone_verified == "verified"


def test_direct_sms_utilities_never_send(client, backend, actors, auth_headers, monkeypatch):
    sms = Mock()
    monkeypatch.setattr(backend, "twilio_sms_service", sms)
    headers = auth_headers(actors[0][0])
    paths = ["/sms/welcome?phone_number=123", "/sms/order-status?phone_number=123&order_number=1&status=shipped",
             "/sms/promotional?phone_number=123&discount=10&valid_until=tomorrow"]
    for path in paths:
        assert client.post(path).status_code == 401
        assert client.post(path, headers=headers).status_code == 403
    assert not sms.mock_calls


def test_payment_link_updates_and_deletes_work_only_for_owner(client, actors, resources, auth_headers):
    user = actors[0][0]
    address, card, product, order, links, review = resources[0]
    headers = auth_headers(user)
    for path, body in [
        (f"/users_address/{links[0].id}", {"user_id": user.id, "address_id": address.id}),
        (f"/users_credit_card/{links[1].id}", {"user_id": user.id, "credit_card_id": card.id}),
        (f"/users_order/{links[2].id}", {"user_id": user.id, "order_id": order.id, "product_id": product.id}),
    ]:
        assert client.put(path, headers=headers, json=body).status_code == 200
    card_body = dict(provider="mock", card_token=card.card_token, card_brand="visa", last4="1111",
                     expiry_month=12, expiry_year=2099, is_default=True)
    assert client.put(f"/credit_card/{card.id}", headers=headers, json=card_body).status_code == 200
    assert client.delete(f"/users_credit_card/{links[1].id}", headers=headers).status_code == 200
    assert client.delete(f"/credit_card/{card.id}", headers=headers).status_code == 200
    assert client.post("/seller_reviews", headers=headers, json={"user_id": actors[0][1].id,
        "product_id": product.id, "seller_id": product.seller_id, "rating": 4}).status_code == 403


def test_phone_changes_cannot_claim_another_user_or_keep_old_reset_challenge(client, backend, db, actors, reset_setup, auth_headers, monkeypatch):
    user, sms, request = reset_setup
    code = request()
    headers = auth_headers(user)
    assert client.put("/users/me", headers=headers, json={**profile(user), "phone_number": actors[0][1].phone_number}).status_code == 400
    response = client.put("/users/me", headers=headers, json={**profile(user), "phone_number": "+905329999999"})
    assert response.status_code == 200
    assert db.query(backend.models.PasswordResetVerification).count() == 0
    assert client.post("/auth/forgot-password/reset", json=reset_body(user, code)).status_code == 400


def test_simultaneous_reset_consumes_code_only_once(client, backend, db, reset_setup):
    from concurrent.futures import ThreadPoolExecutor
    from fastapi.testclient import TestClient
    from threading import Barrier
    user, sms, request = reset_setup
    code = request()
    body = reset_body(user, code)
    barrier = Barrier(2)
    def attempt():
        with TestClient(backend.app) as other_client:
            barrier.wait(timeout=10)
            return other_client.post("/auth/forgot-password/reset", json=body).status_code
    with ThreadPoolExecutor(max_workers=2) as pool:
        attempts = [pool.submit(attempt) for _ in range(2)]
        assert sorted(future.result(timeout=15) for future in attempts) == [200, 400]


@pytest.mark.parametrize("body", [
    {"current_password": [PASSWORD], "new_password": NEW_PASSWORD, "new_password_again": NEW_PASSWORD},
    {"current_password": PASSWORD, "new_password": [NEW_PASSWORD], "new_password_again": NEW_PASSWORD},
    {"current_password": PASSWORD, "new_password": "xYzQ7!", "new_password_again": "xYzQ7!"},
])
def test_password_validation_never_echoes_credentials(client, actors, auth_headers, body):
    response = client.put("/users/me/password", headers=auth_headers(actors[0][0]), json=body)
    assert response.status_code == 422
    for value in (PASSWORD, NEW_PASSWORD, "xYzQ7!"):
        assert value not in response.text


def test_own_product_cannot_delete_another_products_image(client, backend, db, actors, auth_headers, monkeypatch):
    a, b = actors[1]
    image = "/uploads/Product_Image/shared.png"
    other = backend.models.Product(**{**PRODUCT, "product_image_url": image}, seller_id=b.id)
    own = backend.models.Product(**{**PRODUCT, "product_image_url": image}, seller_id=a.id)
    db.add_all([other, own])
    db.commit()
    delete_file = Mock()
    monkeypatch.setattr(backend.file_service, "delete_file_safely", delete_file)
    headers = auth_headers(a, role="seller")
    assert client.put(f"/products/{own.id}", headers=headers, json=PRODUCT).status_code == 200
    delete_file.assert_not_called()
    assert client.put(f"/products/{own.id}", headers=headers, json={**PRODUCT, "product_image_url": image}).status_code == 200
    assert client.delete(f"/products/{own.id}", headers=headers).status_code == 200
    delete_file.assert_not_called()
    backend.delete_unreferenced_product_image(db, r"..\..\outside.txt", 0)
    delete_file.assert_not_called()
