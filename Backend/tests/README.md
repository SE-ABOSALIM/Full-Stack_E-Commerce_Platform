# Security regression tests

From the repository root, run:

```sh
python -m pytest Backend/tests -q
flutter test --no-pub
```

The backend tests need `pytest`, `httpx`, `fastapi`, `pydantic`, `sqlalchemy`,
`python-dotenv`, `python-multipart`, and `twilio` in the active Python environment.
They import the real FastAPI application, use a temporary SQLite database, bypass
local environment files, and mock SMS/email services. No production database or
Twilio, email, or payment calls are used. Flutter tests use a mocked HTTP client.

Logging checks inspect only console/log arguments for sensitive values, capture
actual authentication and verification output, and inject sensitive SDK errors.
Twilio/SMTP tests assert that the original destinations, credentials, and message
bodies still reach the mocked SDKs while remaining absent from console output.
Migration SQL/schema output and order codes are not authentication secrets.
