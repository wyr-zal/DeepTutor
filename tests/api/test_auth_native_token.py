"""Contract tests for the native-client Bearer token endpoint."""

from __future__ import annotations

from fastapi import FastAPI
from fastapi.testclient import TestClient
import pytest

from deeptutor.api.routers import auth as auth_router
from deeptutor.services.auth import TokenPayload


@pytest.fixture
def client() -> TestClient:
    app = FastAPI()
    app.include_router(auth_router.router, prefix="/api/v1/auth")
    return TestClient(app)


def test_token_returns_native_bearer_contract_without_cookie(monkeypatch, client) -> None:
    payload = TokenPayload(username="alice", role="admin", user_id="u_alice")
    monkeypatch.setattr(auth_router, "AUTH_ENABLED", True)
    monkeypatch.setattr(auth_router, "POCKETBASE_ENABLED", False)
    monkeypatch.setattr(auth_router, "authenticate", lambda username, password: payload)

    create_token_calls: list[tuple[str, str, str]] = []

    def fake_create_token(username: str, role: str, user_id: str) -> str:
        create_token_calls.append((username, role, user_id))
        return "local-jwt"

    monkeypatch.setattr(auth_router, "create_token", fake_create_token)
    monkeypatch.setattr(auth_router, "_COOKIE_MAX_AGE", 7200)

    response = client.post(
        "/api/v1/auth/token",
        json={"username": "alice", "password": "correct-password"},
    )

    assert response.status_code == 200
    assert response.json() == {
        "access_token": "local-jwt",
        "token_type": "bearer",
        "expires_in": 7200,
        "user": {
            "user_id": "u_alice",
            "username": "alice",
            "role": "admin",
            "is_admin": True,
        },
    }
    assert create_token_calls == [("alice", "admin", "u_alice")]
    assert "set-cookie" not in response.headers
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["pragma"] == "no-cache"


def test_existing_login_cookie_contract_is_unchanged(monkeypatch, client) -> None:
    payload = TokenPayload(username="alice", role="user", user_id="u_alice")
    monkeypatch.setattr(auth_router, "AUTH_ENABLED", True)
    monkeypatch.setattr(auth_router, "POCKETBASE_ENABLED", False)
    monkeypatch.setattr(auth_router, "authenticate", lambda username, password: payload)
    monkeypatch.setattr(auth_router, "create_token", lambda username, role, user_id: "cookie-jwt")

    response = client.post(
        "/api/v1/auth/login",
        json={"username": "alice", "password": "correct-password"},
    )

    assert response.status_code == 200
    assert response.json() == {
        "ok": True,
        "user_id": "u_alice",
        "username": "alice",
        "role": "user",
        "is_admin": False,
    }
    assert response.cookies[auth_router._COOKIE_NAME] == "cookie-jwt"
    assert "access_token" not in response.text


def test_token_rejects_incorrect_password(monkeypatch, client) -> None:
    monkeypatch.setattr(auth_router, "AUTH_ENABLED", True)
    monkeypatch.setattr(auth_router, "POCKETBASE_ENABLED", False)
    monkeypatch.setattr(auth_router, "authenticate", lambda username, password: None)

    response = client.post(
        "/api/v1/auth/token",
        json={"username": "alice", "password": "wrong-password"},
    )

    assert response.status_code == 401
    assert response.json() == {"detail": "Incorrect username or password"}
    assert response.headers["www-authenticate"] == "Bearer"


def test_token_has_explicit_disabled_semantics(monkeypatch, client) -> None:
    monkeypatch.setattr(auth_router, "AUTH_ENABLED", False)
    monkeypatch.setattr(
        auth_router,
        "authenticate",
        lambda username, password: pytest.fail("disabled mode must not authenticate credentials"),
    )

    response = client.post(
        "/api/v1/auth/token",
        json={"username": "local", "password": "unused"},
    )

    assert response.status_code == 409
    assert response.json() == {"detail": "Authentication is disabled; no access token is required."}
    assert "access_token" not in response.text


def test_token_returns_pocketbase_token_and_user(monkeypatch, client) -> None:
    payload = TokenPayload(
        username="student@example.com",
        role="user",
        user_id="pb_user_1",
    )
    monkeypatch.setattr(auth_router, "AUTH_ENABLED", True)
    monkeypatch.setattr(auth_router, "POCKETBASE_ENABLED", True)
    monkeypatch.setattr(
        auth_router,
        "authenticate_pb",
        lambda username, password: (payload, "pocketbase-jwt"),
    )
    monkeypatch.setattr(
        auth_router,
        "create_token",
        lambda username, role, user_id: pytest.fail(
            "PocketBase tokens must be returned verbatim, not re-signed locally"
        ),
    )
    monkeypatch.setattr(auth_router, "_COOKIE_MAX_AGE", 3600)

    response = client.post(
        "/api/v1/auth/token",
        json={"username": "student@example.com", "password": "correct-password"},
    )

    assert response.status_code == 200
    assert response.json() == {
        "access_token": "pocketbase-jwt",
        "token_type": "bearer",
        "expires_in": 3600,
        "user": {
            "user_id": "pb_user_1",
            "username": "student@example.com",
            "role": "user",
            "is_admin": False,
        },
    }
    assert "set-cookie" not in response.headers
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["pragma"] == "no-cache"


def test_token_rejects_incorrect_pocketbase_password(monkeypatch, client) -> None:
    monkeypatch.setattr(auth_router, "AUTH_ENABLED", True)
    monkeypatch.setattr(auth_router, "POCKETBASE_ENABLED", True)
    monkeypatch.setattr(auth_router, "authenticate_pb", lambda username, password: None)

    response = client.post(
        "/api/v1/auth/token",
        json={"username": "student@example.com", "password": "wrong-password"},
    )

    assert response.status_code == 401
    assert response.json() == {"detail": "Incorrect email or password"}
    assert response.headers["www-authenticate"] == "Bearer"
