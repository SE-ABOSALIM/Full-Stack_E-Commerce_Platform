from datetime import datetime, timedelta

import pytest


PASSWORD = "Original-password-123!"
NEW_PASSWORD = "Replacement-password-456!"
USER_INPUT = {
    "name_surname": "Test Buyer",
    "email": "buyer@example.com",
    "phone_number": "+90 532 123 45 67",
    "password": PASSWORD,
}
PUBLIC_FIELDS = {
    "id", "name_surname", "email", "phone_number", "phone_verified",
    "email_verified", "created_at", "updated_at",
}


def assert_no_password(value, *secrets):
    if isinstance(value, dict):
        assert "password" not in value
        for child in value.values():
            assert_no_password(child, *secrets)
    elif isinstance(value, list):
        for child in value:
            assert_no_password(child, *secrets)
    elif isinstance(value, str):
        for secret in secrets:
            assert secret not in value


def assert_public_user(response, stored_password):
    assert response.status_code == 200, response.text
    body = response.json()
    expected = PUBLIC_FIELDS | ({"access_token", "token_type"} if response.request.url.path.endswith("/login") else set())
    assert set(body) == expected
    assert_no_password(body, PASSWORD, NEW_PASSWORD, stored_password)
    assert body["email"] == USER_INPUT["email"]
    assert body["phone_number"].replace(" ", "") == USER_INPUT["phone_number"].replace(" ", "")
    assert body["phone_verified"] == "verified"
    assert body["email_verified"] == "pending"
    datetime.fromisoformat(body["created_at"])
    datetime.fromisoformat(body["updated_at"])
    return body


@pytest.fixture
def verified_phone(backend, db):
    db.add(backend.models.PhoneVerification(
        phone_number=USER_INPUT["phone_number"],
        verification_code="123456", is_verified="verified", attempts=0,
        created_at=datetime.now(), expires_at=datetime.now() + timedelta(minutes=5),
    ))
    db.commit()


@pytest.fixture
def user(backend, db):
    user = backend.models.User(
        **{**USER_INPUT, "password": backend.hash_password(PASSWORD)},
        phone_verified="verified", email_verified="pending",
        created_at=datetime.now(), updated_at=datetime.now(),
    )
    db.add(user)
    db.commit()
    return user


def test_registration_response_and_stored_hash(client, backend, db, verified_phone):
    response = client.post("/users", json=USER_INPUT)
    stored = db.query(backend.models.User).one()
    body = assert_public_user(response, stored.password)
    assert body["id"] == stored.id
    assert body["name_surname"] == USER_INPUT["name_surname"]
    assert stored.password != PASSWORD
    assert ":" in stored.password
    assert backend.verify_password(PASSWORD, stored.password)
    assert_public_user(client.post("/users/login", data={
        "email": stored.email, "password": PASSWORD,
    }), stored.password)


@pytest.mark.parametrize("legacy_plaintext", [False, True])
def test_user_list_excludes_hashes_and_legacy_passwords(client, db, user, legacy_plaintext):
    if legacy_plaintext:
        user.password = PASSWORD
        db.commit()
    response = client.get("/users")
    assert response.status_code == 200
    assert len(response.json()) == 1
    assert set(response.json()[0]) == PUBLIC_FIELDS
    assert_no_password(response.json(), PASSWORD, user.password)


def test_password_update_and_subsequent_login(client, backend, db, user, auth_headers):
    old_hash = user.password
    response = client.put("/users/me/password", headers=auth_headers(user), json={
        "current_password": PASSWORD, "new_password": NEW_PASSWORD, "new_password_again": NEW_PASSWORD,
    })
    assert response.status_code == 200
    db.refresh(user)
    assert_no_password(response.json(), PASSWORD, NEW_PASSWORD, user.password)
    assert user.password not in (old_hash, NEW_PASSWORD)
    assert backend.verify_password(NEW_PASSWORD, user.password)
    assert_public_user(client.post("/users/login", data={
        "email": user.email, "password": NEW_PASSWORD,
    }), user.password)
    assert client.post("/users/login", data={
        "email": user.email, "password": PASSWORD,
    }).status_code == 401


def test_profile_update_without_password_preserves_hash(client, db, user, auth_headers):
    old_hash = user.password
    response = client.put(f"/users/{user.id}", headers=auth_headers(user), json={
        key: ("Updated Buyer" if key == "name_surname" else value)
        for key, value in USER_INPUT.items() if key != "password"
    })
    db.refresh(user)
    assert_public_user(response, old_hash)
    assert user.password == old_hash
    assert user.name_surname == "Updated Buyer"
    assert_public_user(client.post("/users/login", data={
        "email": user.email, "password": PASSWORD,
    }), old_hash)


@pytest.mark.parametrize("legacy_plaintext", [False, True])
def test_correct_password_login(client, db, user, legacy_plaintext):
    if legacy_plaintext:
        user.password = PASSWORD
        db.commit()
    assert_public_user(client.post("/users/login", data={
        "email": user.email, "password": PASSWORD,
    }), user.password)


@pytest.mark.parametrize("email,password", [
    (USER_INPUT["email"], "wrong-password"),
    ("missing@example.com", PASSWORD),
])
def test_authentication_failure_unchanged(client, user, email, password):
    response = client.post("/users/login", data={"email": email, "password": password})
    assert response.status_code == 401
    assert response.json() == {"detail": "E-posta veya şifre hatalı!"}
    assert_no_password(response.json(), PASSWORD, user.password, password)


@pytest.mark.parametrize("method,path,payload", [
    ("post", "/users", {"password": PASSWORD}),
    ("post", "/users", {**USER_INPUT, "password": [PASSWORD]}),
    ("put", "/users/1", {"password": PASSWORD}),
    ("put", "/users/1", {**USER_INPUT, "password": {"nested": PASSWORD}}),
    ("post", "/users", [USER_INPUT]),
    ("post", "/users", '{"password":"' + PASSWORD + '"}'),
    ("post", "/products", {"nested": {"password": PASSWORD}}),
])
def test_validation_errors_do_not_echo_passwords(client, backend, db, user, auth_headers, method, path, payload):
    actor = user
    role = "user"
    if path == "/products":
        actor = backend.models.Seller(name="Seller", email="seller@example.com", phone="+905320000000", password=backend.hash_password(PASSWORD), store_name="Store")
        db.add(actor)
        db.commit()
        role = "seller"
    response = client.request(method, path, headers=auth_headers(actor, role=role), json=payload)
    assert response.status_code == 422
    assert response.json()["detail"]
    # Error locations may name the password field, but never contain its value.
    assert_no_password(response.json(), PASSWORD)


def test_validation_errors_keep_non_password_details(client):
    response = client.post("/users", json={"name_surname": "Test Buyer", "password": PASSWORD})
    assert response.status_code == 422
    assert response.json() == {"detail": [
        {"type": "missing", "loc": ["body", field], "msg": "Field required",
         "input": {"name_surname": "Test Buyer"}}
        for field in ("email", "phone_number")
    ]}


@pytest.mark.parametrize("path", ["/users/login", "/sellers/login", "/sellers/signup"])
def test_invalid_form_does_not_echo_password(client, path):
    response = client.post(path, data={"password": PASSWORD})
    assert response.status_code == 422
    assert_no_password(response.json(), PASSWORD)


@pytest.mark.parametrize("content,content_type", [
    ('{"password":"' + PASSWORD + '",', "application/json"),
    ('{"password":"' + PASSWORD + '"}', "text/plain"),
])
def test_invalid_raw_body_does_not_echo_password(client, content, content_type):
    response = client.post("/users", content=content, headers={"Content-Type": content_type})
    assert response.status_code == 422
    assert_no_password(response.json(), PASSWORD)


def test_openapi_response_schemas_exclude_password(client):
    document = client.get("/openapi.json").json()
    schemas = document["components"]["schemas"]

    def walk_response(schema, visited):
        if isinstance(schema, dict):
            assert "password" not in schema.get("properties", {})
            reference = schema.get("$ref")
            if reference and reference not in visited:
                visited.add(reference)
                walk_response(schemas[reference.rsplit("/", 1)[-1]], visited)
            for child in schema.values():
                walk_response(child, visited)
        elif isinstance(schema, list):
            for child in schema:
                walk_response(child, visited)

    for path in document["paths"].values():
        for operation in path.values():
            for response in operation.get("responses", {}).values():
                walk_response(response, set())
    assert set(schemas["UserBase"]["properties"]) == PUBLIC_FIELDS
    assert "password" in schemas["UserCreate"]["required"]
    assert "password" not in schemas["UserUpdate"]["properties"]
    assert "password" not in schemas["UserUpdate"]["required"]
