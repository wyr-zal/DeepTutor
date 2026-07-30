"""Context cleanup regressions for the AI judge WebSocket."""

from __future__ import annotations

import asyncio

from fastapi import WebSocketDisconnect


class _DisconnectingWebSocket:
    accepted = False

    async def accept(self) -> None:
        self.accepted = True

    async def receive_json(self):
        raise WebSocketDisconnect()


class _DisconnectingOnSendWebSocket:
    async def accept(self) -> None:
        pass

    async def receive_json(self):
        return {
            "question": "2 + 2 = ?",
            "question_type": "short_answer",
            "correct_answer": "4",
            "user_answer": "4",
            "language": "zh",
        }

    async def send_json(self, _payload) -> None:
        raise WebSocketDisconnect()

    async def close(self) -> None:
        pass


def test_initial_disconnect_resets_authenticated_user_context(monkeypatch) -> None:
    from deeptutor.api.routers import auth as auth_router
    from deeptutor.api.routers.quiz_judge import websocket_quiz_judge
    from deeptutor.multi_user import context as user_context

    context_token = object()

    async def fake_ws_require_auth(_websocket):
        return context_token

    resets: list[object] = []
    monkeypatch.setattr(auth_router, "ws_require_auth", fake_ws_require_auth)
    monkeypatch.setattr(user_context, "reset_current_user", resets.append)
    websocket = _DisconnectingWebSocket()

    asyncio.run(websocket_quiz_judge(websocket))

    assert websocket.accepted is True
    assert resets == [context_token]


def test_disconnect_before_started_does_not_begin_llm_stream(monkeypatch) -> None:
    from deeptutor.api.routers import auth as auth_router
    from deeptutor.api.routers import quiz_judge

    async def fake_ws_require_auth(_websocket):
        return None

    async def unexpected_llm_stream(**_kwargs):
        raise AssertionError("LLM stream must not start after the client disconnects")
        yield  # pragma: no cover

    monkeypatch.setattr(auth_router, "ws_require_auth", fake_ws_require_auth)
    monkeypatch.setattr(quiz_judge, "llm_stream", unexpected_llm_stream)

    asyncio.run(quiz_judge.websocket_quiz_judge(_DisconnectingOnSendWebSocket()))
