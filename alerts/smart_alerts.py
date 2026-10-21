#!/usr/bin/env python3
"""resurrect smart alerts: watch sources, let an LLM pick what matters,
push the results to ntfy. Standard library only (Python 3.11+).

A job is one TOML file (see alerts/examples/). Two kinds:

  digest  Collect items from RSS/Atom feeds, JSON APIs or web pages, drop the
          ones already seen, ask the LLM to score each new item against your
          prompt, and send the ones scoring >= min_score.
  watch   Track one value on a page (a price, a stock level...). Extract it
          with a regex or, if none is given, with the LLM. Alert when the
          condition is met (drop by N %, below a target, any change).

Usage:
  smart_alerts.py run JOB.toml [--dry-run] [--no-llm]
  smart_alerts.py test JOB.toml          fetch + parse only, print items
  smart_alerts.py list DIR
  smart_alerts.py cron-lines DIR "REZ_CMD"

The LLM endpoint is any OpenAI-compatible /chat/completions API: OpenAI,
OpenRouter, Groq, a local llama.cpp/Ollama server... Your key, your bill.
"""
from __future__ import annotations

import hashlib
import html
import html.parser
import json
import os
import re
import sqlite3
import sys
import time
import tomllib
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

UA = "resurrect-smart-alerts/0.1"
MAX_TEXT = 1200          # characters of each item sent to the LLM
MAX_ITEMS_PER_CALL = 25  # items per LLM request
TIMEOUT = 30


# ---------------------------------------------------------------- config ---

def rez_paths():
    home = Path.home()
    cfg = Path(os.environ.get("REZ_CONFIG_DIR", home / ".config/resurrect"))
    state = Path(os.environ.get("REZ_STATE_DIR", home / ".local/state/resurrect"))
    return cfg, state


def rez_cfg(key, default=""):
    env = "REZ_CFG_" + re.sub(r"[.-]", "_", key)
    if env in os.environ:
        return os.environ[env]
    cfg, _ = rez_paths()
    f = cfg / "resurrect.conf"
    val = default
    try:
        for line in f.read_text().splitlines():
            if line.lstrip().startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            if k.strip() == key:
                val = v.strip()
    except OSError:
        pass
    return val


def read_secret(spec: dict, prefix: str = "api_key"):
    """api_key_file / api_key_env / api_key (discouraged) / default secret."""
    if spec.get(f"{prefix}_env"):
        return os.environ.get(spec[f"{prefix}_env"], "")
    path = spec.get(f"{prefix}_file")
    if not path:
        cfg, _ = rez_paths()
        path = str(cfg / "secrets" / "alerts_api_key")
    try:
        return Path(os.path.expanduser(path)).read_text().strip()
    except OSError:
        return spec.get(prefix, "")


# ---------------------------------------------------------------- fetch ----

def http_get(url, headers=None, timeout=TIMEOUT) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA, **(headers or {})})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read(5_000_000)


def http_post_json(url, payload, headers, timeout=120):
    data = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data, method="POST", headers={
        "User-Agent": UA, "Content-Type": "application/json", **headers})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


class _Text(html.parser.HTMLParser):
    """HTML to readable text, keeping links."""
    SKIP = {"script", "style", "noscript", "svg", "head"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out, self.skip, self.links = [], 0, []

    def handle_starttag(self, tag, attrs):
        if tag in self.SKIP:
            self.skip += 1
        elif tag in ("p", "div", "li", "br", "tr", "h1", "h2", "h3", "h4", "article", "section"):
            self.out.append("\n")
        if tag == "a":
            href = dict(attrs).get("href")
            if href:
                self.links.append(href)

    def handle_endtag(self, tag):
        if tag in self.SKIP and self.skip:
            self.skip -= 1

    def handle_data(self, data):
        if not self.skip:
            self.out.append(data)


def html_to_text(raw: str) -> str:
    p = _Text()
    p.feed(raw)
    text = "".join(p.out)
    text = re.sub(r"[ \t\r\f\v]+", " ", text)
    return re.sub(r"\n\s*\n+", "\n", text).strip()


@dataclass
class Item:
    id: str
    title: str
    link: str = ""
    text: str = ""
    source: str = ""
    extra: dict = field(default_factory=dict)


def _strip_ns(tag):
    return tag.rsplit("}", 1)[-1]


def parse_feed(raw: bytes, source: str) -> list[Item]:
    root = ET.fromstring(raw)
    items = []
    for el in root.iter():
        name = _strip_ns(el.tag)
        if name not in ("item", "entry"):
            continue
        fields = {}
        link = ""
        for c in el:
            cn = _strip_ns(c.tag)
            if cn == "link":
                link = c.get("href") or (c.text or "").strip() or link
            elif c.text:
                fields.setdefault(cn, c.text.strip())
        title = html.unescape(fields.get("title", "(no title)"))
        body = fields.get("description") or fields.get("summary") or fields.get("content") or ""
        uid = fields.get("guid") or fields.get("id") or link or title
        items.append(Item(id=uid, title=title, link=link, text=html_to_text(body), source=source))
    return items


def dig(obj, path: str):
    """'data.items' / 'results.0.title' lookup."""
    for part in [p for p in path.split(".") if p]:
        if isinstance(obj, list):
            obj = obj[int(part)] if part.isdigit() and int(part) < len(obj) else None
        elif isinstance(obj, dict):
            obj = obj.get(part)
        else:
            return None
    return obj


def parse_json_api(raw: bytes, src: dict) -> list[Item]:
    data = json.loads(raw)
    arr = dig(data, src.get("items", "")) if src.get("items") else data
    if not isinstance(arr, list):
        raise ValueError(f"'items' path {src.get('items')!r} is not a list")
    f = {"id": "id", "title": "title", "link": "url", "text": "description", **src.get("fields", {})}
    out = []
    for obj in arr:
        title = str(dig(obj, f["title"]) or "(no title)")
        link = str(dig(obj, f["link"]) or "")
        uid = str(dig(obj, f["id"]) or link or title)
        text = dig(obj, f["text"]) or ""
        if not isinstance(text, str):
            text = json.dumps(text)
        out.append(Item(id=uid, title=title, link=link, text=html_to_text(text), source=src.get("name", src["url"])))
    return out


def parse_web(raw: bytes, src: dict) -> list[Item]:
    text = html_to_text(raw.decode("utf-8", errors="replace"))
    if src.get("start_marker") and src["start_marker"] in text:
        text = text.split(src["start_marker"], 1)[1]
    if src.get("end_marker") and src["end_marker"] in text:
        text = text.split(src["end_marker"], 1)[0]
    if src.get("item_regex"):
        out = []
        for m in re.finditer(src["item_regex"], text, re.M | re.S):
            chunk = m.group(0).strip()
            title = (m.groupdict().get("title") or chunk.splitlines()[0])[:200]
            out.append(Item(id=hashlib.sha1(chunk.encode()).hexdigest(), title=title,
                            link=src["url"], text=chunk, source=src.get("name", src["url"])))
        return out
    # Whole page as one item; its id changes when the content changes.
    return [Item(id=hashlib.sha1(text.encode()).hexdigest(), title=src.get("name", src["url"]),
                 link=src["url"], text=text, source=src.get("name", src["url"]))]


def fetch_source(src: dict) -> list[Item]:
    kind = src.get("type", "rss")
    raw = http_get(src["url"], headers=src.get("headers"))
    if kind in ("rss", "atom", "feed"):
        items = parse_feed(raw, src.get("name", src["url"]))
    elif kind == "json":
        items = parse_json_api(raw, src)
    elif kind == "web":
        items = parse_web(raw, src)
    else:
        raise ValueError(f"unknown source type {kind!r}")
    inc = [w.lower() for w in src.get("include", [])]
    exc = [w.lower() for w in src.get("exclude", [])]
    if inc or exc:
        def keep(it):
            blob = f"{it.title} {it.text}".lower()
            return (not inc or any(w in blob for w in inc)) and not any(w in blob for w in exc)
        items = [i for i in items if keep(i)]
    return items[: int(src.get("max_items", 100))]


# ---------------------------------------------------------------- state ----

class State:
    def __init__(self, path: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(path)
        self.db.execute("CREATE TABLE IF NOT EXISTS seen (job TEXT, id TEXT, ts INTEGER, PRIMARY KEY (job, id))")
        self.db.execute("CREATE TABLE IF NOT EXISTS kv (job TEXT, k TEXT, v TEXT, PRIMARY KEY (job, k))")

    def seen(self, job, iid):
        return self.db.execute("SELECT 1 FROM seen WHERE job=? AND id=?", (job, iid)).fetchone() is not None

    def mark(self, job, ids):
        now = int(time.time())
        self.db.executemany("INSERT OR IGNORE INTO seen VALUES (?, ?, ?)", [(job, i, now) for i in ids])
        # Forget ids after 180 days so the table stays small.
        self.db.execute("DELETE FROM seen WHERE ts < ?", (now - 180 * 86400,))
        self.db.commit()

    def get(self, job, k, default=None):
        r = self.db.execute("SELECT v FROM kv WHERE job=? AND k=?", (job, k)).fetchone()
        return r[0] if r else default

    def put(self, job, k, v):
        self.db.execute("INSERT OR REPLACE INTO kv VALUES (?, ?, ?)", (job, k, str(v)))
        self.db.commit()


# ------------------------------------------------------------------ LLM ----

SYSTEM_DIGEST = """You filter items for one person. Their instructions follow.
Score every item from 0 (irrelevant) to 10 (exactly what they want).
Reply with JSON only, no prose, in this shape:
{"items": [{"id": "<id>", "score": <0-10>, "summary": "<one sentence why it matters>"}]}"""

SYSTEM_EXTRACT = """Extract one value from the page text, following the instructions.
Reply with JSON only: {"value": <number or null>, "note": "<short context>"}"""


def llm_chat(llm: dict, system: str, user: str) -> dict:
    base = llm.get("base_url", "https://api.openai.com/v1").rstrip("/")
    key = read_secret(llm)
    headers = {"Authorization": f"Bearer {key}"} if key else {}
    headers.update(llm.get("headers", {}))
    payload = {
        "model": llm.get("model", "gpt-4o-mini"),
        "temperature": llm.get("temperature", 0),
        "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
    }
    if llm.get("json_mode", True):
        payload["response_format"] = {"type": "json_object"}
    resp = http_post_json(base + "/chat/completions", payload, headers)
    content = resp["choices"][0]["message"]["content"]
    m = re.search(r"\{.*\}", content, re.S)  # tolerate ```json fences
    if not m:
        raise ValueError(f"LLM reply is not JSON: {content[:200]!r}")
    return json.loads(m.group(0))


def score_items(job: dict, items: list[Item], no_llm=False) -> list[tuple[Item, int, str]]:
    if no_llm:
        return [(it, 10, "") for it in items]
    by_id = {}
    results = []
    for start in range(0, len(items), MAX_ITEMS_PER_CALL):
        batch = items[start:start + MAX_ITEMS_PER_CALL]
        listing = []
        for n, it in enumerate(batch):
            key = f"i{start + n}"
            by_id[key] = it
            listing.append({"id": key, "title": it.title, "source": it.source, "text": it.text[:MAX_TEXT]})
        user = f"Instructions:\n{job['llm']['prompt'].strip()}\n\nItems:\n{json.dumps(listing, ensure_ascii=False)}"
        reply = llm_chat(job["llm"], SYSTEM_DIGEST, user)
        for r in reply.get("items", []):
            it = by_id.get(str(r.get("id")))
            if it is not None:
                try:
                    score = int(float(r.get("score", 0)))
                except (TypeError, ValueError):
                    score = 0
                results.append((it, score, str(r.get("summary", ""))[:300]))
    return results


# ----------------------------------------------------------------- ntfy ----

def ntfy_send(title, message, priority=3, tags="", click="", dry_run=False):
    url = rez_cfg("ntfy.url").rstrip("/")
    topic = rez_cfg("ntfy.topic")
    if dry_run or not url or not topic:
        print(f"--- ntfy {'(dry run)' if dry_run else '(not configured)'}: {title}\n{message}\n")
        return
    cfg, _ = rez_paths()
    headers = {"User-Agent": UA, "Title": title.encode("utf-8").decode("latin-1", "replace"),
               "Priority": str(priority)}
    if tags:
        headers["Tags"] = tags
    if click:
        headers["Click"] = click
    try:
        headers["Authorization"] = "Bearer " + (cfg / "secrets/ntfy_publish_token").read_text().strip()
    except OSError:
        pass
    req = urllib.request.Request(f"{url}/{topic}", data=message.encode(), method="POST", headers=headers)
    urllib.request.urlopen(req, timeout=TIMEOUT).read()


# ------------------------------------------------------------------ jobs ---

def load_job(path: str) -> dict:
    with open(path, "rb") as fh:
        job = tomllib.load(fh)
    job.setdefault("name", Path(path).stem)
    job.setdefault("kind", "digest")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", job["name"]):
        raise ValueError("job name may only contain letters, digits, . _ -")
    if job["kind"] == "digest":
        if not job.get("sources"):
            raise ValueError("a digest job needs at least one [[sources]] entry")
        if "prompt" not in job.get("llm", {}):
            raise ValueError("a digest job needs llm.prompt")
    elif job["kind"] == "watch":
        if "watch" not in job or "url" not in job["watch"]:
            raise ValueError("a watch job needs [watch] with url")
    else:
        raise ValueError(f"unknown kind {job['kind']!r}")
    return job


def run_digest(job, state: State, dry_run=False, no_llm=False):
    name = job["name"]
    items, errors = [], []
    for src in job["sources"]:
        try:
            items.extend(fetch_source(src))
        except (OSError, ValueError, ET.ParseError, urllib.error.URLError) as e:
            errors.append(f"{src.get('name', src.get('url'))}: {e}")
    new = [it for it in items if not state.seen(name, it.id)]
    # Same id from two feeds: keep one.
    uniq = {}
    for it in new:
        uniq.setdefault(it.id, it)
    new = list(uniq.values())
    print(f"{name}: {len(items)} items, {len(new)} new, {len(errors)} source errors")
    for e in errors:
        print(f"  source error: {e}", file=sys.stderr)
    if errors and len(errors) == len(job["sources"]):
        raise RuntimeError("every source failed: " + "; ".join(errors))
    if not new:
        return
    if state.get(name, "initialized") is None and job.get("skip_backlog", True):
        # First run: remember what exists today instead of alerting on the backlog.
        if not dry_run:
            state.mark(name, [it.id for it in new])
            state.put(name, "initialized", int(time.time()))
        print(f"{name}: first run, {len(new)} existing items marked as seen (skip_backlog)")
        return
    scored = score_items(job, new, no_llm=no_llm)
    out = job.get("output", {})
    min_score = int(job.get("llm", {}).get("min_score", 7))
    hits = sorted([s for s in scored if s[1] >= min_score], key=lambda s: -s[1])
    hits = hits[: int(out.get("max_alerts", 5))]
    title = out.get("title", name)
    for it, score, summary in hits:
        body = f"{it.title}\n{summary}".strip() + (f"\n{it.link}" if it.link else "")
        ntfy_send(f"{title} ({score}/10)", body, out.get("priority", 3), out.get("tags", ""), it.link, dry_run)
    print(f"{name}: {len(hits)} alert(s) sent")
    if not dry_run:
        state.mark(name, [it.id for it in new])
        state.put(name, "initialized", int(time.time()))


def run_watch(job, state: State, dry_run=False, no_llm=False):
    name, w = job["name"], job["watch"]
    raw = http_get(w["url"], headers=w.get("headers")).decode("utf-8", errors="replace")
    text = html_to_text(raw)
    value, note = None, ""
    if w.get("regex"):
        m = re.search(w["regex"], text) or re.search(w["regex"], raw)
        if m:
            value = float(re.sub(r"[^\d.]", "", m.group(1).replace(",", "")))
    if value is None and not no_llm and job.get("llm"):
        reply = llm_chat(job["llm"], SYSTEM_EXTRACT,
                         f"Instructions:\n{job['llm'].get('prompt', 'Find the current price.')}\n\nPage text:\n{text[:6000]}")
        if reply.get("value") is not None:
            value, note = float(reply["value"]), str(reply.get("note", ""))
    if value is None:
        raise RuntimeError("could not find the value on the page (check watch.regex or llm.prompt)")
    prev = state.get(name, "value")
    print(f"{name}: value {value} (previous {prev})")
    cond = w.get("alert_when", "drop")
    fire, why = False, ""
    if prev is not None:
        prev = float(prev)
        if cond == "drop" and prev > 0 and (prev - value) / prev * 100 >= float(w.get("min_drop_pct", 5)):
            fire, why = True, f"dropped {prev:g} -> {value:g} ({(prev - value) / prev * 100:.1f}%)"
        elif cond == "change" and value != prev:
            fire, why = True, f"changed {prev:g} -> {value:g}"
    if cond == "below" and value <= float(w["target"]) and (prev is None or float(prev) > float(w["target"])):
        fire, why = True, f"now {value:g}, at or below your target {w['target']}"
    if fire:
        out = job.get("output", {})
        ntfy_send(out.get("title", name), f"{why}\n{note}\n{w['url']}".replace("\n\n", "\n"),
                  out.get("priority", 4), out.get("tags", "moneybag"), w["url"], dry_run)
    if not dry_run:
        state.put(name, "value", value)


def cmd_run(path, dry_run=False, no_llm=False):
    job = load_job(path)
    _, state_dir = rez_paths()
    state = State(state_dir / "alerts.db")
    name = job["name"]
    try:
        (run_digest if job["kind"] == "digest" else run_watch)(job, state, dry_run, no_llm)
        state.put(name, "failures", 0)
    except Exception as e:  # noqa: BLE001 - report every failure through ntfy
        n = int(state.get(name, "failures", 0)) + 1
        state.put(name, "failures", n)
        print(f"{name}: FAILED ({n} in a row): {e}", file=sys.stderr)
        if n == 3:
            ntfy_send(f"Smart alert '{name}' is failing", f"3 runs in a row failed. Last error: {e}", 4, "warning",
                      dry_run=dry_run)
        return 1
    return 0


def cmd_test(path):
    job = load_job(path)
    print(f"job {job['name']} ({job['kind']}) is valid")
    if job["kind"] == "watch":
        raw = http_get(job["watch"]["url"]).decode("utf-8", errors="replace")
        print(html_to_text(raw)[:1500])
        return 0
    for src in job["sources"]:
        try:
            items = fetch_source(src)
        except Exception as e:  # noqa: BLE001
            print(f"  {src.get('name', src['url'])}: ERROR {e}")
            continue
        print(f"  {src.get('name', src['url'])}: {len(items)} items")
        for it in items[:5]:
            print(f"    - {it.title[:90]}")
    return 0


def iter_jobs(d):
    for p in sorted(Path(d).glob("*.toml")):
        try:
            yield p, load_job(str(p))
        except Exception as e:  # noqa: BLE001
            print(f"{p.name}: invalid: {e}", file=sys.stderr)


CRON_RX = re.compile(r"^(\S+\s+){4}\S+$")


def cmd_list(d):
    for p, job in iter_jobs(d):
        print(f"{job['name']:<20} {'on ' if job.get('enabled') else 'off'}  {job.get('schedule', '-'):<16} {job['kind']}  {p.name}")
    return 0


def cmd_cron_lines(d, rez_cmd, log_dir):
    for p, job in iter_jobs(d):
        if not job.get("enabled"):
            continue
        sched = job.get("schedule", "")
        if not CRON_RX.match(sched):
            print(f"{p.name}: invalid schedule {sched!r}, skipped", file=sys.stderr)
            continue
        print(f"{sched} {rez_cmd} alerts run {job['name']} >>{log_dir}/alerts.log 2>&1")
    return 0


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd, arg = argv[0], argv[1]
    flags = set(argv[2:])
    if cmd == "run":
        return cmd_run(arg, "--dry-run" in flags, "--no-llm" in flags)
    if cmd == "test":
        return cmd_test(arg)
    if cmd == "list":
        return cmd_list(arg)
    if cmd == "cron-lines":
        return cmd_cron_lines(arg, argv[2], argv[3] if len(argv) > 3 else "/tmp")
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
