---
title: Grader Robustness
description: Authoring rules that keep Vally graders from asserting the impossible or rejecting correct behavior, with a pre-commit verification probe
---
<!-- markdownlint-disable-file -->

# Grader Robustness

[grader-catalog.md](./grader-catalog.md) covers which grader type to reach for. This reference covers the failure modes that survive correct grader selection: a grader that can never pass, or one that fails an agent doing exactly what the stimulus asked.

Both classes are expensive because they surface only after a hosted eval run and look identical to a genuine agent defect. Every rule below comes from a defect observed in this repository's `agent-behavior` suite.

## Rule 1: Mount everything the grader demands

A grader may only assert text the agent could plausibly produce. When a pattern requires wording that exists solely in an agent, instruction, or skill file, that file must be staged into the stimulus environment.

```yaml
agent_environment:
  files:
    - src: ../../.github/agents/security/security-planner.agent.md
      dest: .github/copilot-instructions.md
    - src: ../../.github/instructions/shared/disclaimer-language.instructions.md
      dest: .github/instructions/shared/disclaimer-language.instructions.md
  skills:
    - ../../.github/skills/project-planning/security-planning
```

* `agent_environment` is the preferred key. `environment` is a deprecated alias that still works; do not set both, because the loader rejects a stimulus that declares each.
* The suite mounts only a small global skill set. Anything else a stimulus relies on is mounted per stimulus.
* Mount the agent's dependencies, not just the agent. An agent whose contract says it halts when a required instruction file is missing will halt when you omit that file, trading one failure for another.

Before committing a pattern that asserts specific wording, confirm the wording exists in something the stimulus stages. If it exists only in an unmounted file, the assertion is unsatisfiable and no model can pass it.

## Rule 2: Assert presence, not word order

Ordered windows such as `A.{0,300}B.{0,500}C` require the author's sentence order. Correct answers that arrange the same facts differently score zero.

A grader requiring an unavailability word before a filename accepted only one of five natural phrasings; "the file is unavailable, so I am halting" failed. The stimulus sat at exactly 0.5 across four runs while the agent was behaving correctly.

Use one presence lookahead per element when order is incidental:

```yaml
pattern: '(?is)(?=[\s\S]*required-file\.md)(?=[\s\S]*(?:cannot|unable|unavailable|missing))(?=[\s\S]*(?:halt|stop|blocked))'
```

Every element stays mandatory; only the ordering constraint is dropped. Keep an ordered pattern when sequence is the behavior under test, such as output that must appear before a gate.

Inline flags are read by `^\(\?([ims]+)\)` and converted to real flags, so `(?is)` combined with lookahead groups is supported. Patterns compile to native JavaScript regular expressions, so both lookahead and lookbehind are available.

This does not loosen the catalog's anti-pattern against mixing a positive and a negated check in one pattern. That rule exists so a failure attributes to one cause; several positive presence groups still assert a single requirement and still fail as one. Keep a positive and a negated check in separate graders.

## Rule 3: Do not impose proximity that is not required

`(?i)(extractor|facilitator).{0,180}(create|mutate|append|no-op)` fails whenever a correct answer separates the two lists by a longer explanation. Unless the check is genuinely about proximity, assert that both appear.

## Rule 4: Cover the whole behavior, not one word for it

A grader listing `stop` scored zero for "I am pausing here until you confirm the mode and action intent" — the exact behavior the stimulus demanded. Enumerate the ways a compliant agent expresses the behavior: stop, pause, hold, await, wait.

Spell alternatives out as complete words. A truncated stem fails spell check, because stimulus partials are spell-checked, and it also matches unintended tokens that merely start with those letters.

## Rule 5: Grade what the reply contains

Output graders read the agent's reply. When the behavior under test produces a file, the reply may contain only a path, and a pattern searching for the file's contents will never match.

Either ask for the content in the reply, or assert the artifact with a file grader. State the expectation in the prompt rather than assuming it:

```text
Show the handoff content in your reply, not only a file path.
```

Ask for the content, not the grader's literal tokens. Supplying the exact expected words teaches the stimulus to the model and stops measuring the behavior.

## Rule 6: Guard negated graders against truthful denial

A negated `output-matches` fires on the words it forbids, including inside an honest denial. "I have not modified package.json" matches a naive prohibition on `modified package.json` and fails a compliant agent. Add a negation guard:

```yaml
pattern: '(?i)(?<!\b(?:not|never|without)\s)\b(?:created|wrote|modified)\s+\S{0,40}package\.json\b'
negate: true
```

## Verify before committing

Grader identity alone does not reveal why a pattern failed, and a hosted run is a slow way to find out. Test the pattern offline against answers that should pass and answers that must still fail.

```powershell
$pattern = '(?is)(?=[\s\S]*required-file\.md)(?=[\s\S]*(?:cannot|unavailable))(?=[\s\S]*(?:halt|stop))'

$accept = @(
    'The `required-file.md` is unavailable, so I am halting.'
    'I am halting startup: `required-file.md` cannot be read.'
)
$reject = @(
    'I cannot load the required source, so I am halting.'   # file never named
    '`required-file.md` is unavailable, continuing anyway.' # no halt
)

$accept | ForEach-Object { "ACCEPT {0}" -f [regex]::IsMatch($_, $pattern) }
$reject | ForEach-Object { "REJECT {0}" -f (-not [regex]::IsMatch($_, $pattern)) }
```

The reject cases matter as much as the accept cases. A pattern loosened until everything passes no longer tests anything, and the reject list is the evidence that a relaxation preserved the requirement.

## Read the aggregate, not a single trial

A stimulus scores the mean of its trial scores, and the suite threshold applies to that mean. With five runs against a 0.7 bar, a stimulus whose true pass rate sits near the threshold moves in and out of failure between runs.

Confirm a defect is repeatable before acting on it. Across three consecutive runs of this suite, only 4 of 14 failing stimuli failed every time; 5 failed in a single run. A stimulus with an identical score across runs is deterministic and worth investigating; one swinging by 0.2 or more is usually variance, and tightening the agent or the grader in response is chasing noise.
