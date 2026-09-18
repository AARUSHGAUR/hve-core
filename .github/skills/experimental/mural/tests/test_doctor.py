# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
"""EV-06 readiness and dispatch-time scope tests."""

from __future__ import annotations

import argparse
import importlib
import importlib.util
from typing import Any

import pytest


def doctor_module() -> Any:
    """Load the planned doctor module after asserting that it exists."""
    assert importlib.util.find_spec("mural._doctor") is not None
    return importlib.import_module("mural._doctor")


@pytest.mark.parametrize(
    ("overrides", "expected"),
    [
        ({"cwd_ok": False}, "wrong_cwd"),
        ({"dependencies_available": False}, "deps_missing"),
        ({"configured": False}, "needs_setup"),
        ({"logged_in": False}, "needs_login"),
        ({"required_scopes": ("murals:write",)}, "needs_scope_upgrade"),
        ({}, "ready"),
    ],
)
def test_doctor_verdict_precedence(overrides: dict[str, Any], expected: str) -> None:
    module = doctor_module()
    inputs = {
        "cwd_ok": True,
        "dependencies_available": True,
        "configured": True,
        "logged_in": True,
        "granted_scopes": ("murals:read",),
        "required_scopes": (),
    }
    inputs.update(overrides)

    result = module.evaluate_readiness(**inputs)

    assert result["verdict"] == expected


def test_parser_registers_doctor_and_repeatable_required_scope(mural_module: Any) -> None:
    args = mural_module._build_parser().parse_args(
        ["doctor", "--require-scope", "murals:read", "--require-scope", "murals:write"]
    )

    assert args.command == "doctor"
    assert args.require_scope == ["murals:read", "murals:write"]
    assert args.func is mural_module._cmd_doctor


def test_main_denies_missing_scope_before_handler(
    mural_module: Any, monkeypatch: pytest.MonkeyPatch
) -> None:
    called: list[str] = []

    def fake_handler(_args: argparse.Namespace) -> int:
        called.append("handler")
        return mural_module.EXIT_SUCCESS

    fake_args = argparse.Namespace(
        log_level="WARNING",
        quiet=False,
        json_output=False,
        profile="default",
        command="widget",
        widget_command="update",
        func=fake_handler,
    )

    class FakeParser:
        def parse_args(self, argv: list[str] | None = None) -> argparse.Namespace:
            return fake_args

    monkeypatch.setattr(mural_module, "_build_parser", FakeParser)
    monkeypatch.setattr(mural_module, "_autoload_credentials", lambda _profile: None)
    monkeypatch.setattr(
        mural_module,
        "_require_scope",
        lambda *args, **kwargs: (_ for _ in ()).throw(
            mural_module.MuralAuthScopeError("murals:write", ("murals:read",))
        ),
    )

    assert mural_module.main([]) == mural_module.EXIT_NOPERM
    assert called == []


def test_command_scope_map_covers_representative_mutations(mural_module: Any) -> None:
    expected = {
        ("room", "create"),
        ("mural", "create"),
        ("template", "instantiate"),
        ("widget", "update"),
        ("widget", "delete"),
        ("tag", "apply"),
        ("area", "probe"),
        ("layout", "grid"),
        ("voting", "session-create"),
    }

    assert expected <= set(mural_module.COMMAND_REQUIRED_SCOPES)