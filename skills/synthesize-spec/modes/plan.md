# synthesize-spec · mode: plan (BM-SYNTH-01)

Seed `docs/research-ledger.md` from the brief — the durable work list the rest of the skill executes. This is
the upstream analogue of `decompose-spec`'s Phase 5 seed.

## Read first
The `brief`. Extract the founding questions, the fixed constraints (mark them `⚑`), and the shape of the answer
(product / design / architecture / data / ops streams). If `outline_trace` is on, also extract the brief's
outline obligations as `OL-*` ids.

## Write `docs/research-ledger.md`
From `skills/build-memory/templates/research-ledger.md`, with:

- **Header** stating the vocabularies verbatim:
  - status `open → in-progress → done | blocked-on-operator | dropped(reason)`;
  - owner `R` research · `D` design · `A` architecture · `P` product · `S` synthesis;
  - `⚑` marks an operator-fixed constraint (not up for redesign);
  - the standing rule **"nothing cited that was not read."**
- **`## 0. Working theses`** — the load-bearing hypotheses the research will test, not assume (bulleted `T1…Tn`,
  each ending with the row ids that bear on it).
- **Lettered streams** (`## A.`, `## B.`, …), each a table `| id | item | owner | status | evidence |`. One row =
  one unit of work a fresh context will execute in `run`. Order roughly by dependency (ground truth before
  design that depends on it).
- **`## O. Spec synthesis & review process`** — rows `O1…On` planning the synthesize/review/ratify units and the
  `rounds` you intend.
- **`## Q. Operator decisions register`** — a table `| id | question (abridged) | decision | unblocks / new rows |`,
  seeded with the open questions the brief leaves unresolved (decision cells empty until `ratify`).
- **`## Change log`** — one dated line per round/edit.
- **A `CURRENT STATE` fenced block** so `drive-build.sh --skill synthesize-spec` can drive it:

```
projectStatus:   IN_PROGRESS      # NOT_STARTED | IN_PROGRESS | BLOCKED | PAUSED | DONE
nextUnit:        <first open row id, e.g. A1>
lastCompleted:   (none)
blockedOn:       (nothing)
pauseRequested:  false
returnPass:      (none)
specOut:         docs/<build_name>-spec.md
brief:           <path>
round:           1
updatedAt:       <date>
```

If `outline_trace` is on, create `docs/OUTLINE_TRACE.md` seeded with the `OL-*` obligations (status `open`),
each to be discharged by a spec section or a conscious de-scope in `ratify`.

## Then
Set `nextUnit` to the first open row and return to the hub. Do not do the research now — that is `run`, one row
per fresh context.
