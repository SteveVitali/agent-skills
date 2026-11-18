#!/usr/bin/env python3
"""build-trace.py — the per-ticket trace record (BM-TRACE-01): one JSON line per worker attempt.

A trace line is the machine-readable twin of a run ledger's header: which ticket, at which base and head commit,
by which harness / model / effort / dispatch tier, with which skills version, how long it took, how many tokens it
used (measured from the harness's own transcript where the harness exposes one, never invented) and how its
verification ended. It is appended to <memoryRoot>/runs/<ID>.trace.jsonl in the ticket's closeout commit, so a
later evaluation (replaying tickets at their base commit under other configurations, audit-build's evaluate mode,
cost analysis) reads it directly instead of mining transcripts.

Usage:
  build-trace.py record --ticket ID --outcome done|blocked|gate-pending|abandoned [options]
      Append one line to <memoryRoot>/runs/<ID>.trace.jsonl (or --out FILE) and print it.
      --run-ledger PATH   read Started:, Harness:, Base:, Spec: and ci: from this run ledger's header
                          (default: <memoryRoot>/runs/<ID>.md when it exists); flags below override it
      --base-sha SHA | --base-ref REF   the commit the branch was cut from (REF → git merge-base HEAD REF)
      --pr N  --branch NAME  --spec PATH  --started ISO
      --harness NAME  --model ID  --effort LEVEL  --dispatch headless|subagent|manual
      --ci "LINE"  --live LAYER  --layer WORD  --ac met=N,met-engineered=N,partial=N,missed=N
      --usage-json FILE   usage measured elsewhere (source "supplied"); skips transcript measurement
      --no-measure        record usage as not-measured
      --repo DIR  --out FILE  --now ISO  --dry-run (print, do not write)
  build-trace.py stream-usage FILE [--ticket ID] [--iter N] [--run ID] [--now ISO]
      Print one dispatch-usage JSON line from a `claude -p --output-format stream-json` capture
      (orchestrate-build's drive-build.sh appends it to its gitignored logs/drive-build/usage.jsonl).
  build-trace.py stream-result FILE
      Print the final result text of such a capture (what `claude -p` prints in text mode).

Measurement (record): the harness is read from its environment, never assumed.
  Claude Code  CLAUDE_CODE_SESSION_ID → <CLAUDE_CONFIG_DIR|~/.claude>/projects/*/<id>.jsonl (+ <id>/subagents/).
               The worker is the transcript holding this very `build-trace.py record --ticket <ID>` call: a subagent
               transcript → that agent and its descendants (meta.json parentAgentId); the session's main transcript
               → the whole session; neither → every line of the session on this branch. Effort: CLAUDE_EFFORT.
               The harness writes the call to its transcript a moment after it starts, so the script polls for
               it for up to BUILD_TRACE_WAIT_S seconds (default 30) before falling back.
  Codex        CODEX_THREAD_ID → <CODEX_HOME|~/.codex>/sessions/**/rollout-*-<id>.jsonl plus the threads it spawned
               (parent_thread_id); model and effort from its turn_context.
  Otherwise    usage is "not-measured" (pass --usage-json when another source measured it); harness, model and
               effort come from the flags or the run ledger's `Harness: <harness>/<model-id>/<tier>` line.
Usage counts what the transcripts hold when the record is written (the closeout's own last turns are not in it).
`input_tokens` is every prompt token (uncached + cache read + cache write) for both providers, so totals compare.

Exit codes: 0 written / printed · 1 usage error · 2 cannot resolve the repo, the memory root or the input file.
Stdlib only; run with `python3 -I`. Writes only the trace file (record) — nothing with the stream modes.
"""
import argparse
import datetime as dt
import glob
import json
import os
import re
import subprocess
import sys
import time

SCHEMA = "build-trace/1"
DISPATCH_SCHEMA = "build-dispatch/1"
OUTCOMES = ("done", "blocked", "gate-pending", "abandoned")
DISPATCHES = ("headless", "subagent", "manual", "unknown")
LIVE = ("live-executed", "staging", "fixture-only", "engineered", "n-a", "gate-pending")
EFFORT_SUFFIX = re.compile(r"^(?P<model>.+)-(?P<effort>minimal|low|medium|high|xhigh|max|ultra)$")
TICKET_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
HERE = os.path.dirname(os.path.abspath(__file__))


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
    return None


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
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except ValueError:
                    continue
                if isinstance(obj, dict):
                    yield obj
    except OSError:
        return


def as_int(v):
    return v if isinstance(v, int) and not isinstance(v, bool) else 0


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


# ── harness detection ───────────────────────────────────────────────────────────────────────────
def split_label(label):
    """`devin-desktop/swe-2-high/subagent` → (harness, model, tier); missing parts are None."""
    parts = (label or "").strip().split("/")
    parts += [None] * (3 - len(parts))
    return tuple(p or None for p in parts[:3])


def claude_version():
    agent = os.environ.get("AI_AGENT", "")
    m = re.match(r"^claude-code_([0-9][0-9-]*)", agent)
    if m:
        return m.group(1).replace("-", ".")
    m = re.search(r"/versions/([0-9][0-9.]*)$", os.environ.get("CLAUDE_CODE_EXECPATH", ""))
    return m.group(1) if m else None


# ── Claude Code transcripts ─────────────────────────────────────────────────────────────────────
class Tally:
    def __init__(self):
        self.calls = {}          # message id → (model, usage dict)
        self.compactions = 0
        self.files = 0           # transcripts that contributed a call or a compaction

    def add_call(self, key, model, usage):
        self.calls[key] = (model, usage)


def claude_usage_of(u):
    raw = as_int(u.get("input_tokens"))
    cr = as_int(u.get("cache_read_input_tokens"))
    cw = as_int(u.get("cache_creation_input_tokens"))
    out = as_int(u.get("output_tokens"))
    det = u.get("output_tokens_details")
    think = det.get("thinking_tokens") if isinstance(det, dict) else None
    return {"uncached": raw, "cache_read": cr, "cache_write": cw, "output": out,
            "reasoning": think if isinstance(think, int) else None}


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


def tool_call_marks(path, ticket):
    """Latest timestamp of an assistant tool_use in `path` that ran `build-trace.py record` for `ticket`."""
    latest = None
    pat = re.compile(r"--ticket[= ]+[\"']?" + re.escape(ticket) + r"(?![A-Za-z0-9._-])")
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
            if isinstance(text, str) and "build-trace.py" in text and " record" in text and pat.search(text):
                ts = obj.get("timestamp") or ""
                if latest is None or ts > latest:
                    latest = ts
    return latest


def measure_claude(session_id, ticket, branch):
    conf = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")
    hits = sorted(glob.glob(os.path.join(conf, "projects", "*", session_id + ".jsonl")))
    if not hits:
        return None, "no transcript for CLAUDE_CODE_SESSION_ID under %s/projects" % conf
    main = hits[0]
    subdir = os.path.join(main[:-len(".jsonl")], "subagents")
    agents = {}  # agent id → (path, parent id)
    for p in sorted(glob.glob(os.path.join(subdir, "agent-*.jsonl"))):
        aid = os.path.basename(p)[len("agent-"):-len(".jsonl")]
        parent = None
        try:
            with open(p[:-len(".jsonl")] + ".meta.json", encoding="utf-8") as fh:
                parent = (json.load(fh) or {}).get("parentAgentId")
        except (OSError, ValueError):
            pass
        agents[aid] = (p, parent)

    # The harness writes this very call to its transcript asynchronously (observed: 0.2–3 s after the command
    # starts), so poll the recently written transcripts for it, then fall back to one scan of them all.
    owners = [(main, None)] + [(p, aid) for aid, (p, _) in sorted(agents.items())]
    try:
        wait = float(os.environ.get("BUILD_TRACE_WAIT_S", "30"))
    except ValueError:
        wait = 30.0
    deadline = time.time() + wait
    marks = []
    while True:
        now = time.time()
        for p, aid in owners:
            try:
                if now - os.path.getmtime(p) > 600:
                    continue
            except OSError:
                continue
            ts = tool_call_marks(p, ticket)
            if ts is not None:
                marks.append((ts, aid))
        if marks or now >= deadline:
            break
        time.sleep(0.25)
    if not marks:
        for p, aid in owners:
            ts = tool_call_marks(p, ticket)
            if ts is not None:
                marks.append((ts, aid))
    tally = Tally()
    info = {}
    if marks:
        marks.sort(key=lambda m: (m[0], m[1] is None))
        root = marks[-1][1]
    else:
        root = "branch"
    if root is None:                       # the session itself is the worker (headless / manual)
        scope = "session"
        scan_claude_file(main, tally)
        for aid, (p, _) in sorted(agents.items()):
            scan_claude_file(p, tally)
    elif root == "branch":                 # the call was not found: every line of the session on this branch
        scope = "branch"
        scan_claude_file(main, tally, branch=branch)
        for aid, (p, _) in sorted(agents.items()):
            scan_claude_file(p, tally, branch=branch)
    else:                                  # a subagent is the worker: it and its descendants
        scope = "agent-tree"
        info["agent_id"] = root
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
    return finish_usage("claude-code-transcript", scope, tally), info


# ── Codex rollouts ──────────────────────────────────────────────────────────────────────────────
def first_meta(path):
    for obj in read_jsonl(path):
        if obj.get("type") == "session_meta":
            return obj.get("payload") or {}
        return {}
    return {}


def measure_codex(thread_id):
    home = os.environ.get("CODEX_HOME") or os.path.join(os.path.expanduser("~"), ".codex")
    files = sorted(glob.glob(os.path.join(home, "sessions", "**", "rollout-*.jsonl"), recursive=True))
    root = [f for f in files if f.endswith("-" + thread_id + ".jsonl")]
    if not root:
        return None, "no rollout for CODEX_THREAD_ID under %s/sessions" % home, {}
    root = root[0]
    later = [f for f in files if os.path.basename(f) >= os.path.basename(root)[:len("rollout-YYYY-MM-DDTHH-MM-SS")]]
    parent_of = {}
    for f in later:
        meta = first_meta(f)
        if meta.get("id"):
            parent_of[meta["id"]] = (f, meta.get("parent_thread_id"))
    tree = {thread_id}
    grew = True
    while grew:
        grew = False
        for tid, (_, parent) in parent_of.items():
            if tid not in tree and parent in tree:
                tree.add(tid)
                grew = True
    tally = Tally()
    ctx = {}
    paths = [root] + sorted(parent_of[t][0] for t in tree if t != thread_id and t in parent_of)
    for f in paths:
        tally.files += 1
        model = None
        last_total = None
        peak = 0
        ncalls = 0
        for obj in read_jsonl(f):
            typ = obj.get("type")
            p = obj.get("payload") or {}
            if typ == "turn_context":
                model = model or p.get("model")
                if f == root and not ctx:
                    ctx = {"model": p.get("model"), "effort": p.get("effort") or p.get("reasoning_effort")}
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
        if last_total:
            inp = as_int(last_total.get("input_tokens"))
            cr = as_int(last_total.get("cached_input_tokens"))
            cw = as_int(last_total.get("cache_write_input_tokens"))
            rs = last_total.get("reasoning_output_tokens")
            # Codex counts cached tokens inside input_tokens; split them out so the totals compare with Claude's.
            u = {"uncached": max(0, inp - cr - cw), "cache_read": cr, "cache_write": cw,
                 "output": as_int(last_total.get("output_tokens")), "reasoning": rs if isinstance(rs, int) else None,
                 "calls": ncalls, "peak": peak}
            tally.add_call(f, model or "unknown", u)
    return finish_usage("codex-rollout", "thread-tree", tally), None, ctx


# ── normalized usage ────────────────────────────────────────────────────────────────────────────
def finish_usage(source, scope, tally):
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
        if u["reasoning"] is not None:
            tot["reasoning_tokens"] = (tot["reasoning_tokens"] or 0) + u["reasoning"]
        tot["peak_context_tokens"] = max(tot["peak_context_tokens"], peak)
        m = by_model.setdefault(model, {"model_calls": 0, "input_tokens": 0, "cache_read_tokens": 0,
                                        "cache_write_tokens": 0, "output_tokens": 0})
        m["model_calls"] += calls
        m["input_tokens"] += prompt
        m["cache_read_tokens"] += u["cache_read"]
        m["cache_write_tokens"] += u["cache_write"]
        m["output_tokens"] += u["output"]
    out = {"source": source, "scope": scope, "transcripts": tally.files}
    out.update(tot)
    out["compactions"] = tally.compactions
    out["by_model"] = by_model
    return out


def not_measured(reason):
    return {"source": "not-measured", "reason": reason}


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
    if not out:
        mode, root = memory_root(repo)
        if mode != "committed" or not root:
            die(2, "no committed build-memory root for %s (scratch mode): pass --out FILE" % repo)
        out = os.path.join(root, "runs", a.ticket + ".trace.jsonl")
        rl_default = os.path.join(root, "runs", a.ticket + ".md")
    else:
        rl_default = None
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

    # Harness / model / effort / dispatch: the environment first, then flags, then the run ledger's label.
    label = hdr.get("harness")
    l_h, l_m, l_t = split_label(label)
    sid = os.environ.get("CLAUDE_CODE_SESSION_ID")
    tid = os.environ.get("CODEX_THREAD_ID")
    harness = {"label": label, "name": a.harness or l_h, "version": None, "detected_from": None}
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
    if sid:
        harness.update(name=a.harness or "claude-code", version=claude_version(), detected_from="CLAUDE_CODE_SESSION_ID")
        if not effort and os.environ.get("CLAUDE_EFFORT"):
            effort, effort_src = os.environ["CLAUDE_EFFORT"], "CLAUDE_EFFORT"
        session = {"id": sid}
        if usage is None and not a.no_measure:
            usage, info = measure_claude(sid, a.ticket, branch)
            if usage is None:
                usage = not_measured(info)
            else:
                session.update(info)
                if not model and usage.get("by_model"):
                    model = max(usage["by_model"].items(), key=lambda kv: kv[1]["output_tokens"])[0]
    elif tid:
        harness.update(name=a.harness or "codex", detected_from="CODEX_THREAD_ID")
        session = {"id": tid}
        if usage is None and not a.no_measure:
            usage, err, ctx = measure_codex(tid)
            if usage is None:
                usage = not_measured(err)
            else:
                model = model or ctx.get("model")
                if not effort and ctx.get("effort"):
                    effort, effort_src = ctx["effort"], "turn_context"
    if not model and l_m:
        model = l_m
    if not effort and model:
        m = EFFORT_SUFFIX.match(model)
        if m:
            effort, effort_src = m.group("effort"), "model-suffix"
    if usage is None:
        usage = not_measured("--no-measure" if a.no_measure else
                             "the harness exposes no transcript to this script (pass --usage-json)")
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
    line = json.dumps(rec, ensure_ascii=False, separators=(",", ":"), sort_keys=False)
    if not a.dry_run:
        os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
        if os.path.isfile(out) and os.path.getsize(out) > 0:
            with open(out, "rb") as fh:
                fh.seek(-1, os.SEEK_END)
                needs_nl = fh.read(1) != b"\n"
        else:
            needs_nl = False
        with open(out, "a", encoding="utf-8") as fh:
            fh.write(("\n" if needs_nl else "") + line + "\n")
        sys.stderr.write("build-trace: appended attempt %d to %s (usage: %s)\n" % (attempt, out, usage["source"]))
    print(line)
    return 0


# ── stream modes (drive-build.sh) ───────────────────────────────────────────────────────────────
def stream_events(path):
    if not os.path.isfile(path):
        die(2, "no such stream capture: %s" % path)
    return list(read_jsonl(path))


def cmd_stream_usage(a):
    ev = stream_events(a.file)
    init = next((e for e in ev if e.get("type") == "system" and e.get("subtype") == "init"), {})
    res = next((e for e in reversed(ev) if e.get("type") == "result"), None)
    rec = {"schema": DISPATCH_SCHEMA, "recorded_at": now_iso(a.now), "ticket": a.ticket, "iter": a.iter,
           "run": a.run, "source": "claude-stream", "session_id": (res or init).get("session_id"),
           "model": init.get("model"), "complete": res is not None}
    if res is not None:
        u = claude_usage_of(res.get("usage") or {})
        rec.update({
            "subtype": res.get("subtype"), "is_error": res.get("is_error"), "num_turns": res.get("num_turns"),
            "duration_ms": res.get("duration_ms"), "duration_api_ms": res.get("duration_api_ms"),
            "total_cost_usd": res.get("total_cost_usd"),
            "usage": {"input_tokens": u["uncached"] + u["cache_read"] + u["cache_write"],
                      "uncached_input_tokens": u["uncached"], "cache_read_tokens": u["cache_read"],
                      "cache_write_tokens": u["cache_write"], "output_tokens": u["output"]},
            "by_model": res.get("modelUsage") if isinstance(res.get("modelUsage"), dict) else None,
        })
    print(json.dumps(rec, ensure_ascii=False, separators=(",", ":")))
    return 0


def cmd_stream_result(a):
    ev = stream_events(a.file)
    res = next((e for e in reversed(ev) if e.get("type") == "result"), None)
    if res is not None and isinstance(res.get("result"), str):
        print(res["result"])
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
    s = sub.add_parser("stream-usage")
    s.add_argument("file")
    s.add_argument("--ticket")
    s.add_argument("--iter", type=int)
    s.add_argument("--run")
    s.add_argument("--now")
    t = sub.add_parser("stream-result")
    t.add_argument("file")
    a = ap.parse_args(argv)
    if a.cmd == "record":
        return cmd_record(a)
    if a.cmd == "stream-usage":
        return cmd_stream_usage(a)
    if a.cmd == "stream-result":
        return cmd_stream_result(a)
    ap.print_help(sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
