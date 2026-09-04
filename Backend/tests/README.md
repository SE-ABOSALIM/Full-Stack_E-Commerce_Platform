# Password response regression tests

From the repository root, run:

```sh
python -m pytest Backend/tests -q
flutter test test/user_response_compatibility_test.dart --no-pub
```

The backend tests need `pytest`, `httpx`, `fastapi`, `pydantic`, `sqlalchemy`,
`python-dotenv`, `python-multipart`, and `twilio` in the active Python environment.
They import the real FastAPI application, use a temporary SQLite database, bypass
local environment files, and mock SMS/email services. No production database or
Twilio, email, or payment calls are used. Flutter tests use a mocked HTTP client.
