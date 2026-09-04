"""Run the real API against disposable SQLite, without external services."""

import importlib
import sys
from pathlib import Path
from unittest.mock import Mock

import pytest
from fastapi.staticfiles import StaticFiles
from fastapi.testclient import TestClient


@pytest.fixture(scope="session")
def backend(tmp_path_factory):
    directory = tmp_path_factory.mktemp("password-api")
    with pytest.MonkeyPatch.context() as patch:
        patch.syspath_prepend(str(Path(__file__).resolve().parents[1]))
        patch.setenv("DATABASE_URL", f"sqlite:///{directory / 'test.db'}")
        patch.setattr("dotenv.load_dotenv", lambda *args, **kwargs: False)
        patch.setattr("twilio.rest.Client", Mock())
        patch.setattr(
            "fastapi.staticfiles.StaticFiles",
            lambda **kwargs: StaticFiles(directory=directory),
        )
        main = importlib.import_module("app.main")
        sms = Mock()
        sms.send_welcome_sms.return_value = {
            "success": True, "message": "Mock welcome", "brand_name": "Test",
            "language": "tr",
        }
        patch.setattr(main, "twilio_sms_service", sms)
        patch.setattr(main, "email_service", Mock())
        yield main
        main.engine.dispose()
        for name in list(sys.modules):
            if name == "app" or name.startswith("app."):
                sys.modules.pop(name)


@pytest.fixture
def db(backend):
    backend.models.Base.metadata.drop_all(bind=backend.engine)
    backend.models.Base.metadata.create_all(bind=backend.engine)
    with backend.SessionLocal() as session:
        yield session


@pytest.fixture
def client(backend, db):
    with TestClient(backend.app, raise_server_exceptions=False) as client:
        yield client
