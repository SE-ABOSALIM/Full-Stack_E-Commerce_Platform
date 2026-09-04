"""Check log arguments rather than banning legitimate credential handling."""

import ast
import importlib
import re
from datetime import datetime, timedelta
from email import message_from_string
from pathlib import Path
from unittest.mock import Mock

import pytest


ROOT = Path(__file__).resolve().parents[2]
PASSWORD = "Private-password-789!"
CODE = "918273"
PHONE = "+90 532 765 43 21"
EMAIL = "private-buyer@example.com"
SECRETS = [PASSWORD, CODE, PHONE, EMAIL, "private-salted:password-hash",
           "private-auth-token", "private-api-key", "private-api-secret",
           "4111111111111111", "private-cvc", "private-identity-number"]
SECRET_ERROR = " ".join(SECRETS)
SENSITIVE_NAME = re.compile(
    r"password|verification_?code|\botp\b|\bcode\b|token|api_?key|secret|"
    r"card_?number|cvv|cvc|identity_?number|authorization|bearer|"
    r"\bemail\b|\bphone\b|phone_?number|formatted_phone|old_phone|new_phone",
    re.IGNORECASE,
)
RAW_OBJECT = re.compile(
    r"^(?:user|db_user|updatedUser|card|map|data|requestBody|orderData|order_data|"
    r"userOrders|allOrders|orders|userSpecificOrders|reviewsWithUserInfo|statistics|"
    r"Session\.currentUser)!?(?:\.(?:dict|model_dump|toMap)\(\))?$"
)


def unsafe_expression(expression):
    if expression.endswith(".runtimeType") or expression.startswith("type("):
        return False
    return bool(
        SENSITIVE_NAME.search(expression)
        or RAW_OBJECT.fullmatch(expression)
        or re.search(r"\.body\b|\[['\"]message['\"]\]|__dict__", expression)
        or expression in {"e", "str(e)", "error", "exception", "stackTrace"}
    )


def test_backend_log_arguments_exclude_sensitive_values():
    violations = []
    for path in (ROOT / "Backend/app").rglob("*.py"):
        for call in ast.walk(ast.parse(path.read_text(encoding="utf-8"))):
            if not isinstance(call, ast.Call):
                continue
            name = ast.unparse(call.func)
            if name != "print" and not re.search(r"(?:logger|logging|traceback)\.", name):
                continue
            for argument in call.args:
                expressions = (
                    [part.value for part in ast.walk(argument) if isinstance(part, ast.FormattedValue)]
                    if isinstance(argument, ast.JoinedStr) else [argument]
                )
                for expression in expressions:
                    if not isinstance(expression, ast.Constant) and unsafe_expression(ast.unparse(expression)):
                        violations.append(f"{path.relative_to(ROOT)}:{call.lineno}")
    assert not violations, "Sensitive log arguments: " + ", ".join(violations)


def test_flutter_log_arguments_exclude_sensitive_values():
    violations = []
    for path in (ROOT / "lib").rglob("*.dart"):
        source = path.read_text(encoding="utf-8")
        for call in re.finditer(r"\b(?:print|debugPrint|developer\.log)\s*\((.*?)\);", source, re.DOTALL):
            arguments = call.group(1)
            expressions = [braced or simple for braced, simple in re.findall(
                r"\$(?:\{([^}]+)\}|([A-Za-z_]\w*))", arguments
            )]
            # Also catch direct print(secret) / debugPrint(response.body) calls.
            if not arguments.lstrip().startswith(("'", '"')):
                expressions.append(arguments.strip())
            if any(unsafe_expression(expression) for expression in expressions):
                violations.append(f"{path.relative_to(ROOT)}:{source.count(chr(10), 0, call.start()) + 1}")
    assert not violations, "Sensitive log arguments: " + ", ".join(violations)


def assert_safe_output(capsys, *extra):
    output = capsys.readouterr()
    text = output.out + output.err
    for secret in [*SECRETS, *extra]:
        assert secret not in text
    return text


def test_registration_login_and_password_update_logs(client, backend, db, capsys, auth_headers):
    db.add(backend.models.PhoneVerification(
        phone_number=PHONE, verification_code=CODE, is_verified="verified",
        attempts=0, created_at=datetime.now(), expires_at=datetime.now() + timedelta(minutes=5),
    ))
    db.commit()
    payload = {"name_surname": "Private Buyer", "password": PASSWORD,
               "email": EMAIL, "phone_number": PHONE}
    response = client.post("/users", json=payload)
    assert response.status_code == 200
    user = db.query(backend.models.User).one()
    original_hash = user.password
    for password, status in [(PASSWORD, 200), ("incorrect-password", 401)]:
        assert client.post("/users/login", data={"email": EMAIL, "password": password}).status_code == status
    new_password = "Replacement-password-789!"
    assert client.put("/users/me/password", headers=auth_headers(user, PASSWORD), json={"current_password": PASSWORD, "new_password": new_password, "new_password_again": new_password}).status_code == 200
    db.refresh(user)
    assert backend.verify_password(new_password, user.password)
    assert_safe_output(capsys, original_hash, user.password, new_password, "Private Buyer")


@pytest.mark.parametrize("seller", [False, True])
def test_phone_verification_logs_and_requests(client, backend, db, monkeypatch, capsys, seller):
    monkeypatch.setattr(backend, "generate_verification_code", lambda: CODE)
    backend.twilio_sms_service.send_verification_sms.return_value = {
        "success": True, "message": SECRET_ERROR, "brand_name": "Test", "language": "tr",
    }
    send_path = "/send-seller-verification-code" if seller else "/send-verification-code"
    verify_path = "/verify-seller-phone" if seller else "/verify-phone"
    response = client.post(send_path, json={"phone_number": PHONE, "language": "tr"})
    assert response.status_code == 200, response.text
    assert response.json()["success"] is True
    backend.twilio_sms_service.send_verification_sms.assert_called_with(PHONE, CODE, "tr")
    response = client.post(verify_path, json={"phone_number": PHONE, "verification_code": CODE})
    assert response.status_code == 200
    assert response.json()["success"] is True
    model = backend.models.PhoneVerificationSeller if seller else backend.models.PhoneVerification
    assert db.query(model).one().is_verified == "verified"
    assert_safe_output(capsys)


@pytest.mark.parametrize("seller", [False, True])
def test_email_verification_logs_and_requests(client, backend, db, monkeypatch, capsys, seller, auth_headers):
    monkeypatch.setattr(backend, "generate_verification_code", lambda: CODE)
    if seller:
        record = backend.models.Seller(name="Private Seller", email=EMAIL, phone=PHONE,
                                       password=backend.hash_password(PASSWORD), store_name="Test Store")
    else:
        record = backend.models.User(name_surname="Private Buyer", email=EMAIL,
                                     phone_number=PHONE, password=backend.hash_password(PASSWORD))
    db.add(record)
    db.commit()
    backend.email_service.send_verification_email.return_value = {"success": True, "message": "Sent"}
    send_path = "/send-seller-email-verification-code" if seller else "/send-email-verification-code"
    verify_path = "/verify-seller-email" if seller else "/verify-email"
    headers = auth_headers(record, PASSWORD, "seller" if seller else "user")
    response = client.post(send_path, headers=headers, json={"email": EMAIL, "language": "tr"})
    assert response.status_code == 200, response.text
    backend.email_service.send_verification_email.assert_called_with(EMAIL, CODE, "tr")
    response = client.post(verify_path, headers=headers, json={"email": EMAIL, "verification_code": CODE})
    assert response.status_code == 200
    db.refresh(record)
    assert record.email_verified == "verified"
    assert_safe_output(capsys, record.password)


@pytest.mark.parametrize("failure", [False, True])
def test_twilio_receives_sms_body_but_logs_do_not(backend, monkeypatch, capsys, failure):
    module = importlib.import_module("app.services.twilio_sms_service")
    sdk = Mock()
    sdk.messages.create.return_value = Mock(sid="SM-test", status="queued", price="0.01")
    if failure:
        sdk.messages.create.side_effect = RuntimeError(SECRET_ERROR)
    factory = Mock(return_value=sdk)
    monkeypatch.setattr(module, "Client", factory)
    monkeypatch.setenv("TWILIO_ACCOUNT_SID", "test-account")
    monkeypatch.setenv("TWILIO_AUTH_TOKEN", SECRETS[5])
    monkeypatch.setenv("TWILIO_FROM_NUMBER", "+90 532 111 22 33")
    service = module.TwilioSMS()
    body = f"Your verification code is {CODE}. {PASSWORD}"
    result = service.send_sms(PHONE, body, "tr")
    factory.assert_called_once_with("test-account", SECRETS[5])
    sdk.messages.create.assert_called_once_with(body=body, from_="+90 532 111 22 33", to=PHONE)
    assert result["success"] is not failure
    output = assert_safe_output(capsys, body, "+90 532 111 22 33")
    assert "SMS" in output
    if failure:
        assert "RuntimeError" in output


@pytest.mark.parametrize("mode", ["send", "failure", "unconfigured"])
def test_smtp_receives_code_but_logs_do_not(backend, monkeypatch, capsys, mode):
    module = importlib.import_module("app.services.email_service")
    smtp = Mock()
    factory = Mock(return_value=smtp)
    monkeypatch.setattr(module.smtplib, "SMTP", factory)
    monkeypatch.setenv("SENDER_EMAIL", "sender@example.com")
    monkeypatch.setenv("SENDER_PASSWORD", "smtp-private-secret")
    service = module.EmailService()
    if mode == "unconfigured":
        service.sender_password = "your-app-password"
    if mode == "failure":
        smtp.sendmail.side_effect = RuntimeError(SECRET_ERROR)
    result = service.send_verification_email(EMAIL, CODE, "tr")
    assert result["success"] is (mode != "failure")
    if mode == "unconfigured":
        factory.assert_not_called()
    else:
        smtp.starttls.assert_called_once_with()
        smtp.login.assert_called_once_with("sender@example.com", "smtp-private-secret")
        sender, recipient, content = smtp.sendmail.call_args.args
        assert (sender, recipient) == ("sender@example.com", EMAIL)
        message = message_from_string(content)
        html = message.get_payload()[0].get_payload(decode=True).decode("utf-8")
        assert CODE in html
    output = assert_safe_output(capsys, "sender@example.com", "smtp-private-secret")
    assert "Email" in output
    if mode == "failure":
        assert "RuntimeError" in output
