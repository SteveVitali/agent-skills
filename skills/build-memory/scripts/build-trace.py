#!/usr/bin/env python3
"""build-trace.py — the per-ticket trace record (BM-TRACE-01) and the dispatcher's usage line, for any harness.

A trace line is the machine-readable twin of a run ledger's header: which ticket, at which base and head commit,
by which harness / model / effort / dispatch tier, with which skills version, how long it took, how many tokens it
used (measured from the harness's own session store, never invented) and how its verification ended. The worker
appends it to <memoryRoot>/runs/<ID>.trace.jsonl in the ticket's closeout commit, so a later evaluation (replaying
tickets at their base commit under other configurations, audit-build's evaluate mode, cost analysis) reads it
directly instead of mining transcripts the harness may already have deleted.

Usage:
  build-trace.py record --ticket ID --outcome done|blocked|gate-pending|abandoned [options]
      Append one line to <memoryRoot>/runs/<ID>.trace.jsonl (or --out FILE) and print it. Run by the worker itself.
      --run-ledger PATH   read Started:, Harness:, Base:, Spec: and ci: from this run ledger's header
                          (default: <memoryRoot>/runs/<ID>.md when it exists); flags below override it
      --base-sha SHA | --base-ref REF   the commit the branch was cut from (REF → git merge-base HEAD REF)
      --pr N  --branch NAME  --spec PATH  --started ISO
      --harness NAME  --model ID  --effort LEVEL  --dispatch headless|subagent|manual
      --ci "LINE"  --live LAYER  --layer WORD  --ac met=N,met-engineered=N,partial=N,missed=N
      --usage-json FILE   usage measured elsewhere (source "supplied"); skips measurement
      --no-measure        record usage as not-measured
      --repo DIR  --out FILE  --now ISO  --dry-run (print, do not write)
  build-trace.py dispatch-usage --harness NAME --cwd DIR --since ISO --until ISO [--output FILE] [--export FILE]
                                [--exit-code N] [--ticket ID] [--iter N] [--run ID] [--now ISO]
      Print one build-dispatch/1 line for a unit a dispatcher ran (orchestrate-build's drive-build.sh appends it to
      the gitignored logs/drive-build/usage.jsonl). The session is named by the unit's own output when the harness
      prints it (claude/cursor stream-json, codex --json, gemini --output-format json) or by its --export file
      (devin ATIF), else found in the harness's store by working directory and time window ("match": "window").
  build-trace.py result --harness NAME --output FILE
      Print a structured capture's final text (what the CLI prints in its text mode). Prints nothing otherwise.

Harnesses (the adapter is picked by --harness, else BUILD_TRACE_HARNESS, else the nearest harness process above this
one — env vars are inherited from outer sessions, so they are read only for the harness that is actually running):
  claude-code  store <CLAUDE_CONFIG_DIR|~/.claude>/projects/*/<session>.jsonl (+ <session>/subagents/agent-*.jsonl).
               Worker: CLAUDE_CODE_SESSION_ID; the worker is the transcript holding this very `build-trace.py record
               --ticket <ID>` shell call (polled for up to BUILD_TRACE_WAIT_S s, default 30: the harness writes it a
               moment after it starts) — a subagent → it and its descendants (meta.json parentAgentId); the main
               transcript → the whole session; neither → the session's lines on this branch. Effort: CLAUDE_EFFORT.
  codex        store <CODEX_HOME|~/.codex>/sessions/**/rollout-*-<thread>.jsonl. Worker: CODEX_THREAD_ID; the thread
               plus the threads it spawned (parent_thread_id); model and effort from its turn_context.
  devin        store <CHISEL_SESSION_DB|~/.local/share/devin/cli/sessions.db> (read-only; CLI and Desktop share it).
               Worker: the node holding this very shell call (Devin commits it before running it); its agent — a
               subagent → its chain plus the subagents it spawned ("Subagent agent_id=<id>" results); the lead chain →
               the whole session. Model and effort from the session's model id (e.g. swe-2-high).
  cursor, gemini, goose   dispatcher only, from the unit's structured output where the CLI prints usage (best
               effort: not verified against a live CLI here); the worker records not-measured.
  any other    not-measured with the reason (pass --usage-json when another tool measured it).
Usage counts what the store holds when the line is written. `input_tokens` is every prompt token (uncached + cache
read + cache write) for every provider, so totals compare.

Exit codes: 0 written / printed · 1 usage error · 2 cannot resolve the repo, the memory root or an input file.
Stdlib only; run with `python3 -I`. `record` writes only the trace file; the other modes write nothing.
"""
import argparse
import datetime as dt
import glob
import json
import os
import re
import sqlite3
import subprocess
import sys
import time

SCHEMA = "build-trace/1"
DISPATCH_SCHEMA = "build-dispatch/1"
OUTCOMES = ("done", "blocked", "gate-pending", "abandoned")
DISPATCHES = ("headless", "subagent", "manual", "unknown")
LIVE = ("live-executed", "staging", "fixture-only", "engineered", "n-a", "gate-pending")
HARNESSES = ("claude-code", "codex", "devin", "cursor", "gemini", "goose")
EFFORT_SUFFIX = re.compile(r"^(?P<model>.+?)-(?P<effort>minimal|low|medium|high|xhigh|max|ultra)"
                           r"(?:-(?P<variant>fast|lightning))?$")
TICKET_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
HERE = os.path.dirname(os.path.abspath(__file__))
HARNESS_ARGV0 = None     # the detected harness binary (for --version), set by detect_harness


def die(code, msg):
    sys.stderr.write("build-trace: %s\n" % msg)
    sys.exit(code)


def now_iso(override=None):
    if override:
        return override
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_iso(s):
    if not s:
        return None
    s = s.strip()
    for fmt in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S.%fZ", "%Y-%m-%dT%H:%MZ", "%Y-%m-%d"):
        try:
            return dt.datetime.strptime(s, fmt).replace(tzinfo=dt.timezone.utc)
        except ValueError:
            pass
    try:                                         # 2026-11-17T22:50:42.882112+00:00 and friends
        d = dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
        return d if d.tzinfo else d.replace(tzinfo=dt.timezone.utc)
    except ValueError:
        return None


def epoch(s):
    d = parse_iso(s)
    return d.timestamp() if d else None


def git(repo, *args):
    try:
        out = subprocess.run(["git", "-C", repo] + list(args), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                             universal_newlines=True, check=False)
    except OSError:
        return None
    return out.stdout.strip() if out.returncode == 0 else None


def read_jsonl(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line or line[0] != "{":
                    continue
                try:
                    obj = json.loads(line)
                except ValueError:
                    continue
                if isinstance(obj, dict):
                    yield obj
    except OSError:
        return


def first_line(path):
    for obj in read_jsonl(path):
        return obj
    return {}


def as_int(v):
    return v if isinstance(v, int) and not isinstance(v, bool) else 0


def real(p):
    try:
        return os.path.realpath(p) if p else None
    except OSError:
        return p


# ── run ledger header ─────────────────────────────────────────────────────────────────────────────
def ledger_header(path):
    """The lines of a run ledger before its first `## ` heading, flattened, markup stripped."""
    if not path or not os.path.isfile(path):
        return {}
    head = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if line.startswith("## "):
                break
            head.append(line.rstrip("\n"))
    text = "\n".join(head).replace("**", "").replace("`", "")
    found = {}

    def grab(key, pat):
        m = re.search(r"(?im)(?:^|[\s·|(-])" + key + r":\s*" + pat, text)
        if m:
            found[key.lower()] = m.group(1).strip()

    grab("Harness", r"([^\s·|,;]+)")
    grab("Started", r"(\d{4}-\d{2}-\d{2}T[0-9:.]+Z|\d{4}-\d{2}-\d{2})")
    grab("Spec", r"([^\s·|,;()]+)")
    grab("Base", r"([^\n·|]+)")
    m = re.search(r"(?im)^\s*[-*]?\s*ci:\s*(.+)$", text)
    if m:
        found["ci"] = m.group(1).strip()
    return found


def base_sha_from_text(repo, text):
    """`main @ ee466fa0 (flat …)` → the full sha of the first hex token that resolves to a commit."""
    for tok in re.findall(r"\b[0-9a-f]{7,40}\b", text or ""):
        full = git(repo, "rev-parse", "--verify", "--quiet", tok + "^{commit}")
        if full:
            return full
    return None


def split_label(label):
    """`devin-desktop/swe-2-high/subagent` → (harness, model, tier); missing parts are None."""
    parts = (label or "").strip().split("/")
    parts += [None] * (3 - len(parts))
    return tuple(p or None for p in parts[:3])


def label_adapter(name):
    n = (name or "").lower()
    for h in HARNESSES:
        if n == h or n.startswith(h.split("-")[0]):
            return h
    return None


def effort_of(model):
    m = EFFORT_SUFFIX.match(model or "")
    return m.group("effort") if m else None


# ── which harness is running this process ─────────────────────────────────────────────────────────
def classify(args):
    """A process's argv (as `ps` prints it) → (adapter, variant) when it is a known harness, else None."""
    toks = args.split()
    for t in toks[:2]:
        b = os.path.basename(t).lower()
        if b == "claude":
            return "claude-code", None
        if b == "codex":
            return "codex", None
        if b == "devin":
            return "devin", ("desktop" if "/Devin.app/" in args else "cli")
        if b == "cursor-agent":
            return "cursor", None
        if b == "gemini":
            return "gemini", None
        if b == "goose":
            return "goose", None
    if "/Devin.app/" in args:
        return "devin", "desktop"
    return None


def ancestry():
    """The nearest known harness process above this one: (adapter, variant, argv) or None."""
    pid = os.getppid()
    chain = []
    for _ in range(40):
        try:
            out = subprocess.run(["ps", "-o", "ppid=", "-o", "args=", "-p", str(pid)], stdout=subprocess.PIPE,
                                 stderr=subprocess.DEVNULL, universal_newlines=True, check=False).stdout.strip()
        except OSError:
            return None
        if not out:
            return None
        ppid, _, args = out.partition(" ")
        args = args.strip()
        chain.append(args)
        hit = classify(args)
        if hit:
            variant = hit[1]
            if hit[0] == "devin" and variant == "cli":
                # Devin Desktop runs `devin acp` under its app: look further up for the app before calling it the CLI.
                for _ in range(10):
                    try:
                        up = subprocess.run(["ps", "-o", "ppid=", "-o", "args=", "-p", ppid.strip()],
                                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                            universal_newlines=True, check=False).stdout.strip()
                    except OSError:
                        break
                    if not up:
                        break
                    ppid, _, uargs = up.partition(" ")
                    if "/Devin.app/" in uargs:
                        variant = "desktop"
                        break
            return hit[0], variant, args
        try:
            pid = int(ppid.strip())
        except ValueError:
            return None
        if pid <= 1:
            return None
    return None


def detect_harness(flag):
    """(adapter, variant, detected_from)."""
    if flag:
        return label_adapter(flag) or flag, None, "flag"
    env = os.environ.get("BUILD_TRACE_HARNESS")
    if env:
        return label_adapter(env) or env, None, "BUILD_TRACE_HARNESS"
    hit = ancestry()
    if hit:
        global HARNESS_ARGV0
        HARNESS_ARGV0 = next((t for t in hit[2].split()[:2] if os.path.basename(t).lower() in
                              ("claude", "codex", "devin", "cursor-agent", "gemini", "goose")), None)
        return hit[0], hit[1], "process:" + os.path.basename(HARNESS_ARGV0 or hit[2].split()[0])
    agent = os.environ.get("AI_AGENT", "")
    if agent.startswith("devin_"):
        return "devin", None, "AI_AGENT"
    if agent.startswith("claude-code_"):
        return "claude-code", None, "AI_AGENT"
    if os.environ.get("CODEX_THREAD_ID"):
        return "codex", None, "CODEX_THREAD_ID"
    if os.environ.get("CLAUDE_CODE_SESSION_ID"):
        return "claude-code", None, "CLAUDE_CODE_SESSION_ID"
    return None, None, None


def binary_version(argv0):
    """`<harness binary> --version` → its first dotted version number (claude 2.1.327, codex-cli 0.170.0, devin 3000.12.57)."""
    if not argv0:
        return None
    try:
        out = subprocess.run([argv0, "--version"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                             universal_newlines=True, timeout=10, check=False).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    m = re.search(r"\b(\d+\.\d+(?:\.\d+)?)\b", out or "")
    return m.group(1) if m else None


def agent_version(prefix):
    """AI_AGENT=claude-code_2-1-326_agent / devin_3000-12-57_agent → 2.1.326 / 3000.12.57 (only for that harness)."""
    m = re.match(r"^" + re.escape(prefix) + r"_([0-9][0-9-]*)", os.environ.get("AI_AGENT", ""))
    return m.group(1).replace("-", ".") if m else None


# ── normalized usage ────────────────────────────────────────────────────────────────────────────
class Tally:
    def __init__(self):
        self.calls = {}          # call key → (model, usage dict)
        self.compactions = 0
        self.files = 0           # transcripts / threads / agents that contributed

    def add_call(self, key, model, usage):
        self.calls[key] = (model, usage)


def finish_usage(source, scope, tally, unit="transcripts"):
    tot = {"model_calls": 0, "input_tokens": 0, "uncached_input_tokens": 0, "cache_read_tokens": 0,
           "cache_write_tokens": 0, "output_tokens": 0, "reasoning_tokens": None, "peak_context_tokens": 0}
    by_model = {}
    for model, u in tally.calls.values():
        calls = u.get("calls", 1)
        prompt = u["uncached"] + u["cache_read"] + u["cache_write"]
        peak = u.get("peak", prompt)
        tot["model_calls"] += calls
        tot["input_tokens"] += prompt
        tot["uncached_input_tokens"] += u["uncached"]
        tot["cache_read_tokens"] += u["cache_read"]
        tot["cache_write_tokens"] += u["cache_write"]
        tot["output_tokens"] += u["output"]
        if u.get("reasoning") is not None:
            tot["reasoning_tokens"] = (tot["reasoning_tokens"] or 0) + u["reasoning"]
        tot["peak_context_tokens"] = max(tot["peak_context_tokens"], peak)
        m = by_model.setdefault(model, {"model_calls": 0, "input_tokens": 0, "cache_read_tokens": 0,
                                        "cache_write_tokens": 0, "output_tokens": 0})
        m["model_calls"] += calls
        m["input_tokens"] += prompt
        m["cache_read_tokens"] += u["cache_read"]
        m["cache_write_tokens"] += u["cache_write"]
        m["output_tokens"] += u["output"]
    out = {"source": source, "scope": scope, unit: tally.files}
    out.update(tot)
    out["compactions"] = tally.compactions
    out["by_model"] = by_model
    return out


def not_measured(reason):
    return {"source": "not-measured", "reason": reason}


def main_model(usage):
    bm = (usage or {}).get("by_model") or {}
    return max(bm.items(), key=lambda kv: kv[1]["output_tokens"])[0] if bm else None


def wait_seconds():
    try:
        return float(os.environ.get("BUILD_TRACE_WAIT_S", "30"))
    except ValueError:
        return 30.0


# ── Claude Code ─────────────────────────────────────────────────────────────────────────────────
def claude_usage_of(u):
    det = u.get("output_tokens_details")
    think = det.get("thinking_tokens") if isinstance(det, dict) else None
    return {"uncached": as_int(u.get("input_tokens")), "cache_read": as_int(u.get("cache_read_input_tokens")),
            "cache_write": as_int(u.get("cache_creation_input_tokens")), "output": as_int(u.get("output_tokens")),
            "reasoning": think if isinstance(think, int) else None}


def claude_conf():
    return os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")


def scan_claude_file(path, tally, branch=None):
    before = (len(tally.calls), tally.compactions)
    for obj in read_jsonl(path):
        if branch is not None and obj.get("gitBranch") != branch:
            continue
        typ = obj.get("type")
        if typ == "system" and obj.get("subtype") == "compact_boundary":
            tally.compactions += 1
            continue
        if typ != "assistant":
            continue
        msg = obj.get("message")
        if not isinstance(msg, dict) or not isinstance(msg.get("usage"), dict):
            continue
        model = msg.get("model") or "unknown"
        if model == "<synthetic>" or obj.get("isApiErrorMessage"):
            continue
        key = msg.get("id") or obj.get("uuid") or "%s:%d" % (path, len(tally.calls))
        tally.add_call(key, model, claude_usage_of(msg["usage"]))
    if (len(tally.calls), tally.compactions) != before:
        tally.files += 1


def record_call_re(ticket):
    return re.compile(r"build-trace\.py\S*\s+record\b.*--ticket[= ]+(?:\\?[\"'])?" + re.escape(ticket)
                      + r"(?![A-Za-z0-9._-])", re.S)


def claude_marks(path, pat):
    """Latest timestamp of an assistant shell tool_use in `path` that ran `build-trace.py record` for the ticket."""
    latest = None
    for obj in read_jsonl(path):
        if obj.get("type") != "assistant":
            continue
        content = (obj.get("message") or {}).get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict) or block.get("type") != "tool_use":
                continue
            inp = block.get("input")
            text = inp.get("command") if isinstance(inp, dict) else None   # a shell call, not a prompt naming it
            if isinstance(text, str) and pat.search(text):
                ts = obj.get("timestamp") or ""
                if latest is None or ts > latest:
                    latest = ts
    return latest


def claude_session_files(session_id):
    hits = sorted(glob.glob(os.path.join(claude_conf(), "projects", "*", session_id + ".jsonl")))
    if not hits:
        return None, {}
    main = hits[0]
    agents = {}  # agent id → (path, parent id)
    for p in sorted(glob.glob(os.path.join(main[:-len(".jsonl")], "subagents", "agent-*.jsonl"))):
        aid = os.path.basename(p)[len("agent-"):-len(".jsonl")]
        parent = None
        try:
            with open(p[:-len(".jsonl")] + ".meta.json", encoding="utf-8") as fh:
                parent = (json.load(fh) or {}).get("parentAgentId")
        except (OSError, ValueError):
            pass
        agents[aid] = (p, parent)
    return main, agents


def claude_worker(ticket, branch):
    sid = os.environ.get("CLAUDE_CODE_SESSION_ID")
    if not sid:
        return not_measured("claude-code: CLAUDE_CODE_SESSION_ID is not set"), None, {}
    main, agents = claude_session_files(sid)
    if not main:
        return not_measured("claude-code: no transcript for session %s under %s/projects" % (sid, claude_conf())), \
            {"id": sid}, {}
    pat = record_call_re(ticket)
    owners = [(main, None)] + [(p, aid) for aid, (p, _) in sorted(agents.items())]
    deadline = time.time() + wait_seconds()
    marks = []
    while True:
        now = time.time()
        for p, aid in owners:
            try:
                if now - os.path.getmtime(p) > 600:
                    continue
            except OSError:
                continue
            ts = claude_marks(p, pat)
            if ts is not None:
                marks.append((ts, aid))
        if marks or now >= deadline:
            break
        time.sleep(0.25)
    if not marks:
        for p, aid in owners:
            ts = claude_marks(p, pat)
            if ts is not None:
                marks.append((ts, aid))
    tally = Tally()
    session = {"id": sid}
    root = sorted(marks, key=lambda m: (m[0], m[1] is None))[-1][1] if marks else "branch"
    if root is None:                       # the session itself is the worker (headless / manual)
        scope = "session"
        for p, _ in owners:
            scan_claude_file(p, tally)
    elif root == "branch":                 # the call was not found: every line of the session on this branch
        scope = "branch"
        for p, _ in owners:
            scan_claude_file(p, tally, branch=branch)
    else:                                  # a subagent is the worker: it and its descendants
        scope = "agent-tree"
        session["agent_id"] = root
        tree = {root}
        grew = True
        while grew:
            grew = False
            for aid, (_, parent) in agents.items():
                if aid not in tree and parent in tree:
                    tree.add(aid)
                    grew = True
        for aid in sorted(tree):
            scan_claude_file(agents[aid][0], tally)
    usage = finish_usage("claude-code-transcript", scope, tally)
    meta = {"model": main_model(usage), "version": agent_version("claude-code")}
    if os.environ.get("CLAUDE_EFFORT"):
        meta["effort"], meta["effort_source"] = os.environ["CLAUDE_EFFORT"], "CLAUDE_EFFORT"
    return usage, session, meta


def claude_sessions_usage(ids):
    tally = Tally()
    found = 0
    for sid in ids:
        main, agents = claude_session_files(sid)
        if not main:
            continue
        found += 1
        scan_claude_file(main, tally)
        for _, (p, _) in sorted(agents.items()):
            scan_claude_file(p, tally)
    return finish_usage("claude-code-transcript", "session", tally) if found else None


def claude_discover(cwd, since, until):
    """Sessions whose transcript started in [since, until] in `cwd` (the dispatcher's fallback)."""
    ids = []
    for p in glob.glob(os.path.join(claude_conf(), "projects", "*", "*.jsonl")):
        try:
            if os.path.getmtime(p) < since - 5:
                continue
        except OSError:
            continue
        for obj in read_jsonl(p):
            if "cwd" not in obj:
                continue
            t = epoch(obj.get("timestamp"))
            if real(obj.get("cwd")) == real(cwd) and t is not None and since - 5 <= t <= until + 5:
                ids.append(os.path.basename(p)[:-len(".jsonl")])
            break
    return sorted(ids)


# ── Codex ───────────────────────────────────────────────────────────────────────────────────────
def codex_home():
    return os.environ.get("CODEX_HOME") or os.path.join(os.path.expanduser("~"), ".codex")


def codex_rollouts():
    return sorted(glob.glob(os.path.join(codex_home(), "sessions", "**", "rollout-*.jsonl"), recursive=True))


def codex_threads_usage(thread_ids):
    files = codex_rollouts()
    roots = []
    for tid in thread_ids:
        roots += [f for f in files if f.endswith("-" + tid + ".jsonl")]
    if not roots:
        return None, {}
    first_root = min(os.path.basename(r)[:len("rollout-YYYY-MM-DDTHH-MM-SS")] for r in roots)
    parent_of = {}
    for f in files:
        if os.path.basename(f) < first_root:
            continue
        meta = (first_line(f) or {}).get("payload") or {}
        if meta.get("id"):
            parent_of[meta["id"]] = (f, meta.get("parent_thread_id"))
    tree = set(thread_ids)
    grew = True
    while grew:
        grew = False
        for tid, (_, parent) in parent_of.items():
            if tid not in tree and parent in tree:
                tree.add(tid)
                grew = True
    tally = Tally()
    ctx = {}
    paths = sorted(set(roots) | {parent_of[t][0] for t in tree if t in parent_of})
    for f in paths:
        model = None
        last_total = None
        peak = 0
        ncalls = 0
        records = {}                     # response_id → usage (token_usage_record: one per model response)
        rec_peak = 0
        is_root = f in roots
        for obj in read_jsonl(f):
            typ = obj.get("type")
            p = obj.get("payload") or {}
            if typ == "token_usage_record" and isinstance(p.get("usage"), dict):
                records[p.get("response_id") or len(records)] = p["usage"]
                rec_peak = max(rec_peak, as_int(p["usage"].get("input_tokens")))
            elif typ == "session_meta" and is_root and p.get("cli_version"):
                ctx.setdefault("version", p.get("cli_version"))
            elif typ == "turn_context":
                model = model or p.get("model")
                if is_root and "model" not in ctx:
                    ctx.update(model=p.get("model"), effort=p.get("effort") or p.get("reasoning_effort"))
            elif typ == "compacted":
                tally.compactions += 1
            elif typ == "event_msg" and p.get("type") == "token_count":
                info = p.get("info") or {}
                tot = info.get("total_token_usage")
                if isinstance(tot, dict) and tot != last_total:
                    last_total = tot
                    ncalls += 1
                lastu = info.get("last_token_usage")
                if isinstance(lastu, dict):
                    peak = max(peak, as_int(lastu.get("input_tokens")))
        if records:                      # per-response records are complete; token_count can miss responses
            last_total = {}
            for u in records.values():
                for k, v in u.items():
                    if isinstance(v, int) and not isinstance(v, bool):
                        last_total[k] = last_total.get(k, 0) + v
            ncalls, peak = len(records), rec_peak
        if last_total:
            inp = as_int(last_total.get("input_tokens"))
            cr = as_int(last_total.get("cached_input_tokens"))
            cw = as_int(last_total.get("cache_write_input_tokens"))
            rs = last_total.get("reasoning_output_tokens")
            # Codex counts cached tokens inside input_tokens; split them out so the totals compare with Claude's.
            tally.files += 1
            tally.add_call(f, model or "unknown", {
                "uncached": max(0, inp - cr - cw), "cache_read": cr, "cache_write": cw,
                "output": as_int(last_total.get("output_tokens")), "reasoning": rs if isinstance(rs, int) else None,
                "calls": ncalls, "peak": peak})
    return finish_usage("codex-rollout", "thread-tree", tally, unit="threads"), ctx


def codex_settled(tid, pat):
    """True once the rollout holds a token_usage_record after this record call (Codex writes it right after)."""
    for f in codex_rollouts():
        if f.endswith("-" + tid + ".jsonl"):
            seen = False
            for obj in read_jsonl(f):
                p = obj.get("payload") or {}
                if obj.get("type") == "response_item" and p.get("type") in ("custom_tool_call", "function_call",
                                                                             "local_shell_call"):
                    if pat.search(json.dumps(p.get("input") or p.get("arguments") or p.get("action") or "")):
                        seen = True
                elif seen and obj.get("type") == "token_usage_record":
                    return True
            return False
    return False


def codex_worker(ticket, branch):
    tid = os.environ.get("CODEX_THREAD_ID")
    if not tid:
        return not_measured("codex: CODEX_THREAD_ID is not set"), None, {}
    pat = record_call_re(ticket)
    deadline = time.time() + wait_seconds()
    while not codex_settled(tid, pat) and time.time() < deadline:
        time.sleep(0.25)
    usage, ctx = codex_threads_usage([tid])
    if usage is None:
        return not_measured("codex: no rollout for thread %s under %s/sessions" % (tid, codex_home())), {"id": tid}, {}
    meta = {"model": ctx.get("model") or main_model(usage), "version": ctx.get("version") or os.environ.get("CODEX_VERSION")}
    if ctx.get("effort"):
        meta["effort"], meta["effort_source"] = ctx["effort"], "turn_context"
    return usage, {"id": tid}, meta


def codex_discover(cwd, since, until):
    ids = []
    for f in codex_rollouts():
        try:
            if os.path.getmtime(f) < since - 5:
                continue
        except OSError:
            continue
        meta = (first_line(f) or {}).get("payload") or {}
        t = epoch(meta.get("timestamp"))
        if meta.get("id") and not meta.get("parent_thread_id") and real(meta.get("cwd")) == real(cwd) \
                and t is not None and since - 5 <= t <= until + 5:
            ids.append(meta["id"])
    return sorted(ids)


# ── Devin (CLI and Desktop share one SQLite store) ───────────────────────────────────────────────
def devin_db_path():
    p = os.environ.get("CHISEL_SESSION_DB")
    if p:
        return p
    base = os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local", "share")
    return os.path.join(base, "devin", "cli", "sessions.db")


def devin_connect():
    p = devin_db_path()
    if not os.path.isfile(p):
        return None, "devin: no session store at %s" % p
    try:
        return sqlite3.connect("file:%s?mode=ro" % p, uri=True, timeout=10), None
    except sqlite3.Error as e:
        return None, "devin: cannot open %s: %s" % (p, e)


def devin_nodes(c, session_id):
    """node_id → (parent, message_id, role, model, metrics|None, summarized_from, spawned agent ids)."""
    nodes = {}
    rows = c.execute(
        "SELECT node_id, parent_node_id, json_extract(chat_message,'$.message_id'), json_extract(chat_message,'$.role'),"
        " json_extract(chat_message,'$.metadata.generation_model'), json_extract(chat_message,'$.metadata.metrics'),"
        " json_extract(metadata,'$.summarized_from'),"
        " CASE WHEN json_extract(chat_message,'$.role')='tool' THEN substr(json_extract(chat_message,'$.content'),1,400)"
        " END FROM message_nodes WHERE session_id=?", (session_id,))
    for nid, par, mid, role, model, metrics, summ, tooltxt in rows:
        try:
            m = json.loads(metrics) if metrics else None
        except ValueError:
            m = None
        spawned = re.findall(r"\bagent_id=([0-9A-Za-z_-]+)", tooltxt or "")
        nodes[nid] = (par, mid, role, model, m, summ, spawned)
    return nodes


def devin_roots(nodes):
    memo = {}

    def root(n):
        path = []
        while n not in memo:
            par = nodes.get(n, (None,))[0]
            if par is None or par not in nodes:
                memo[n] = n
                break
            path.append(n)
            n = par
        r = memo[n]
        for p in path:
            memo[p] = r
        return r
    for n in nodes:
        root(n)
    # A compaction summary continues the chain it summarized: join the two roots.
    alias = {}
    for n, v in nodes.items():
        if v[5] is not None and v[5] in memo:
            alias[memo[v[5]]] = memo[n]
    return {n: alias.get(r, r) for n, r in memo.items()}


def devin_tally(nodes, roots, keep=None):
    tally = Tally()
    contributing = set()
    for nid, (par, mid, role, model, m, summ, _) in nodes.items():
        if keep is not None and roots[nid] not in keep:
            continue
        if summ is not None:
            tally.compactions += 1
        if role != "assistant" or not isinstance(m, dict):
            continue
        cw = as_int(m.get("cache_creation_tokens"))
        tally.add_call(mid or ("n%d" % nid), model or "unknown", {
            "uncached": as_int(m.get("input_tokens")), "cache_read": as_int(m.get("cache_read_tokens")),
            "cache_write": cw, "output": as_int(m.get("output_tokens")), "reasoning": None,
            "peak": as_int(m.get("context_input_tokens")) or None})
        contributing.add(roots[nid])
    for k, (model, u) in list(tally.calls.items()):
        if u["peak"] is None:
            u["peak"] = u["uncached"] + u["cache_read"] + u["cache_write"]
    tally.files = len(contributing)
    return tally


def devin_session_row(c, sid):
    r = c.execute("SELECT model, working_directory, main_chain_id FROM sessions WHERE id=?", (sid,)).fetchone()
    return r or (None, None, None)


def devin_worker(ticket, branch):
    c, err = devin_connect()
    if c is None:
        return not_measured(err), None, {}
    pat = record_call_re(ticket)
    hit = None
    deadline = time.time() + wait_seconds()
    try:
        while hit is None:
            top = c.execute("SELECT max(row_id) FROM message_nodes").fetchone()[0] or 0
            # Only the newest rows: the store is large, and this call was committed just before it ran.
            for sid, nid, cm in c.execute(
                    "SELECT session_id, node_id, chat_message FROM message_nodes WHERE row_id > ? "
                    "AND chat_message LIKE '%build-trace.py%' ORDER BY row_id DESC", (top - 20000,)):
                try:
                    calls = json.loads(cm).get("tool_calls") or []
                except ValueError:
                    continue
                for call in calls:
                    args = call.get("arguments") if isinstance(call, dict) else None
                    if isinstance(args, str):
                        try:
                            args = json.loads(args)
                        except ValueError:
                            args = {"command": args}
                    cmd = args.get("command") if isinstance(args, dict) else None
                    if isinstance(cmd, str) and pat.search(cmd):
                        hit = (sid, nid)
                        break
                if hit:
                    break
            if hit or time.time() >= deadline:
                break
            time.sleep(0.25)
        if hit is None:
            return not_measured("devin: this build-trace.py record call was not found in %s" % devin_db_path()), \
                None, {}
        sid, nid = hit
        model, _, main_chain = devin_session_row(c, sid)
        nodes = devin_nodes(c, sid)
        heads = dict(c.execute("SELECT agent_id, chain_node_id FROM subagent_heads WHERE session_id=?", (sid,)))
    except sqlite3.Error as e:
        return not_measured("devin: %s" % e), None, {}
    finally:
        c.close()
    roots = devin_roots(nodes)
    agent_root = {a: roots[h] for a, h in heads.items() if h in roots}
    owner = {r: a for a, r in agent_root.items()}
    mine = roots.get(nid)
    session = {"id": sid}
    if mine is not None and mine in owner and (main_chain is None or roots.get(main_chain) != mine):
        scope = "agent-tree"
        session["agent_id"] = owner[mine]
        keep = {mine}
        grew = True
        while grew:                          # descendants: agents whose spawn result sits in a kept chain
            grew = False
            for n, v in nodes.items():
                if roots[n] in keep:
                    for a in v[6]:
                        r = agent_root.get(a)
                        if r is not None and r not in keep:
                            keep.add(r)
                            grew = True
        tally = devin_tally(nodes, roots, keep)
    else:
        scope = "session"
        tally = devin_tally(nodes, roots)
    usage = finish_usage("devin-session-store", scope, tally, unit="chains")
    meta = {"model": model or main_model(usage), "version": agent_version("devin")}
    if effort_of(meta["model"]):
        meta["effort"], meta["effort_source"] = effort_of(meta["model"]), "model-id"
    return usage, session, meta


def devin_sessions_usage(ids):
    c, err = devin_connect()
    if c is None:
        return None, err
    tally_all = Tally()
    found = 0
    try:
        for sid in ids:
            nodes = devin_nodes(c, sid)
            if not nodes:
                continue
            found += 1
            t = devin_tally(nodes, devin_roots(nodes))
            tally_all.calls.update(t.calls)
            tally_all.compactions += t.compactions
            tally_all.files += t.files
        models = [devin_session_row(c, sid)[0] for sid in ids]
    except sqlite3.Error as e:
        return None, "devin: %s" % e
    finally:
        c.close()
    if not found:
        return None, "devin: no nodes for session(s) %s" % ",".join(ids)
    u = finish_usage("devin-session-store", "session", tally_all, unit="chains")
    u["session_models"] = [m for m in models if m]
    return u, None


def devin_discover(cwd, since, until):
    c, _ = devin_connect()
    if c is None:
        return []
    try:
        rows = c.execute("SELECT id, working_directory, created_at FROM sessions WHERE created_at >= ? AND created_at <= ?",
                         (int(since) - 5, int(until) + 5)).fetchall()
    except sqlite3.Error:
        rows = []
    finally:
        c.close()
    return sorted(r[0] for r in rows if real(r[1]) == real(cwd))


WORKERS = {"claude-code": claude_worker, "codex": codex_worker, "devin": devin_worker}


# ── structured unit output (dispatcher) ──────────────────────────────────────────────────────────
def parse_output(harness, path):
    """What a unit's own output says: {session_ids, usage?, cost_usd?, num_turns?, duration_ms?, model?, result?}."""
    out = {"session_ids": []}
    if not path or not os.path.isfile(path):
        return out
    if harness in ("claude-code", "cursor"):
        ev = list(read_jsonl(path))
        init = next((e for e in ev if e.get("type") == "system" and e.get("subtype") == "init"), {})
        res = next((e for e in reversed(ev) if e.get("type") == "result"), None)
        sid = (res or {}).get("session_id") or init.get("session_id")
        if sid:
            out["session_ids"] = [sid]
        out["model"] = init.get("model")
        if res is not None:
            out.update(cost_usd=res.get("total_cost_usd"), num_turns=res.get("num_turns"),
                       duration_ms=res.get("duration_ms"), is_error=res.get("is_error"))
            if isinstance(res.get("result"), str):
                out["result"] = res["result"]
            if isinstance(res.get("usage"), dict):
                t = Tally()
                t.files = 1
                t.add_call("result", out.get("model") or "unknown", claude_usage_of(res["usage"]))
                out["usage"] = finish_usage(harness + "-stream", "process", t, unit="streams")
    elif harness == "codex":
        t = Tally()
        n = 0
        for e in read_jsonl(path):
            if e.get("type") == "thread.started" and e.get("thread_id"):
                out["session_ids"].append(e["thread_id"])
            elif e.get("type") == "turn.completed" and isinstance(e.get("usage"), dict):
                u = e["usage"]
                inp, cr, cw = as_int(u.get("input_tokens")), as_int(u.get("cached_input_tokens")), \
                    as_int(u.get("cache_write_input_tokens"))
                n += 1
                rs = u.get("reasoning_output_tokens")
                t.add_call("turn%d" % n, "unknown", {"uncached": max(0, inp - cr - cw), "cache_read": cr,
                                                     "cache_write": cw, "output": as_int(u.get("output_tokens")),
                                                     "reasoning": rs if isinstance(rs, int) else None, "peak": inp})
            elif e.get("type") == "item.completed" and (e.get("item") or {}).get("type") == "agent_message":
                out["result"] = e["item"].get("text")
        if n:
            t.files = 1
            out["usage"] = finish_usage("codex-stream", "process", t, unit="streams")
    elif harness == "gemini":
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                txt = fh.read()
            obj = json.loads(txt[txt.index("{"):])
        except (OSError, ValueError):
            obj = {}
        if isinstance(obj.get("response"), str):
            out["result"] = obj["response"]
        models = ((obj.get("stats") or {}).get("models") or {})
        t = Tally()
        for name, s in models.items():
            tok = (s or {}).get("tokens") or {}
            cached = as_int(tok.get("cached"))
            t.add_call(name, name, {"uncached": max(0, as_int(tok.get("prompt")) - cached), "cache_read": cached,
                                    "cache_write": 0, "output": as_int(tok.get("candidates")) + as_int(tok.get("thoughts")),
                                    "reasoning": as_int(tok.get("thoughts")) if "thoughts" in tok else None,
                                    "calls": as_int(((s or {}).get("api") or {}).get("totalRequests")) or 1})
        if t.calls:
            t.files = 1
            out["usage"] = finish_usage("gemini-stats", "process", t, unit="streams")
    return out


def parse_export(harness, path):
    """Devin's --export file is an ATIF trajectory: its session_id names the session in the store."""
    if harness != "devin" or not path or not os.path.isfile(path):
        return {}
    try:
        with open(path, encoding="utf-8") as fh:
            d = json.load(fh)
    except (OSError, ValueError):
        return {}
    return {"session_id": d.get("session_id"), "model": (d.get("agent") or {}).get("model_name"),
            "final_metrics": d.get("final_metrics")}


def cmd_dispatch_usage(a):
    h = label_adapter(a.harness) or a.harness
    since, until = epoch(a.since), epoch(a.until)
    if since is None or until is None:
        die(1, "--since and --until must be ISO-8601 times")
    out = parse_output(h, a.output)
    exp = parse_export(h, a.export)
    ids = list(out.get("session_ids") or [])
    if exp.get("session_id") and exp["session_id"] not in ids:
        ids.append(exp["session_id"])
    match = "output" if out.get("session_ids") else ("export" if ids else None)
    discover = {"claude-code": claude_discover, "codex": codex_discover, "devin": devin_discover}.get(h)
    if not ids and discover and a.cwd:
        ids = discover(a.cwd, since, until)
        match = "window" if ids else None
    usage = None
    reason = None
    if ids and h == "claude-code":
        usage = claude_sessions_usage(ids)
    elif ids and h == "codex":
        usage, _ = codex_threads_usage(ids)
    elif ids and h == "devin":
        usage, reason = devin_sessions_usage(ids)
    if usage is None and out.get("usage"):
        usage = out["usage"]
    if usage is None:
        usage = not_measured(reason or ("%s: no session found (output, export or %s in the time window)"
                                        % (h, "store" if discover else "no store adapter")))
    rec = {"schema": DISPATCH_SCHEMA, "recorded_at": now_iso(a.now), "ticket": a.ticket, "iter": a.iter,
           "run": a.run, "harness": h, "sessions": ids, "match": match, "started_at": a.since, "ended_at": a.until,
           "wall_s": int(until - since), "exit_code": a.exit_code,
           "model": out.get("model") or ((usage.get("session_models") or [None])[0]) or main_model(usage)
           or exp.get("model"),
           "cost_usd": out.get("cost_usd"), "num_turns": out.get("num_turns"), "duration_ms": out.get("duration_ms"),
           "usage": usage}
    print(json.dumps(rec, ensure_ascii=False, separators=(",", ":")))
    return 0


def cmd_result(a):
    r = parse_output(label_adapter(a.harness) or a.harness, a.output).get("result")
    if isinstance(r, str):
        print(r)
    return 0


# ── record ──────────────────────────────────────────────────────────────────────────────────────
def parse_ac(s):
    if not s:
        return None
    out = {}
    for part in s.split(","):
        if not part.strip():
            continue
        k, sep, v = part.partition("=")
        if not sep or not v.strip().isdigit():
            die(1, "--ac wants met=N,met-engineered=N,partial=N,missed=N (got %r)" % s)
        out[k.strip().replace("-", "_")] = int(v)
    return out


def repo_slug(url):
    if not url:
        return None
    url = re.sub(r"//[^@/]+@", "//", url)   # never record credentials embedded in a remote URL
    m = re.search(r"[:/]([^/:]+/[^/]+?)(?:\.git)?/?$", url)
    return m.group(1) if m else None


def skills_identity():
    top = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))     # <skills repo>/skills/build-memory/scripts
    ident = {"sha": None, "version": None}
    sha = git(top, "rev-parse", "HEAD") if os.path.exists(os.path.join(top, ".git")) else None
    if sha:
        ident["sha"] = sha
        if git(top, "status", "--porcelain", "--untracked-files=no"):
            ident["dirty"] = True
    else:
        try:
            with open(os.path.join(top, "RELEASE"), encoding="utf-8") as fh:
                rel = json.load(fh)
            ident["sha"] = rel.get("source_head")
            ident["release"] = rel.get("name")
        except (OSError, ValueError):
            pass
    try:
        with open(os.path.join(top, ".claude-plugin", "plugin.json"), encoding="utf-8") as fh:
            ident["version"] = json.load(fh).get("version")
    except (OSError, ValueError):
        pass
    return ident


def memory_root(repo):
    try:
        out = subprocess.run(["bash", os.path.join(HERE, "memory-root.sh"), repo], stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, universal_newlines=True, check=False)
    except OSError:
        return None, None
    mode = root = None
    for line in out.stdout.splitlines():
        if line.startswith("mode="):
            mode = line[5:]
        elif line.startswith("root="):
            root = line[5:]
    return (mode, root) if out.returncode == 0 else (None, None)


def cmd_record(a):
    if not TICKET_RE.match(a.ticket or ""):
        die(1, "--ticket must be a ticket id ([A-Za-z0-9._-]), got %r" % a.ticket)
    if a.outcome not in OUTCOMES:
        die(1, "--outcome must be one of %s" % "|".join(OUTCOMES))
    if a.dispatch and a.dispatch not in DISPATCHES:
        die(1, "--dispatch must be one of %s" % "|".join(DISPATCHES))
    if a.live and a.live not in LIVE:
        die(1, "--live must be one of %s" % "|".join(LIVE))
    repo = git(a.repo or os.getcwd(), "rev-parse", "--show-toplevel")
    if not repo:
        die(2, "not inside a git worktree: %s" % (a.repo or os.getcwd()))

    out = a.out
    rl_default = None
    if not out:
        mode, root = memory_root(repo)
        if mode != "committed" or not root:
            die(2, "no committed build-memory root for %s (scratch mode): pass --out FILE" % repo)
        out = os.path.join(root, "runs", a.ticket + ".trace.jsonl")
        rl_default = os.path.join(root, "runs", a.ticket + ".md")
    run_ledger = a.run_ledger or (rl_default if rl_default and os.path.isfile(rl_default) else None)
    hdr = ledger_header(run_ledger)

    branch = a.branch or git(repo, "branch", "--show-current") or None
    head = git(repo, "rev-parse", "HEAD")
    base_sha = None
    base_src = None
    if a.base_sha:
        base_sha = git(repo, "rev-parse", "--verify", "--quiet", a.base_sha + "^{commit}")
        if not base_sha:
            die(1, "--base-sha %s is not a commit in %s" % (a.base_sha, repo))
        base_src = "flag"
    elif a.base_ref:
        base_sha = git(repo, "merge-base", "HEAD", a.base_ref)
        base_src = "merge-base(%s)" % a.base_ref if base_sha else None
    elif hdr.get("base"):
        base_sha = base_sha_from_text(repo, hdr["base"])
        base_src = "run-ledger" if base_sha else None
    base = {"sha": base_sha, "source": base_src}
    if hdr.get("base"):
        base["recorded"] = hdr["base"][:200]
    diff = None
    if base_sha and head:
        stat = git(repo, "diff", "--shortstat", base_sha, head) or ""
        nums = {k: 0 for k in ("files", "insertions", "deletions")}
        for n, word in re.findall(r"(\d+) (file|insertion|deletion)", stat):
            nums[{"file": "files", "insertion": "insertions", "deletion": "deletions"}[word]] = int(n)
        diff = nums

    spec_path = a.spec or hdr.get("spec")
    spec = None
    if spec_path:
        spec = {"path": spec_path}
        if base_sha:
            blob = git(repo, "rev-parse", "--verify", "--quiet", "%s:%s" % (base_sha, spec_path))
            if blob:
                spec["blob_at_base"] = blob

    # Harness: the running process tree decides; the run ledger's label is kept as recorded.
    label = hdr.get("harness")
    l_h, l_m, l_t = split_label(label)
    adapter, variant, detected = detect_harness(a.harness)
    if adapter is None and l_h:
        adapter, detected = label_adapter(l_h), "run-ledger"
    name = adapter
    if adapter == "devin":
        name = "devin-" + variant if variant else (l_h if (l_h or "").startswith("devin") else "devin")
    harness = {"label": label, "name": name or l_h, "version": None, "detected_from": detected}
    model = a.model
    effort = a.effort
    effort_src = "flag" if a.effort else None
    usage = None
    session = None
    if a.usage_json:
        try:
            with open(a.usage_json, encoding="utf-8") as fh:
                usage = json.load(fh)
        except (OSError, ValueError) as e:
            die(2, "--usage-json %s: %s" % (a.usage_json, e))
        if not isinstance(usage, dict):
            die(2, "--usage-json %s is not a JSON object" % a.usage_json)
        usage.setdefault("source", "supplied")
    elif a.no_measure:
        usage = not_measured("--no-measure")
    worker = WORKERS.get(adapter)
    if worker and usage is None:
        usage, session, meta = worker(a.ticket, branch)
        harness["version"] = meta.get("version")
        model = model or meta.get("model")
    if detected and detected.startswith("process:"):     # the running binary is the authority on its version
        harness["version"] = binary_version(HARNESS_ARGV0) or harness["version"]
        if not effort and meta.get("effort"):
            effort, effort_src = meta["effort"], meta.get("effort_source")
    if usage is None:
        usage = not_measured("%s: this harness exposes no session store to the worker (pass --usage-json)"
                             % (adapter or "unknown harness"))
    if not model and l_m:
        model = l_m
    if not effort and effort_of(model):
        effort, effort_src = effort_of(model), "model-suffix"
    dispatch = a.dispatch or os.environ.get("BUILD_TRACE_DISPATCH") or l_t or "unknown"
    if dispatch not in DISPATCHES:
        dispatch = "unknown"

    started = a.started or hdr.get("started")
    closed = now_iso(a.now)
    t0, t1 = parse_iso(started), parse_iso(closed)
    wall = int((t1 - t0).total_seconds()) if t0 and t1 and t1 >= t0 and "T" in (started or "") else None

    ci = a.ci or hdr.get("ci")
    ci_status = None
    if ci:
        m = re.match(r"^\s*(?:ci:\s*)?([a-z-]+)", ci)
        ci_status = m.group(1) if m else None
    verification = {"ci": ci, "ci_status": ci_status, "live": a.live, "layer": a.layer, "ac": parse_ac(a.ac)}

    attempt = 1
    if os.path.isfile(out):
        with open(out, encoding="utf-8", errors="replace") as fh:
            attempt += sum(1 for line in fh if line.strip())

    rec = {
        "schema": SCHEMA, "recorded_at": closed, "ticket": a.ticket, "attempt": attempt, "outcome": a.outcome,
        "repo": repo_slug(git(repo, "remote", "get-url", "origin")), "branch": branch, "base": base,
        "head_sha": head, "diff": diff, "pr": a.pr, "spec": spec, "harness": harness, "model": model,
        "effort": effort, "effort_source": effort_src, "dispatch": dispatch, "session": session,
        "skills": skills_identity(), "started_at": started, "closed_at": closed, "wall_s": wall,
        "usage": usage, "verification": verification, "dispatch_run": os.environ.get("BUILD_TRACE_RUN"),
        "recorded_by": "build-trace.py",
    }
    line = json.dumps(rec, ensure_ascii=False, separators=(",", ":"))
    if not a.dry_run:
        os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
        needs_nl = False
        if os.path.isfile(out) and os.path.getsize(out) > 0:
            with open(out, "rb") as fh:
                fh.seek(-1, os.SEEK_END)
                needs_nl = fh.read(1) != b"\n"
        with open(out, "a", encoding="utf-8") as fh:
            fh.write(("\n" if needs_nl else "") + line + "\n")
        sys.stderr.write("build-trace: appended attempt %d to %s (harness %s, usage %s)\n"
                         % (attempt, out, name or "unknown", usage["source"]))
    print(line)
    return 0


class Parser(argparse.ArgumentParser):
    def error(self, message):            # a usage error exits 1 (the documented contract), not argparse's 2
        self.print_usage(sys.stderr)
        die(1, message)


def main(argv):
    ap = Parser(prog="build-trace.py", description="per-ticket trace records (BM-TRACE-01)")
    sub = ap.add_subparsers(dest="cmd", parser_class=Parser)
    r = sub.add_parser("record")
    r.add_argument("--ticket", required=True)
    r.add_argument("--outcome", required=True)
    for flag in ("--run-ledger", "--base-sha", "--base-ref", "--branch", "--spec", "--started", "--harness",
                 "--model", "--effort", "--dispatch", "--ci", "--live", "--layer", "--ac", "--usage-json",
                 "--repo", "--out", "--now"):
        r.add_argument(flag)
    r.add_argument("--pr", type=int)
    r.add_argument("--no-measure", action="store_true")
    r.add_argument("--dry-run", action="store_true")
    d = sub.add_parser("dispatch-usage")
    d.add_argument("--harness", required=True)
    d.add_argument("--since", required=True)
    d.add_argument("--until", required=True)
    for flag in ("--cwd", "--output", "--export", "--ticket", "--run", "--now"):
        d.add_argument(flag)
    d.add_argument("--iter", type=int)
    d.add_argument("--exit-code", type=int)
    t = sub.add_parser("result")
    t.add_argument("--harness", required=True)
    t.add_argument("--output", required=True)
    a = ap.parse_args(argv)
    if a.cmd == "record":
        return cmd_record(a)
    if a.cmd == "dispatch-usage":
        return cmd_dispatch_usage(a)
    if a.cmd == "result":
        return cmd_result(a)
    ap.print_help(sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
