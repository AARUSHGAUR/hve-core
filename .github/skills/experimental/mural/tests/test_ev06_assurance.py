# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
"""EV-06 finding matrix and cross-cutting assurance tests."""

from __future__ import annotations

import json
import pathlib
from typing import Any

import pytest


FIXTURE = pathlib.Path(__file__).parent / "fixtures" / "assurance" / "ev06-scenarios.json"
EXPECTED_FINDINGS = {
    "RAI-P08-G02-A081-C01",
    "RAI-P08-G02-A082-C01",
    "RAI-P08-G02-A083-C01",
    "RAI-P08-G02-A084-C01",
    "RAI-P08-G02-A085-C01",
    "RAI-P08-G02-A086-C01",
    "RAI-P08-G02-A087-C01",
    "RAI-P08-G04-A191-C01",
}
FIVE_FAMILIES = {
    "NORMAL",
    "AUTHORITY_CONSENT",
    "FAIL_CLOSED",
    "EXTERNAL_WRITE",
    "RECOVERY_RESUME",
}


def load_manifest() -> dict[str, Any]:
    return json.loads(FIXTURE.read_text(encoding="utf-8"))


def test_manifest_covers_all_findings_and_required_dimensions() -> None:
    manifest = load_manifest()
    rows = {row["finding_id"]: row for row in manifest["required_findings"]}

    assert manifest["fidelity"] == "LOCAL_TEST_DOUBLE"
    assert set(rows) == EXPECTED_FINDINGS
    for finding_id, row in rows.items():
        expected = {"NORMAL", "ROUTING"} if finding_id.endswith("A087-C01") else FIVE_FAMILIES
        assert set(row["families"]) == expected
        assert row["assertions"]
        assert row["baseline"] in {"ABSENT", "CONTRADICTED"}
    assert rows["RAI-P08-G02-A085-C01"]["callers"] == [
        "dt-coach",
        "rai-planner",
        "ux-ui-designer",
    ]
    assert len(rows["RAI-P08-G02-A087-C01"]["destinations"]) == 7
    assert "azure-blob-sas-upload" in rows["RAI-P08-G04-A191-C01"]["surfaces"]


def test_human_widget_update_is_protected_by_default(
    mural_module: Any, monkeypatch: pytest.MonkeyPatch
) -> None:
    protected: list[tuple[str, str]] = []
    transport: list[str] = []
    monkeypatch.setattr(
        mural_module,
        "_assert_widget_has_author_tag",
        lambda mural_id, widget_id: protected.append((mural_id, widget_id)),
    )
    monkeypatch.setattr(
        mural_module,
        "_patch_widget_or_disambiguate_404",
        lambda *args, **kwargs: transport.append("patch"),
    )

    mural_module._op_widget_update(
        {
            "mural": "workspace1.mural-abc123",
            "widget": "widget-1",
            "body": {"hyperlink": "https://example.invalid/record"},
            "force_human": False,
        }
    )

    assert protected == [("workspace1.mural-abc123", "widget-1")]
    assert transport == ["patch"]


def test_redaction_removes_credential_markers_but_preserves_human_record_text(
    mural_module: Any,
) -> None:
    diagnostic = (
        'access_token="SYNTHETIC_ACCESS" refresh_token=SYNTHETIC_REFRESH '
        "Authorization: Bearer SYNTHETIC_BEARER "
        "https://acct.blob.core.windows.net/c/b?sig=SYNTHETIC_SAS"
    )
    human_text = "The team reports that password rotation is difficult."

    redacted = mural_module._redact(diagnostic)

    for marker in ("SYNTHETIC_ACCESS", "SYNTHETIC_REFRESH", "SYNTHETIC_BEARER", "SYNTHETIC_SAS"):
        assert marker not in redacted
    assert mural_module._redact(human_text) == human_text