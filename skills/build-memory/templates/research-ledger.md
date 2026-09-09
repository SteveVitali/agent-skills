<!--
  Template: docs/research-ledger.md (BM-SYNTH-01). Written by synthesize-spec mode=plan;
  driven row-by-row by mode=run; frozen at mode=ratify. Same ledger shape as the build:
  the CURRENT STATE block lets `drive-build.sh --skill synthesize-spec` run it. Living until
  ratified, then frozen (a change-log line records the freeze).
-->
# <build> — research & design ledger

- **Status vocabulary:** `open` → `in-progress` → `done` | `blocked-on-operator` | `dropped(reason)`.
  Every row ends `done` with **evidence** — a path into the spec, a source actually fetched, or
  an explicit decision + rationale.
- **Owner vocabulary:** `R` research · `D` design · `A` architecture · `P` product · `S` synthesis.
- **⚑** marks an operator-fixed constraint (do not relitigate).
- **Nothing cited that was not read.**

## CURRENT STATE

```
projectStatus:   NOT_STARTED        # NOT_STARTED | IN_PROGRESS | BLOCKED | PAUSED | DONE
nextUnit:        PLAN               # PLAN, then the next open row id, then SYNTHESIZE, REVIEW, RATIFY
lastCompleted:   (none)
blockedOn:       (nothing)
pauseRequested:  false
brief:           <path to the brief, or (none)>
specOut:         docs/<build>-spec.md
memoryRoot:      docs
autonomy:        (set by the driver)
round:           1
updatedAt:       <date>
```

## 0. Working theses (to be tested, not assumed)
- **T1 — <thesis>.** <one line> (<row refs>)

## A. <stream title>

| id | item | owner | status | evidence |
|---|---|---|---|---|
| A1 | <research/design question> | R | open | |

<!-- add lettered streams B, C, … as the brief demands -->

## O. Spec synthesis & review process

| id | item | owner | status | evidence |
|---|---|---|---|---|
| O1 | draft the spec from the ledger | S | open | |
| O2 | fresh-context adversarial review | S | open | |
| O3 | operator ratification round | S | open | |

## Q. Operator decisions register

| id | question (abridged) | decision | unblocks / new rows |
|---|---|---|---|
| Q-1 | <open question for the operator> | | |

## Change log
- <date> — ledger created by synthesize-spec mode=plan.
