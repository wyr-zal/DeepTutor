"""PocketBase token validation must keep the immutable record ID."""

from __future__ import annotations

import sys
from types import SimpleNamespace


def test_validate_pb_token_returns_record_id(monkeypatch) -> None:
    from deeptutor.services import pocketbase_client

    record = SimpleNamespace(
        id="pb_user_1",
        email="student@example.com",
        name="Student",
        username="student",
        role="user",
    )

    class FakePocketBase:
        def __init__(self, _url: str):
            self.auth_store = SimpleNamespace(save=lambda _token, _model: None)

        def collection(self, name: str):
            assert name == "users"
            return SimpleNamespace(
                auth_refresh=lambda: SimpleNamespace(record=record),
            )

    monkeypatch.setattr(
        pocketbase_client,
        "_pocketbase_settings",
        lambda: {"url": "https://pocketbase.example", "admin_email": "", "admin_password": ""},
    )
    monkeypatch.setitem(
        sys.modules,
        "pocketbase",
        SimpleNamespace(PocketBase=FakePocketBase),
    )
    pocketbase_client._TOKEN_CACHE.clear()

    payload = pocketbase_client.validate_pb_token("pb-token")

    assert payload == {
        "id": "pb_user_1",
        "username": "student@example.com",
        "role": "user",
    }
