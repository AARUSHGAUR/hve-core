---
title: HVE Artifact Tester
description: "Performs contained literal conformance simulation of an HVE artifact and records simulated, emulated, and observed behavior. Dispatched by hve-builder-tester."
sidebar_position: 1
author: Microsoft
ms.date: 2026-08-12
ms.topic: reference
keywords:
  - agent
  - hve-core
  - hve-artifact-tester
---

<!-- BEGIN AUTO-GENERATED: metadata -->
| Field       | Value                                                                    |
|-------------|--------------------------------------------------------------------------|
| Kind        | agent                                                                    |
| Source      | `.github/agents/hve-core/subagents/hve-artifact-tester.agent.md`         |
| Invocation  | Delegated subagent, dispatched by a parent agent (not selected directly) |
| Interactive | No                                                                       |
<!-- END AUTO-GENERATED: metadata -->

## What it does

<!-- BEGIN AUTO-GENERATED: overview -->
Performs contained literal conformance simulation of an HVE artifact and records simulated, emulated, and observed behavior. Dispatched by hve-builder-tester.
<!-- END AUTO-GENERATED: overview -->

## When to use it

The HVE Builder tester lead dispatches this worker for contained, literal conformance simulation of a frozen customization artifact. It distinguishes simulated behavior, emulated actions, and observed evidence. This read-only worker is not a direct user entry point and does not prove native activation or tool reliability.

## Example usage

The lead supplies the frozen artifact, a read-only sandbox, case inputs, selected profile, and model-binding evidence. The worker follows the artifact literally and returns a trace with coverage, deviations, and fidelity limits for the lead to persist. It does not improve the artifact or write the sandbox, and stops before an action requiring secrets or an out-of-sandbox write.
