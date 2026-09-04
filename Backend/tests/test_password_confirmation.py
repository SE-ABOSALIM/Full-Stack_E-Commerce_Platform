"""Required confirmation without changing the authenticated password-change rules."""
import pytest

PASSWORD = "Current-password-123!"
NEW_PASSWORD = "Replacement-password-456!"
CONFIRMATION = "Different-confirmation-789!"


@pytest.fixture
def account(backend, db):
    user = backend.models.User(
        name_surname="Confirmation Test", email="confirmation@example.com",
        phone_number="+905320000008", password=backend.hash_password(PASSWORD),
    )
    db.add(user)
    db.commit()
    return user


def test_confirmation_is_required_and_documented(client, db, account, auth_headers):
    headers = auth_headers(account, PASSWORD)
    original = account.password
    response = client.put("/users/me/password", headers=headers, json={
        "current_password": PASSWORD, "new_password": NEW_PASSWORD,
    })
    assert response.status_code == 422
    assert any(error["loc"] == ["body", "new_password_again"] for error in response.json()["detail"])
    assert PASSWORD not in response.text and NEW_PASSWORD not in response.text
    db.refresh(account)
    assert account.password == original
    assert client.get("/users/me", headers=headers).status_code == 200
    schemas = client.get("/openapi.json").json()["components"]["schemas"]
    assert set(schemas["PasswordChange"]["required"]) == {"current_password", "new_password", "new_password_again"}
    assert "password" not in schemas["UserUpdate"]["properties"]
    assert set(schemas["PasswordReset"]["properties"]) == {"phone_number", "verification_code", "new_password"}


@pytest.mark.parametrize("current,status", [(PASSWORD, 400), ("Incorrect-current-123!", 401)])
def test_mismatch_never_changes_password_or_invalidates_token(client, db, account, auth_headers, current, status, capsys):
    headers = auth_headers(account, PASSWORD)
    original = account.password
    response = client.put("/users/me/password", headers=headers, json={
        "current_password": current, "new_password": NEW_PASSWORD, "new_password_again": CONFIRMATION,
    })
    assert response.status_code == status
    if status == 400:
        assert response.json() == {"detail": "New password and confirmation must match"}
    db.refresh(account)
    assert account.password == original
    assert client.get("/users/me", headers=headers).status_code == 200
    auth_headers(account, PASSWORD)
    output = capsys.readouterr()
    for secret in (current, NEW_PASSWORD, CONFIRMATION, original):
        assert secret not in response.text + output.out + output.err


def test_matching_confirmation_preserves_hashing_and_token_invalidation(client, backend, db, account, auth_headers, capsys):
    headers = auth_headers(account, PASSWORD)
    body = {"current_password": PASSWORD, "new_password": NEW_PASSWORD, "new_password_again": NEW_PASSWORD}
    assert client.put("/users/me/password", json=body).status_code == 401
    response = client.put("/users/me/password", headers=headers, json=body)
    assert response.status_code == 200
    assert not set(body).intersection(response.json())
    db.refresh(account)
    assert backend.verify_password(NEW_PASSWORD, account.password)
    assert not backend.verify_password(PASSWORD, account.password)
    assert client.get("/users/me", headers=headers).status_code == 401
    auth_headers(account, NEW_PASSWORD)
    output = capsys.readouterr()
    for secret in (PASSWORD, NEW_PASSWORD, account.password, headers["Authorization"]):
        assert secret not in response.text + output.out + output.err


@pytest.mark.parametrize("confirmation", [[CONFIRMATION], {"secret": CONFIRMATION}, "c0nF!"])
def test_invalid_confirmation_is_redacted(client, account, auth_headers, confirmation):
    response = client.put("/users/me/password", headers=auth_headers(account, PASSWORD), json={
        "current_password": PASSWORD, "new_password": NEW_PASSWORD, "new_password_again": confirmation,
    })
    assert response.status_code == 422
    for secret in (PASSWORD, NEW_PASSWORD, CONFIRMATION, "c0nF!"):
        assert secret not in response.text
