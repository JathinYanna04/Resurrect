"""Smart alerts: parsing, dedupe, LLM scoring and ntfy delivery against a
local mock server (no network, no real API key). Run:
    python3 -m unittest discover -s tests/python
"""
import importlib.util
import json
import os
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("smart_alerts", REPO / "alerts/smart_alerts.py")
sa = importlib.util.module_from_spec(spec)
sys.modules["smart_alerts"] = sa  # dataclasses look the module up while it loads
spec.loader.exec_module(sa)

RSS = b"""<?xml version="1.0"?><rss version="2.0"><channel><title>Jobs</title>
<item><title>Backend Engineer (Python)</title><link>https://jobs.example.com/1</link>
<guid>job-1</guid><description>&lt;p&gt;Remote, junior friendly&lt;/p&gt;</description></item>
<item><title>Senior Staff Sales Lead</title><link>https://jobs.example.com/2</link>
<guid>job-2</guid><description>10+ years sales</description></item>
</channel></rss>"""

ATOM = b"""<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"><title>arXiv</title>
<entry><id>http://arxiv.org/abs/2601.00001v1</id><title>Tiny Models on Phones</title>
<link href="http://arxiv.org/abs/2601.00001v1"/><summary>We quantize.</summary></entry>
</feed>"""

JSON_API = json.dumps({"jobs": [
    {"id": 11, "title": "Platform Engineer", "url": "https://jobs.example.com/11", "description": "<b>Go</b>, k8s"},
    {"id": 12, "title": "Crypto Trader", "url": "https://jobs.example.com/12", "description": "trading"},
]}).encode()

PRODUCT = {"price": "Price: $249.99"}


class Mock(BaseHTTPRequestHandler):
    """Serves feeds, a fake OpenAI-compatible API and a fake ntfy."""
    posts = []

    def log_message(self, *a):
        pass

    def _send(self, body, ctype="application/xml"):
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/rss":
            self._send(RSS)
        elif self.path == "/atom":
            self._send(ATOM)
        elif self.path == "/api":
            self._send(JSON_API, "application/json")
        elif self.path == "/product":
            self._send(f"<html><body><h1>Gadget</h1><p>{PRODUCT['price']}</p></body></html>".encode(), "text/html")
        elif self.path == "/broken":
            self.send_response(500)
            self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        Mock.posts.append((self.path, dict(self.headers), body))
        if self.path == "/v1/chat/completions":
            req = json.loads(body)
            user = req["messages"][1]["content"]
            if "Page text" in user:
                reply = {"value": 199.0, "note": "sale"}
            else:
                items = json.loads(user.split("Items:\n", 1)[1])
                # Score items with "Engineer" in the title high, the rest low.
                reply = {"items": [{"id": it["id"], "score": 9 if "Engineer" in it["title"] else 2,
                                    "summary": "fits"} for it in items]}
            self._send(json.dumps({"choices": [{"message": {"content": json.dumps(reply)}}]}).encode(),
                       "application/json")
        else:  # ntfy publish
            self._send(b"{}", "application/json")


class SmartAlertsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.srv = ThreadingHTTPServer(("127.0.0.1", 0), Mock)
        cls.base = f"http://127.0.0.1:{cls.srv.server_address[1]}"
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()

    def setUp(self):
        Mock.posts.clear()
        self.tmp = tempfile.TemporaryDirectory()
        t = Path(self.tmp.name)
        (t / "cfg/secrets").mkdir(parents=True)
        (t / "cfg/resurrect.conf").write_text(f"ntfy.url={self.base}\nntfy.topic=alerts\n")
        (t / "cfg/secrets/ntfy_publish_token").write_text("tk_test\n")
        (t / "cfg/secrets/alerts_api_key").write_text("sk-test\n")
        os.environ["REZ_CONFIG_DIR"] = str(t / "cfg")
        os.environ["REZ_STATE_DIR"] = str(t / "state")
        self.dir = t

    def tearDown(self):
        self.tmp.cleanup()

    def job(self, text):
        p = self.dir / "job.toml"
        p.write_text(text.replace("BASE", self.base))
        return str(p)

    def digest(self, extra=""):
        return self.job(f"""
name = "jobs"
skip_backlog = false
[[sources]]
type = "rss"
url = "BASE/rss"
[[sources]]
type = "json"
url = "BASE/api"
items = "jobs"
fields = {{ id = "id", title = "title", link = "url", text = "description" }}
[llm]
base_url = "BASE/v1"
model = "test"
min_score = 7
prompt = "backend roles"
{extra}
""")

    def ntfy_posts(self):
        return [p for p in Mock.posts if p[0] == "/alerts"]

    # --- parsing ---
    def test_rss_parse(self):
        items = sa.parse_feed(RSS, "s")
        self.assertEqual([i.id for i in items], ["job-1", "job-2"])
        self.assertEqual(items[0].text, "Remote, junior friendly")
        self.assertEqual(items[0].link, "https://jobs.example.com/1")

    def test_atom_parse(self):
        items = sa.parse_feed(ATOM, "s")
        self.assertEqual(items[0].title, "Tiny Models on Phones")
        self.assertEqual(items[0].link, "http://arxiv.org/abs/2601.00001v1")

    def test_json_parse_and_dig(self):
        items = sa.parse_json_api(JSON_API, {"url": "x", "items": "jobs",
                                             "fields": {"id": "id", "title": "title", "link": "url", "text": "description"}})
        self.assertEqual(items[0].id, "11")
        self.assertEqual(items[0].text, "Go, k8s")
        self.assertEqual(sa.dig({"a": [{"b": 5}]}, "a.0.b"), 5)
        self.assertIsNone(sa.dig({"a": []}, "a.3"))

    def test_web_item_regex(self):
        raw = b"<ul><li>Deal A $10</li><li>Deal B $20</li></ul>"
        items = sa.parse_web(raw, {"url": "u", "item_regex": r"Deal \w \$\d+"})
        self.assertEqual([i.title for i in items], ["Deal A $10", "Deal B $20"])

    def test_include_exclude_filters(self):
        items = sa.fetch_source({"type": "rss", "url": self.base + "/rss", "exclude": ["sales"]})
        self.assertEqual([i.id for i in items], ["job-1"])

    # --- digest flow ---
    def test_digest_scores_and_sends_only_hits(self):
        self.assertEqual(sa.cmd_run(self.digest()), 0)
        sent = self.ntfy_posts()
        bodies = [p[2].decode() for p in sent]
        self.assertEqual(len(sent), 2)  # Backend Engineer + Platform Engineer
        self.assertTrue(all("Engineer" in b for b in bodies))
        self.assertEqual(sent[0][1]["Authorization"], "Bearer tk_test")
        llm = [p for p in Mock.posts if p[0] == "/v1/chat/completions"][0]
        self.assertEqual(llm[1]["Authorization"], "Bearer sk-test")

    def test_digest_dedupes_between_runs(self):
        sa.cmd_run(self.digest())
        Mock.posts.clear()
        sa.cmd_run(self.digest())
        self.assertEqual(self.ntfy_posts(), [])
        self.assertEqual([p for p in Mock.posts if p[0] == "/v1/chat/completions"], [])  # no LLM cost

    def test_skip_backlog_first_run(self):
        path = self.digest()
        Path(path).write_text(Path(path).read_text().replace("skip_backlog = false", "skip_backlog = true"))
        sa.cmd_run(path)
        self.assertEqual(Mock.posts, [])

    def test_dry_run_sends_nothing_and_marks_nothing(self):
        sa.cmd_run(self.digest(), dry_run=True)
        self.assertEqual(self.ntfy_posts(), [])
        sa.cmd_run(self.digest())
        self.assertEqual(len(self.ntfy_posts()), 2)

    def test_failure_counter_alerts_on_third(self):
        p = self.job("""
name = "broken"
[[sources]]
type = "rss"
url = "BASE/broken"
[llm]
prompt = "x"
""")
        for _ in range(3):
            self.assertEqual(sa.cmd_run(p), 1)
        sent = self.ntfy_posts()
        self.assertEqual(len(sent), 1)
        self.assertIn("broken", sent[0][1]["Title"])

    # --- watch flow ---
    def test_watch_regex_drop(self):
        p = self.job("""
name = "price"
kind = "watch"
[watch]
url = "BASE/product"
regex = 'Price:\\s*\\$([\\d.,]+)'
alert_when = "drop"
min_drop_pct = 5
""")
        PRODUCT["price"] = "Price: $249.99"
        sa.cmd_run(p)
        self.assertEqual(self.ntfy_posts(), [])  # first value, nothing to compare
        PRODUCT["price"] = "Price: $199.99"
        sa.cmd_run(p)
        sent = self.ntfy_posts()
        self.assertEqual(len(sent), 1)
        self.assertIn("249.99 -> 199.99", sent[0][2].decode())

    def test_watch_llm_extraction_below_target(self):
        p = self.job("""
name = "price2"
kind = "watch"
[watch]
url = "BASE/product"
alert_when = "below"
target = 200
[llm]
base_url = "BASE/v1"
prompt = "price"
""")
        sa.cmd_run(p)
        self.assertEqual(len(self.ntfy_posts()), 1)

    # --- job management ---
    def test_invalid_jobs(self):
        with self.assertRaises(ValueError):
            sa.load_job(self.job('name = "bad name!"\n[[sources]]\nurl="x"\n[llm]\nprompt="x"'))
        with self.assertRaises(ValueError):
            sa.load_job(self.job('name = "nosources"\n[llm]\nprompt="x"'))

    def test_examples_are_valid_and_disabled(self):
        for f in (REPO / "alerts/examples").glob("*.toml"):
            job = sa.load_job(str(f))
            self.assertFalse(job.get("enabled"), f.name)

    def test_cron_lines_only_for_enabled_valid_jobs(self):
        d = self.dir / "jobs"
        d.mkdir()
        (d / "a.toml").write_text('name="a"\nenabled=true\nschedule="0 * * * *"\n[[sources]]\nurl="x"\n[llm]\nprompt="p"\n')
        (d / "b.toml").write_text('name="b"\nenabled=false\nschedule="0 * * * *"\n[[sources]]\nurl="x"\n[llm]\nprompt="p"\n')
        (d / "c.toml").write_text('name="c"\nenabled=true\nschedule="every hour"\n[[sources]]\nurl="x"\n[llm]\nprompt="p"\n')
        import contextlib
        import io
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(io.StringIO()):
            sa.cmd_cron_lines(str(d), "REZ", "/logs")
        self.assertEqual(buf.getvalue().strip(), "0 * * * * REZ alerts run a >>/logs/alerts.log 2>&1")


if __name__ == "__main__":
    unittest.main()
