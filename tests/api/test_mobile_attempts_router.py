from __future__ import annotations

from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient

from deeptutor.api.routers import auth as auth_router
from deeptutor.api.routers import mobile as mobile_router
from deeptutor.services.auth import TokenPayload


def _build_app() -> FastAPI:
    app = FastAPI()
    app.include_router(
        mobile_router.router,
        prefix="/api/v1/mobile",
        dependencies=[Depends(auth_router.require_auth)],
    )
    return app


def _isolate_paths(monkeypatch, tmp_path) -> None:
    from deeptutor.multi_user import paths as mu_paths

    admin_root = (tmp_path / "data").resolve()
    monkeypatch.setattr(mu_paths, "PROJECT_ROOT", tmp_path)
    monkeypatch.setattr(mu_paths, "ADMIN_WORKSPACE_ROOT", admin_root)
    monkeypatch.setattr(mu_paths, "USERS_ROOT", admin_root / "users")
    monkeypatch.setattr(mu_paths, "SYSTEM_ROOT", admin_root / "system")
    monkeypatch.setattr(mu_paths, "_path_services", {})


def _attempt(
    attempt_id: str = "attempt-1",
    *,
    user_answer: str = "4",
) -> dict:
    return {
        "id": attempt_id,
        "question": {
            "question_id": "q-1",
            "question": "2 + 2 = ?",
            "question_type": "short_answer",
            "options": {},
            "correct_answer": "4",
            "explanation": "Addition.",
            "difficulty": "easy",
        },
        "user_answer": user_answer,
        "result": {
            "raw_text": "Correct",
            "correctness": "correct",
            "feedback": "Good.",
            "score": 1.0,
            "completed_at": "2026-07-29T00:00:00Z",
        },
        "created_at": "2026-07-29T00:00:00Z",
    }


def test_auth_disabled_mobile_attempts_upsert_in_local_admin_space(
    monkeypatch,
    tmp_path,
) -> None:
    _isolate_paths(monkeypatch, tmp_path)
    monkeypatch.setattr(auth_router, "AUTH_ENABLED", False)

    with TestClient(_build_app()) as client:
        created = client.post("/api/v1/mobile/attempts", json=_attempt())
        updated = client.post(
            "/api/v1/mobile/attempts",
            json=_attempt(user_answer="four"),
        )
        listed = client.get("/api/v1/mobile/attempts")

    assert created.status_code == 201
    assert updated.status_code == 201
    assert listed.status_code == 200
    attempts = listed.json()["attempts"]
    assert len(attempts) == 1
    assert attempts[0]["id"] == "attempt-1"
    assert attempts[0]["user_answer"] == "four"


def test_auth_enabled_mobile_attempts_are_scoped_per_user(
    monkeypatch,
    tmp_path,
) -> None:
    _isolate_paths(monkeypatch, tmp_path)
    monkeypatch.setattr(auth_router, "AUTH_ENABLED", True)

    def decode_token(token: str) -> TokenPayload | None:
        if token == "alice-token":
            return TokenPayload(username="alice", role="user", user_id="u_alice")
        if token == "bob-token":
            return TokenPayload(username="bob", role="user", user_id="u_bob")
        return None

    monkeypatch.setattr(auth_router, "decode_token", decode_token)

    with TestClient(_build_app()) as client:
        created = client.post(
            "/api/v1/mobile/attempts",
            json=_attempt(),
            headers={"Authorization": "Bearer alice-token"},
        )
        bob_list = client.get(
            "/api/v1/mobile/attempts",
            headers={"Authorization": "Bearer bob-token"},
        )
        alice_list = client.get(
            "/api/v1/mobile/attempts",
            headers={"Authorization": "Bearer alice-token"},
        )

    assert created.status_code == 201
    assert bob_list.status_code == 200
    assert bob_list.json()["attempts"] == []
    assert alice_list.status_code == 200
    assert [item["id"] for item in alice_list.json()["attempts"]] == ["attempt-1"]
