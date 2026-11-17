#!/usr/bin/env python3
"""audit-stats.py — aggregate audit-build datasets into the evaluation tables (modes/evaluate.md § 3).

Usage:
  audit-stats.py <audits-dir> [--audit ID ...] [--json]

Reads every <audit-id>.tickets.tsv, <audit-id>.findings.jsonl and <audit-id>.mutations.tsv in the
directory (or only the named audits), then reports:
  Q1  per implementer x stratum: tickets with >= 1 confirmed major+ finding, k/n, Wilson 95% interval
      (round-1 audits only; duplicate rounds feed agreement, not the rate)
  Q2  confirmed findings by category x origin; severity counts per ticket
  --  auditor precision: confirmed / (confirmed + refuted), overall and per auditor
  Q5  mutation kill rate per implementer x stratum
  --  duplicate subset: Cohen's kappa on "has confirmed major+", finding overlap, Lincoln-Petersen
Effective severity = severity_adjusted if set, else severity. "Confirmed" excludes plausible.

Exit codes: 0 ok · 1 invalid input (each problem printed to stderr) · 2 no data.
Stdlib only; run with `python3 -I`. Read-only.
"""
import argparse
import csv
import glob
import json
import math
import os
import sys

SEVERITIES = ("blocker", "major", "minor", "nit")
MAJOR_PLUS = {"blocker", "major"}
VERDICTS = {"confirmed", "plausible", "refuted", ""}
CATEGORIES = {"correctness", "boundary", "security", "contract", "claims", "test-adequacy",
              "evidence-integrity", "ownership", "interface", "records", "process", "spec"}
TICKET_COLS = ("ticket", "implementer", "stratum", "audit_round", "auditor", "blind_guess", "tokens")
REQUIRED = ("id", "audit_id", "ticket", "severity", "category", "claim", "evidence", "verdict")


def wilson(k, n, z=1.959964):
    if n == 0:
        return (0.0, 1.0)
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, c - h), min(1.0, c + h))


def kappa(pairs):
    n = len(pairs)
    if n == 0:
        return None
    po = sum(1 for a, b in pairs if a == b) / n
    pa = sum(1 for a, _ in pairs if a) / n
    pb = sum(1 for _, b in pairs if b) / n
    pe = pa * pb + (1 - pa) * (1 - pb)
    if pe == 1:
        return 1.0 if po == 1 else 0.0
    return (po - pe) / (1 - pe)


def load(directory, only, problems):
    def wanted(path, suffix):
        aid = os.path.basename(path)[: -len(suffix)]
        aid = aid.split("_", 1)[1] if "_" in aid else aid
        return (not only) or aid in only, aid

    tickets, findings, mutations = [], [], []
    for path in sorted(glob.glob(os.path.join(directory, "*.tickets.tsv"))):
        ok, aid = wanted(path, ".tickets.tsv")
        if not ok:
            continue
        with open(path, newline="") as fh:
            rows = list(csv.DictReader(fh, delimiter="\t"))
        for i, r in enumerate(rows, 2):
            missing = [c for c in TICKET_COLS if c not in r]
            if missing:
                problems.append(f"{path}:{i}: missing columns {missing}")
                continue
            try:
                rnd = int(r["audit_round"] or 1)
            except ValueError:
                problems.append(f"{path}:{i}: audit_round is not an integer")
                continue
            tickets.append({**r, "audit_id": aid, "audit_round": rnd})
    for path in sorted(glob.glob(os.path.join(directory, "*.findings.jsonl"))):
        ok, aid = wanted(path, ".findings.jsonl")
        if not ok:
            continue
        with open(path) as fh:
            for i, line in enumerate(fh, 1):
                if not line.strip():
                    continue
                try:
                    f = json.loads(line)
                except json.JSONDecodeError as e:
                    problems.append(f"{path}:{i}: not JSON ({e})")
                    continue
                bad = [k for k in REQUIRED if k not in f]
                if bad:
                    problems.append(f"{path}:{i}: missing {bad}")
                    continue
                sev = f.get("severity_adjusted") or f["severity"]
                if sev not in SEVERITIES or f["severity"] not in SEVERITIES:
                    problems.append(f"{path}:{i}: bad severity")
                    continue
                if f["verdict"] not in VERDICTS or f["category"] not in CATEGORIES:
                    problems.append(f"{path}:{i}: bad verdict or category")
                    continue
                f["_sev"] = sev
                f["_round"] = int(f.get("audit_round", 1) or 1)
                findings.append(f)
    for path in sorted(glob.glob(os.path.join(directory, "*.mutations.tsv"))):
        ok, aid = wanted(path, ".mutations.tsv")
        if not ok:
            continue
        with open(path, newline="") as fh:
            for i, r in enumerate(csv.DictReader(fh, delimiter="\t"), 2):
                if r.get("killed") not in ("0", "1") or not r.get("ticket"):
                    problems.append(f"{path}:{i}: mutation row needs ticket and killed 0/1")
                    continue
                mutations.append({**r, "audit_id": aid})
    return tickets, findings, mutations


def analyze(tickets, findings, mutations):
    key = {}
    for t in tickets:
        key[(t["audit_id"], t["ticket"], t["audit_round"])] = t
    conf = [f for f in findings if f["verdict"] == "confirmed"]

    def has_major(aid, ticket, rnd):
        return any(f["audit_id"] == aid and f["ticket"] == ticket and f["_round"] == rnd
                   and f["_sev"] in MAJOR_PLUS for f in conf)

    groups = {}
    for (aid, ticket, rnd), t in key.items():
        if rnd != 1:
            continue
        g = groups.setdefault((t["implementer"], t["stratum"]),
                              {"n": 0, "k": 0, "sev": {s: 0 for s in SEVERITIES}, "mut": [0, 0]})
        g["n"] += 1
        g["k"] += 1 if has_major(aid, ticket, 1) else 0
        for f in conf:
            if f["audit_id"] == aid and f["ticket"] == ticket and f["_round"] == 1:
                g["sev"][f["_sev"]] += 1
    for m in mutations:
        t = key.get((m["audit_id"], m["ticket"], 1))
        if t:
            g = groups.get((t["implementer"], t["stratum"]))
            if g:
                g["mut"][0] += int(m["killed"])
                g["mut"][1] += 1
    q1 = []
    for (impl, stratum), g in sorted(groups.items()):
        lo, hi = wilson(g["k"], g["n"])
        q1.append({"implementer": impl, "stratum": stratum, "k": g["k"], "n": g["n"],
                   "rate": g["k"] / g["n"] if g["n"] else None, "wilson95": [round(lo, 3), round(hi, 3)],
                   "confirmed_per_ticket": {s: round(g["sev"][s] / g["n"], 2) for s in SEVERITIES},
                   "mutation_kill_rate": (round(g["mut"][0] / g["mut"][1], 3) if g["mut"][1] else None),
                   "mutations": g["mut"][1]})
    cat_origin = {}
    for f in conf:
        k2 = (f["category"], f.get("origin", "unknown"))
        cat_origin[k2] = cat_origin.get(k2, 0) + 1
    decided = [f for f in findings if f["verdict"] in ("confirmed", "refuted")]
    per_aud = {}
    for f in decided:
        t = key.get((f["audit_id"], f["ticket"], f["_round"]))
        a = t["auditor"] if t else "unknown"
        c = per_aud.setdefault(a, [0, 0])
        c[0] += f["verdict"] == "confirmed"
        c[1] += 1
    precision = {"overall": (round(sum(c[0] for c in per_aud.values()) / len(decided), 3) if decided else None),
                 "per_auditor": {a: round(c[0] / c[1], 3) for a, c in sorted(per_aud.items())}}
    # Duplicate subset: tickets audited in rounds 1 and 2 within the same audit.
    pairs, n1, n2, m = [], 0, 0, 0
    for (aid, ticket, rnd) in key:
        if rnd == 1 and (aid, ticket, 2) in key:
            pairs.append((has_major(aid, ticket, 1), has_major(aid, ticket, 2)))
            r1 = {f["id"] for f in conf if f["audit_id"] == aid and f["ticket"] == ticket
                  and f["_round"] == 1 and f["_sev"] in MAJOR_PLUS}
            r2 = [f for f in conf if f["audit_id"] == aid and f["ticket"] == ticket
                  and f["_round"] == 2 and f["_sev"] in MAJOR_PLUS]
            n1 += len(r1)
            n2 += len(r2)
            m += sum(1 for f in r2 if f.get("duplicate_of") in r1)
    union = n1 + n2 - m
    dup = {"tickets": len(pairs), "kappa_major_plus": (round(kappa(pairs), 3) if pairs else None),
           "major_plus_round1": n1, "major_plus_round2": n2, "matched": m,
           "overlap": (round(m / union, 3) if union else None),
           "lincoln_petersen_total": (round(n1 * n2 / m, 1) if m else None)}
    return {"q1": q1, "category_origin": [{"category": c, "origin": o, "n": n}
                                          for (c, o), n in sorted(cat_origin.items())],
            "precision": precision, "duplicates": dup,
            "totals": {"tickets_round1": sum(g["n"] for g in groups.values()), "findings": len(findings),
                       "confirmed": len(conf)}}


def render(r):
    out = ["## Q1: tickets with >= 1 confirmed major+ (round 1)", "",
           "| implementer | stratum | k/n | rate | Wilson 95% | confirmed/ticket b·M·m·n | mutation kill |",
           "|---|---|---|---|---|---|---|"]
    for q in r["q1"]:
        s = q["confirmed_per_ticket"]
        mk = f'{q["mutation_kill_rate"]} ({q["mutations"]})' if q["mutations"] else "-"
        out.append(f'| {q["implementer"]} | {q["stratum"]} | {q["k"]}/{q["n"]} | {q["rate"]:.2f} | '
                   f'[{q["wilson95"][0]:.2f}, {q["wilson95"][1]:.2f}] | '
                   f'{s["blocker"]}·{s["major"]}·{s["minor"]}·{s["nit"]} | {mk} |')
    out += ["", "## Q2: confirmed findings by category x origin", "", "| category | origin | n |", "|---|---|---|"]
    out += [f'| {c["category"]} | {c["origin"]} | {c["n"]} |' for c in r["category_origin"]]
    p = r["precision"]
    out += ["", f'## Auditor precision: {p["overall"]}', ""]
    out += [f"- {a}: {v}" for a, v in p["per_auditor"].items()]
    d = r["duplicates"]
    out += ["", "## Duplicate subset", "",
            f'- tickets: {d["tickets"]} · kappa (has confirmed major+): {d["kappa_major_plus"]}',
            f'- major+ round 1/2: {d["major_plus_round1"]}/{d["major_plus_round2"]} · matched: {d["matched"]} '
            f'· overlap: {d["overlap"]} · Lincoln-Petersen total: {d["lincoln_petersen_total"]}',
            "", f'Totals: {r["totals"]}']
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("directory")
    ap.add_argument("--audit", action="append", default=[])
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    problems = []
    tickets, findings, mutations = load(a.directory, set(a.audit), problems)
    for p in problems:
        print(f"audit-stats: {p}", file=sys.stderr)
    if problems:
        return 1
    if not tickets:
        print("audit-stats: no tickets.tsv rows found", file=sys.stderr)
        return 2
    r = analyze(tickets, findings, mutations)
    print(json.dumps(r, indent=2, sort_keys=True) if a.json else render(r))
    return 0


if __name__ == "__main__":
    sys.exit(main())
