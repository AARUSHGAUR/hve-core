# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
"""EV-06 destination registry, dispatch, and hydration tests."""

from __future__ import annotations

import importlib
import importlib.util
from dataclasses import dataclass
from typing import Any

import pytest


def destinations_module() -> Any:
    """Load the planned destination module after asserting that it exists."""
    assert importlib.util.find_spec("mural._destinations") is not None
    return importlib.import_module("mural._destinations")


@dataclass
class RecordingAdapter:
    result: Any
    calls: list[Any]

    def dispatch(self, request: Any) -> Any:
        self.calls.append(request)
        return self.result


def test_loads_authoritative_registry_and_all_destinations() -> None:
    module = destinations_module()

    registry = module.load_destination_registry()

    assert set(registry.entries) == {
        "backlog-item",
        "instructions-file",
        "adr",
        "living-document",
        "powerpoint-deck",
        "next-workshop-seed",
        "unactioned",
    }


@pytest.mark.parametrize(
    "text",
    [
        "destinations: not-a-list\n",
        "destinations:\n  - id: duplicate\n    intent: action\n    target: safe/**\n    loop_closure: ok\n    v1_retro: true\n  - id: duplicate\n    intent: action\n    target: safe/**\n    loop_closure: ok\n    v1_retro: true\n",
        "destinations:\n  - id: unsafe\n    intent: action\n    target: ../escape/**\n    loop_closure: no\n    v1_retro: false\n",
        "destinations:\n  - id: extra\n    intent: action\n    target: safe/**\n    loop_closure: ok\n    v1_retro: false\n    unexpected: value\n",
    ],
)
def test_registry_rejects_malformed_duplicate_unsafe_and_unknown_fields(
    tmp_path: Any, text: str
) -> None:
    module = destinations_module()
    path = tmp_path / "registry.yml"
    path.write_text(text, encoding="utf-8")

    with pytest.raises(ValueError):
        module.load_destination_registry(base_path=path)


def test_dispatch_requires_explicit_destination_and_action_intent() -> None:
    module = destinations_module()
    registry = module.load_destination_registry()
    adapter = RecordingAdapter(
        result=module.DispatchResult(status="created", external_id="synthetic-1"),
        calls=[],
    )

    result = module.dispatch_destination(
        module.DispatchRequest(destination=None, action_intent=None, payload={}),
        registry,
        {"backlog-item": adapter},
    )

    assert result.status == "no-dispatch"
    assert adapter.calls == []


def test_dispatch_projects_lifecycle_only_after_adapter_results() -> None:
    module = destinations_module()
    registry = module.load_destination_registry()
    adapter = RecordingAdapter(
        result=module.DispatchResult(
            status="created", external_id="synthetic-1", loop_closed=True
        ),
        calls=[],
    )
    request = module.DispatchRequest(
        destination="backlog-item",
        action_intent="create",
        payload={"title": "Synthetic action"},
        idempotency_key="ev06-synthetic-1",
    )

    result = module.dispatch_destination(request, registry, {"backlog-item": adapter})

    assert result.lifecycle == ("lifecycle:committed", "lifecycle:loop-closed")
    assert adapter.calls == [request]


def test_writeback_rejects_text_and_accepts_stable_channels() -> None:
    module = destinations_module()

    assert module.validate_writeback_patch(
        {"tags": ["destination:adr"], "hyperlink": "https://example.invalid/a", "parentId": "area-1"}
    ) == {"tags": ["destination:adr"], "hyperlink": "https://example.invalid/a", "parentId": "area-1"}
    with pytest.raises(ValueError):
        module.validate_writeback_patch({"text": "do not overwrite human text"})


def test_hydration_preserves_source_text_and_projects_destination_fields() -> None:
    module = destinations_module()
    context = {
        "widget": {
            "id": "widget-1",
            "text": "Password rotation is difficult for the team",
            "htmlText": "<p>Password rotation is difficult for the team</p>",
            "parentId": "area-1",
            "tags": ["tag-ai", "tag-destination"],
            "hyperlink": "https://example.invalid/source",
            "title": "[dt:method=3 section=affinity run=RUN1] Card",
        },
        "area_chain": [{"id": "area-1", "title": "Actions"}],
        "siblings": [{"id": "widget-2", "text": "Neighbor"}],
    }

    record = module.hydrate_destination_record(
        context,
        room={"id": "room-1", "name": "Synthetic Room"},
        mural={"id": "mural-1", "title": "Synthetic Mural"},
        workspace={"id": "workspace-1", "name": "Synthetic Workspace"},
        tag_text_by_id={"tag-ai": "authored-by-ai", "tag-destination": "destination:adr"},
        widget_url="https://example.invalid/widget-1",
    )
    projection = module.project_destination_record(record, "adr")

    assert record["text"] == context["widget"]["text"]
    assert record["htmlText"] == context["widget"]["htmlText"]
    assert record["authored_by_ai"] is True
    assert projection["source_ref"] == "https://example.invalid/widget-1"
    assert projection["spatial_neighbors"][0]["id"] == "widget-2"