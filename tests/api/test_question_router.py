from __future__ import annotations

from contextlib import contextmanager
import importlib
from pathlib import Path
import sys
import time
import types

import pytest

FastAPI = pytest.importorskip("fastapi").FastAPI
TestClient = pytest.importorskip("fastapi.testclient").TestClient


@pytest.fixture(autouse=True)
def _cleanup_question_router_module():
    yield
    sys.modules.pop("deeptutor.api.routers.question", None)


class _DummyProcessLogEvent:
    def __init__(self, **kwargs) -> None:
        self.data = {"type": "process_log", **kwargs}

    def to_dict(self):
        return self.data


@contextmanager
def _noop_context(*_args, **_kwargs):
    yield


def _package(name: str) -> types.ModuleType:
    module = types.ModuleType(name)
    module.__path__ = []
    return module


def _fake_config_module() -> types.ModuleType:
    """Stand in for ``deeptutor.services.config``, deferring the rest to the real one.

    Only the two names the question router reads at import time are overridden.
    Everything else resolves to the real attribute, because the websocket
    handler lazily imports ``deeptutor.api.routers.auth``, which pulls
    *unrelated* loaders (auth settings, integrations, …) out of this same
    package. Stubbing those one at a time was whack-a-mole, and skipping them
    left the test passing only when an earlier test had already put
    ``deeptutor.api.routers.auth`` in ``sys.modules`` — so the lazy import was
    a cache hit that never reached this stand-in. Green in a full run, red on
    its own.
    """
    real = importlib.import_module("deeptutor.services.config")
    module = types.ModuleType("deeptutor.services.config")
    module.__getattr__ = lambda name: getattr(real, name)  # PEP 562
    module.PROJECT_ROOT = Path.cwd()
    module.load_config_with_main = lambda *_args, **_kwargs: {}
    return module


def _load_question_router_module(monkeypatch: pytest.MonkeyPatch):
    sys.modules.pop("deeptutor.api.routers.question", None)

    fake_agents = _package("deeptutor.agents")
    fake_agents_question = types.ModuleType("deeptutor.agents.question")
    fake_agents_question.AgentCoordinator = object
    fake_agents.question = fake_agents_question
    monkeypatch.setitem(sys.modules, "deeptutor.agents", fake_agents)
    monkeypatch.setitem(sys.modules, "deeptutor.agents.question", fake_agents_question)

    fake_logging = _package("deeptutor.logging")
    fake_logging.ProcessLogEvent = _DummyProcessLogEvent
    fake_logging.bind_log_context = _noop_context
    fake_logging.capture_process_logs = _noop_context
    fake_logging.current_log_context = lambda: {}
    monkeypatch.setitem(sys.modules, "deeptutor.logging", fake_logging)

    monkeypatch.setitem(sys.modules, "deeptutor.services.config", _fake_config_module())

    fake_llm_package = _package("deeptutor.services.llm")
    fake_llm_config = types.ModuleType("deeptutor.services.llm.config")
    fake_llm_config.get_llm_config = lambda: None
    fake_llm_package.config = fake_llm_config
    monkeypatch.setitem(sys.modules, "deeptutor.services.llm", fake_llm_package)
    monkeypatch.setitem(sys.modules, "deeptutor.services.llm.config", fake_llm_config)

    fake_settings_package = _package("deeptutor.services.settings")
    fake_interface_settings = types.ModuleType("deeptutor.services.settings.interface_settings")
    fake_interface_settings.get_ui_language = lambda default="en": default
    # The router asks for the *response* language now that reader-facing output
    # no longer follows the interface locale; the stand-in module has to offer
    # both readers the real one does.
    fake_interface_settings.get_response_language = lambda default="en": default
    fake_settings_package.interface_settings = fake_interface_settings
    monkeypatch.setitem(sys.modules, "deeptutor.services.settings", fake_settings_package)
    monkeypatch.setitem(
        sys.modules,
        "deeptutor.services.settings.interface_settings",
        fake_interface_settings,
    )

    fake_tools = _package("deeptutor.tools")
    fake_tools_question = types.ModuleType("deeptutor.tools.question")

    async def _default_mimic_exam_questions(*_args, **_kwargs):
        return {"success": True}

    fake_tools_question.mimic_exam_questions = _default_mimic_exam_questions
    fake_tools.question = fake_tools_question
    monkeypatch.setitem(sys.modules, "deeptutor.tools", fake_tools)
    monkeypatch.setitem(sys.modules, "deeptutor.tools.question", fake_tools_question)

    return importlib.import_module("deeptutor.api.routers.question")


def _build_app(router_module) -> FastAPI:
    app = FastAPI()
    app.include_router(router_module.router, prefix="/api/v1/question")
    return app


def _install_ws_auth_stubs(monkeypatch: pytest.MonkeyPatch) -> None:
    fake_auth = types.ModuleType("deeptutor.api.routers.auth")
    fake_auth.ws_auth_failed = object()

    async def _ws_require_auth(_websocket):
        return object()

    fake_auth.ws_require_auth = _ws_require_auth
    monkeypatch.setitem(sys.modules, "deeptutor.api.routers.auth", fake_auth)

    fake_multi_user = _package("deeptutor.multi_user")
    fake_context = types.ModuleType("deeptutor.multi_user.context")
    fake_context.reset_current_user = lambda _token: None
    fake_multi_user.context = fake_context
    monkeypatch.setitem(sys.modules, "deeptutor.multi_user", fake_multi_user)
    monkeypatch.setitem(sys.modules, "deeptutor.multi_user.context", fake_context)


def test_mimic_websocket_accepts_config_and_returns_messages(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    question_router_module = _load_question_router_module(monkeypatch)
    _install_ws_auth_stubs(monkeypatch)

    async def _fake_mimic_exam_questions(*_args, **_kwargs):
        return {"success": False, "error": "stub mimic failure"}

    monkeypatch.setattr(question_router_module, "mimic_exam_questions", _fake_mimic_exam_questions)
    # ``MIMIC_OUTPUT_DIR`` was a module-level constant resolved at import time
    # (which froze it to the admin path). It's now a per-call helper so the
    # path follows whichever user is running. Patch the helper instead.
    monkeypatch.setattr(
        question_router_module, "_mimic_output_dir", lambda: tmp_path / "mimic_papers"
    )

    with TestClient(_build_app(question_router_module)) as client:
        with client.websocket_connect("/api/v1/question/mimic") as websocket:
            websocket.send_json(
                {
                    "mode": "parsed",
                    "paper_path": str(tmp_path / "paper"),
                    "kb_name": "demo-kb",
                    "max_questions": 3,
                }
            )
            messages = [websocket.receive_json() for _ in range(3)]

    assert [message["type"] for message in messages] == ["status", "status", "error"]
    assert messages[0]["stage"] == "init"
    assert messages[1]["stage"] == "processing"
    assert messages[2]["content"] == "stub mimic failure"


def test_generate_websocket_adapts_legacy_payload_and_streams_question(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    question_router_module = _load_question_router_module(monkeypatch)
    _install_ws_auth_stubs(monkeypatch)
    calls: list[dict] = []

    class _FakeCoordinator:
        def __init__(self, **_kwargs) -> None:
            self.callback = None

        def set_ws_callback(self, callback) -> None:
            self.callback = callback

        async def generate_from_topic(self, **kwargs):
            calls.append(kwargs)
            assert self.callback is not None
            await self.callback(
                {
                    "type": "content",
                    "metadata": {
                        "call_kind": "quiz_question_emitted",
                        "question_index": 0,
                        "qa_pair": {
                            "question_id": "q_1",
                            "question": "Which graph represents y = x²?",
                            "question_type": "choice",
                            "options": {"A": "A parabola", "B": "A line"},
                            "correct_answer": "A",
                            "explanation": "A quadratic graph is a parabola.",
                            "difficulty": "hard",
                        },
                    },
                }
            )
            return {"success": True, "completed": 1, "failed": 0}

    class _FakePathService:
        def get_question_batch_dir(self, task_id: str) -> Path:
            return tmp_path / task_id

    monkeypatch.setattr(question_router_module, "AgentCoordinator", _FakeCoordinator)
    monkeypatch.setattr(question_router_module, "get_path_service", lambda: _FakePathService())

    with TestClient(_build_app(question_router_module)) as client:
        with client.websocket_connect("/api/v1/question/generate") as websocket:
            task_id_started = time.perf_counter()
            websocket.send_json(
                {
                    "requirement": {
                        "knowledge_point": "Quadratic functions",
                        "preference": "Focus on graph recognition",
                        "difficulty": " Hard ",
                        "question_type": " Choice ",
                    },
                    "kb_name": "demo-kb",
                    "count": "1",
                }
            )
            first_message = websocket.receive_json()
            task_id_elapsed = time.perf_counter() - task_id_started
            messages = [first_message, *[websocket.receive_json() for _ in range(4)]]

    assert calls == [
        {
            "user_topic": (
                "Quadratic functions\n\n"
                "Additional question requirements: Focus on graph recognition"
            ),
            "num_questions": 1,
            "difficulty": "hard",
            "question_types": ["choice"],
            "per_type_counts": {"choice": 1},
        }
    ]
    assert [message["type"] for message in messages] == [
        "task_id",
        "status",
        "question",
        "batch_summary",
        "complete",
    ]
    assert task_id_elapsed < 3.0
    print(f"task_id_elapsed_s={task_id_elapsed:.6f}")
    assert messages[2]["question"]["question_id"] == "q_1"
    assert messages[2]["question"]["question_type"] == "choice"
    assert messages[3] == {
        "type": "batch_summary",
        "requested": 1,
        "completed": 1,
        "failed": 0,
    }


def test_legacy_question_event_marks_pipeline_validation_failure(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    question_router_module = _load_question_router_module(monkeypatch)

    event = question_router_module._legacy_question_event(
        {
            "type": "content",
            "metadata": {
                "call_kind": "quiz_question_emitted",
                "question_index": 2,
                "qa_pair": {"question_id": "q_bad", "question": "invalid"},
                "qa_metadata": {
                    "issues": ["missing_correct_answer"],
                    "error": "quiz_payload_validation_failed",
                },
            },
        }
    )

    assert event["type"] == "question"
    assert event["success"] is False
    assert event["index"] == 2


@pytest.mark.parametrize(
    ("count", "question_type", "expected_error"),
    [
        (0, "choice", "count must be an integer between 1 and 50"),
        ("many", "choice", "count must be an integer between 1 and 50"),
        (51, "choice", "count must be an integer between 1 and 50"),
        (1, "multiple_choice", "Unsupported question_type: multiple_choice"),
        (1, ["choice"], "question_type must be a string"),
    ],
)
def test_generate_websocket_rejects_invalid_count_or_question_type(
    monkeypatch: pytest.MonkeyPatch,
    count,
    question_type,
    expected_error: str,
) -> None:
    question_router_module = _load_question_router_module(monkeypatch)
    _install_ws_auth_stubs(monkeypatch)

    class _UnexpectedCoordinator:
        def __init__(self, **_kwargs) -> None:
            raise AssertionError("Coordinator must not be created for invalid payloads")

    monkeypatch.setattr(question_router_module, "AgentCoordinator", _UnexpectedCoordinator)

    with TestClient(_build_app(question_router_module)) as client:
        with client.websocket_connect("/api/v1/question/generate") as websocket:
            websocket.send_json(
                {
                    "requirement": {
                        "knowledge_point": "Algebra",
                        "question_type": question_type,
                    },
                    "count": count,
                }
            )
            message = websocket.receive_json()

    assert message["type"] == "error"
    assert expected_error in message["content"]
