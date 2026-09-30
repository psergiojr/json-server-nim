#!/usr/bin/env python3
"""Differential test: the same requests against upstream json-server (node)
and this port, each on its own copy of a fixture. Compares status, the headers
a client acts on, and the body (JSON-parsed, generated ids masked).

    tools/difftest.py <upstream json-server checkout> <jsonserver binary>

Needs node >= 22 (upstream runs with --experimental-strip-types)."""
import json, os, re, shutil, subprocess, sys, tempfile, time, urllib.request, urllib.error

UP, OURS = sys.argv[1], sys.argv[2]
FIXTURE = {
    "posts": [
        {"id": "1", "title": "Hello", "views": 100, "published": True, "author": {"name": "ann"}},
        {"id": "2", "title": "bonjour", "views": 250, "published": False, "author": {"name": "Bob"}},
        {"id": 3, "title": "Élan", "views": 50, "tags": ["x"]},
        {"title": "no id", "views": 0},
    ],
    "comments": [
        {"id": "1", "postId": "1", "text": "a"},
        {"id": "2", "postId": "2", "text": "b"},
        {"id": "3", "postId": "1", "text": "c"},
    ],
    "profile": {"name": "typicode"},
    "analyses": [{"id": "a1"}],
    "notes": [{"id": "n1", "analyasisId": "a1"}],
}

REQUESTS = [
    ("GET", "/posts", None),
    ("GET", "/posts/1", None),
    ("GET", "/posts/3", None),
    ("GET", "/posts?views:gt=90", None),
    ("GET", "/posts?views_gte=100&published=true", None),
    ("GET", "/posts?title:contains=ON", None),
    ("GET", "/posts?title:startsWith=h&title:endsWith=O", None),
    ("GET", "/posts?author.name:eq=Bob", None),
    ("GET", "/posts?id:in=1,2", None),
    ("GET", "/posts?id=1", None),
    ("GET", "/posts?_sort=title", None),
    ("GET", "/posts?_sort=-views,title", None),
    ("GET", "/posts?_sort=author.name", None),
    ("GET", "/posts?_page=1&_per_page=2", None),
    ("GET", "/posts?_page=9&_per_page=2", None),
    ("GET", "/posts?_page=0", None),
    ("GET", "/posts?_per_page=2", None),
    ("GET", "/posts?_page=abc", None),
    ("GET", "/posts?_embed=comments", None),
    ("GET", "/posts/1?_embed=comments", None),
    ("GET", "/comments?_embed=post", None),
    ("GET", "/comments/1?_embed=post&_embed=nope", None),
    ("GET", "/analyses/a1?_embed=notes", None),
    ("GET", "/posts?_where=" + urllib.parse.quote('{"or":[{"views":{"lt":60}},{"title":{"eq":"Hello"}}]}'), None),
    ("GET", "/posts?_where=notjson&views:lt=60", None),
    ("GET", "/posts?_limit=1", None),
    ("GET", "/posts?views:bogus=1", None),
    ("GET", "/profile", None),
    ("GET", "/profile/1", None),
    ("GET", "/nope", None),
    ("GET", "/posts/1/extra", None),
    ("GET", "/test.html", None),
    ("OPTIONS", "/posts", None),
    ("POST", "/", "{}"),
    ("POST", "/posts", '{"title": "new", "id": "hijack"}'),
    ("POST", "/posts", ""),
    ("POST", "/posts", "[1]"),
    ("POST", "/posts", "{bad json"),
    ("POST", "/profile", "{}"),
    ("PUT", "/posts/1", '{"title": "replaced", "id": "zzz"}'),
    ("PATCH", "/posts/2", '{"views": 251}'),
    ("PATCH", "/profile", '{"age": 3}'),
    ("PUT", "/profile", '{"name": "x"}'),
    ("PUT", "/posts", "{}"),
    ("PATCH", "/posts/1", '"str"'),
    ("DELETE", "/posts/1", None),
    ("GET", "/comments", None),
    ("DELETE", "/posts/2?_dependent=comments", None),
    ("GET", "/comments", None),
    ("DELETE", "/posts/2", None),
    ("DELETE", "/profile", None),
    ("GET", "/posts?_sort=-views", None),
]

HEADERS = ["content-type", "access-control-allow-origin",
           "access-control-allow-methods", "access-control-allow-headers"]

def start(cmd, cwd, port):
    p = subprocess.Popen(cmd, cwd=cwd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         env=dict(os.environ, ASDF_NODEJS_VERSION=os.environ.get("ASDF_NODEJS_VERSION", "24.13.0")))
    for _ in range(100):
        try:
            urllib.request.urlopen(f"http://localhost:{port}/profile", timeout=1)
            return p
        except Exception:
            time.sleep(0.1)
    p.kill()
    sys.exit(f"server did not start: {cmd}")

def call(port, meth, path, body):
    data = body.encode() if body is not None else None
    req = urllib.request.Request(f"http://localhost:{port}{path}", data=data, method=meth)
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        r = urllib.request.urlopen(req, timeout=5)
        status, hdrs, raw = r.status, r.headers, r.read()
    except urllib.error.HTTPError as e:
        status, hdrs, raw = e.code, e.headers, e.read()
    return status, {h: hdrs.get(h) for h in HEADERS}, raw.decode("utf-8", "replace")

KNOWN_IDS = {"1", "2", "3", "a1", "n1"}
def mask(v):
    if isinstance(v, dict):
        return {k: ("<id>" if k == "id" and isinstance(x, str) and x not in KNOWN_IDS else mask(x))
                for k, x in v.items()}
    if isinstance(v, list):
        return [mask(x) for x in v]
    return v

def body_of(ct, raw):
    if ct and ct.startswith("application/json"):
        return mask(json.loads(raw))
    if ct and ct.startswith("text/html"):
        return "<html %d bytes>" % len(raw)
    return raw

def main():
    tmp = tempfile.mkdtemp()
    dirs = {}
    for side in ("up", "ours"):
        d = os.path.join(tmp, side)
        os.makedirs(os.path.join(d, "public"))
        shutil.copy(os.path.join(UP, "public", "test.html"), os.path.join(d, "public"))
        with open(os.path.join(d, "db.json"), "w") as f:
            json.dump(FIXTURE, f)
        dirs[side] = d
    up = start(["node", "--experimental-strip-types", "--no-warnings",
                os.path.join(os.path.abspath(UP), "src", "bin.ts"), "db.json", "-p", "4101"], dirs["up"], 4101)
    ours = start([os.path.abspath(OURS), "db.json", "-p", "4102"], dirs["ours"], 4102)
    diffs = 0
    try:
        for meth, path, body in REQUESTS:
            a = call(4101, meth, path, body)
            b = call(4102, meth, path, body)
            ba, bb = body_of(a[1]["content-type"], a[2]), body_of(b[1]["content-type"], b[2])
            same = a[0] == b[0] and a[1] == b[1] and ba == bb
            print(("same " if same else "DIFF ") + f"{meth} {path}")
            if not same:
                diffs += 1
                print(f"   upstream: {a[0]} {a[1]}\n             {json.dumps(ba)[:300]}")
                print(f"   ours:     {b[0]} {b[1]}\n             {json.dumps(bb)[:300]}")
        # the files on disk after the whole sequence
        time.sleep(0.3)
        fa = mask(json.load(open(os.path.join(dirs["up"], "db.json"))))
        fb = mask(json.load(open(os.path.join(dirs["ours"], "db.json"))))
        print(("same " if fa == fb else "DIFF ") + "db.json after the sequence")
        if fa != fb:
            diffs += 1
            print("   upstream:", json.dumps(fa)[:400], "\n   ours:    ", json.dumps(fb)[:400])
    finally:
        up.kill(); ours.kill()
    print(f"{len(REQUESTS) + 1 - diffs}/{len(REQUESTS) + 1} identical")
    sys.exit(1 if diffs else 0)

import urllib.parse
main()
