"""Mobile-client support endpoints."""

from __future__ import annotations

from datetime import datetime, timezone
import json
import os
from pathlib import Path
from threading import Lock
from typing import Any

from fastapi import APIRouter, Query, status
from pydantic import BaseModel, ConfigDict, Field, field_validator

from deeptutor.services.path_service import get_path_service

router = APIRouter()

_MAX_ATTEMPTS = 500
_ATTEMPTS_LOCK = Lock()


class MobileQuizAttempt(BaseModel):
    """Stored mobile answer attempt.

    The JSON shape intentionally mirrors ``QuizAttempt.toJson()`` in the
    Flutter client so the API stays a thin sync layer.
    """

    model_config = ConfigDict(extra="forbid")

    id: str = Field(..., min_length=1, max_length=256)
    question: dict[str, Any]
    user_answer: str = ""
    result: dict[str, Any]
    created_at: str = ""

    @field_validator("id", "created_at", "user_answer", mode="before")
    @classmethod
    def _coerce_string(cls, value: Any) -> str:
        return "" if value is None else str(value)

    @field_validator("question", "result")
    @classmethod
    def _require_object(cls, value: dict[str, Any]) -> dict[str, Any]:
        if not value:
            raise ValueError("must be a non-empty object")
        return value


class MobileAttemptsResponse(BaseModel):
    attempts: list[MobileQuizAttempt]


class MobileAttemptSaveResponse(BaseModel):
    saved: bool
    attempt: MobileQuizAttempt


def _attempts_file() -> Path:
    root = get_path_service().get_workspace_dir() / "mobile"
    root.mkdir(parents=True, exist_ok=True)
    return root / "attempts.json"


def _parse_created_at(value: str) -> datetime:
    try:
        normalized = value.replace("Z", "+00:00")
        parsed = datetime.fromisoformat(normalized)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)
    except Exception:
        return datetime.fromtimestamp(0, tz=timezone.utc)


def _read_attempts() -> list[MobileQuizAttempt]:
    path = _attempts_file()
    if not path.exists():
        return []
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return []
    if not isinstance(raw, list):
        return []

    attempts: list[MobileQuizAttempt] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        try:
            attempts.append(MobileQuizAttempt.model_validate(item))
        except Exception:
            continue
    attempts.sort(key=lambda attempt: _parse_created_at(attempt.created_at), reverse=True)
    return attempts


def _write_attempts(attempts: list[MobileQuizAttempt]) -> None:
    path = _attempts_file()
    payload = [
        attempt.model_dump(mode="json")
        for attempt in sorted(
            attempts,
            key=lambda item: _parse_created_at(item.created_at),
            reverse=True,
        )[:_MAX_ATTEMPTS]
    ]
    temporary = path.with_suffix(".json.tmp")
    temporary.write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    os.replace(temporary, path)


@router.get("/attempts", response_model=MobileAttemptsResponse)
async def list_mobile_attempts(
    limit: int = Query(default=200, ge=1, le=_MAX_ATTEMPTS),
) -> MobileAttemptsResponse:
    with _ATTEMPTS_LOCK:
        attempts = _read_attempts()[:limit]
    return MobileAttemptsResponse(attempts=attempts)


@router.post(
    "/attempts",
    response_model=MobileAttemptSaveResponse,
    status_code=status.HTTP_201_CREATED,
)
async def save_mobile_attempt(payload: MobileQuizAttempt) -> MobileAttemptSaveResponse:
    with _ATTEMPTS_LOCK:
        attempts_by_id = {attempt.id: attempt for attempt in _read_attempts()}
        attempts_by_id[payload.id] = payload
        _write_attempts(list(attempts_by_id.values()))
    return MobileAttemptSaveResponse(saved=True, attempt=payload)
