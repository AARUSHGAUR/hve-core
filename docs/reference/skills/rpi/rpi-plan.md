---
title: rpi-plan
description: "Create or resume an evidence-based RPI implementation plan. Use for planning, interrupted critiques, or bounded critique infrastructure recovery."
sidebar_position: 4
author: Microsoft
ms.date: 2026-09-20
ms.topic: reference
keywords:
  - skill
  - rpi
  - rpi-plan
---

<!-- BEGIN AUTO-GENERATED: metadata -->
| Field       | Value                                                                      |
|-------------|----------------------------------------------------------------------------|
| Kind        | skill                                                                      |
| Source      | `.github/skills/rpi/rpi-plan`                                              |
| Invocation  | Invoked directly as `/rpi-plan`, or loaded on demand by referencing agents |
| Interactive | No                                                                         |
<!-- END AUTO-GENERATED: metadata -->

## What it does

<!-- BEGIN AUTO-GENERATED: overview -->
Create or resume an evidence-based RPI implementation plan. Use for planning, interrupted critiques, or bounded critique infrastructure recovery.
<!-- END AUTO-GENERATED: overview -->

## When to use it

Use `rpi-plan` when adequate evidence exists and the work needs a sequenced, verifiable plan before implementation. The skill writes one plan under `.copilot-tracking/plans/` with a stable task ID, `Pxx` phases, and `Pxx-Txx` tasks. The plan leads with an executive summary and a diagrammed Phase Checklist; each task carries `Goals:`, `Requirements:`, `Details:`, `References:`, and `Dependencies:` blocks.

The Phase Checklist opens with **Before** and **After** Mermaid diagrams comparing the evidence-backed starting state with the intended result of all phases. Each phase highlights its changes within the After view, including labeled removal context when needed. Diagrams inherit the renderer's light or dark theme, use readable sans-serif labels, and pair custom highlight fills with explicit contrasting text colors.

Planning owns two internal gates. It activates [rpi-research](rpi-research) only for a demonstrated readiness gap, and runs [rpi-plan-critique](rpi-plan-critique) once the plan is implementation-ready. Substantive terminal assessments are not repeated. The planner can authorize one generic interruption recovery, then two additional infrastructure-only retries with separate consent and evidence checks. Confirmed user direction outranks critique advice.

The planner drafts every phase itself. Before drafting, it looks for skills and subagents whose descriptions say they are used during planning or with `rpi-plan` and follows each description's guidance on when and how to use it; no subagent is required.

One input shapes how the critique is done:

| Input      | Values                       | Effect                                                                               |
|------------|------------------------------|--------------------------------------------------------------------------------------|
| `critique` | `standard` (default), `deep` | How broadly the single critique traces evidence; `deep` requires an explicit request |

Reach for a different asset when:

* Evidence is missing or contradictory. Run [rpi-research](rpi-research) first.
* The plan already exists and is approved. Run [rpi-implement](rpi-implement).
* You only want an independent read of an existing plan. Run [rpi-plan-critique](rpi-plan-critique) directly.

## Example usage

### Resume an interrupted critique

If planning reports `started` but no result survived, resume the same task through `rpi-plan`. It checks recorded evidence, confirms the original critique run has ended, and verifies the saved plan and state. When eligible, it asks for your approval of one recovery for the identified task and candidate, preserving original records and writing a separate recovery result.

A substantive `Complete`, `Partial` or `Blocked` result remains binding even if its file is missing. A saved reservation cannot be replayed. Missing evidence is not a pass: implementation requires an actual Complete assessment, closed blocking findings and explicit residual-risk dispositions.

If both the initial attempt and generic recovery ended in verified infrastructure failures without an assessment, the planner may request up to two additional infrastructure retries. Each needs confirmed ended runs, reconciled saved and late evidence, an identified candidate hash and fresh consent. A network-looking error or absent file alone is insufficient. Every reservation consumes its slot, even if interrupted; changing sessions, candidates or hosts does not reset the task's budget.

For example, two host-recorded connection failures with confirmed completion and no assessment may qualify for another consent request. A substantive critique with blocking findings, an unknown run status, or unresolved assessment fragments does not qualify.

### When infrastructure retries are exhausted

The planner stops automated critique calls and prepares sanitized diagnostics: attempt IDs, candidate hashes, evidence locations, failure and lifecycle status, and the host/network support owner and evidence needed. Repairing the transport does not replenish retry slots.

Exhaustion alone does not authorize another assessment. Active or unknown runs must be reconciled first; substantive results follow their existing finding dispositions. Only confirmed ended infrastructure-only failures with no assessment or unresolved fragments permit a specifically authorized independent human critique.

The human supplies a complete assessment of the saved candidate, including assessor provenance, independence, coverage, verdict and findings. The agent verifies that report against the candidate and all surviving evidence; it cannot write or sign the human's assessment. Approval alone or a mismatched candidate remains blocked. Late results are retained and reconciled, never discarded in favor of a passing report.

### Preserve evidence when resuming

For example, an editor-visible plan that is absent on disk must be saved or synchronized and verified before recovery. Do not delete the reservation to restart. A reconstructed candidate must be identified and approved as current, not represented as the lost original.

Use a consistently updated workflow before resuming: edits to this checkout do not replace instructions already loaded in a conversation or update an installed plugin snapshot. Start a fresh session with the updated repository workflow, or update the installed distribution you use. Choosing this recovery policy or enabling automatic mode does not authorize a specific task's recovery.

### Create a plan

```text
/rpi-plan task=blob-storage research=.copilot-tracking/research/2026-09-04/blob-storage-research.md
```

The skill sends one `RPI Plan` opening with the interpreted goal, starting evidence, and decision state, drafts the phases, adds the Phase Checklist diagrams, and runs the critique once the plan is ready. Its final response summarizes readiness rather than restating the plan:

```text
* Planning execution: Complete; Planning Readiness: Ready
* Critique: standard, verdict Pass; PC-001 (Medium) resolved by adding the retry test to P02-T02 Requirements
* Decisions: managed identity for production confirmed; connection string limited to local development

| Artifact                                                                                                                                             | Description          |
|------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------|
| [.copilot-tracking/plans/2026-09-04/blob-storage-plan.md](.copilot-tracking/plans/2026-09-04/blob-storage-plan.md)                                   | Task-centered plan   |
| [.copilot-tracking/reviews/plans/2026-09-04/blob-storage-plan-critique.md](.copilot-tracking/reviews/plans/2026-09-04/blob-storage-plan-critique.md) | Independent critique |

## Next Steps

Run `/rpi-implement plan=.copilot-tracking/plans/2026-09-04/blob-storage-plan.md`.
```

Inside an automatic `RPI Agent` session the parent continues to Implement without waiting for that command.
