#!/usr/bin/env python3
"""Refresh data/topics.json with headlines Vex can ramble about.

Sources (stdlib only, no auth):
  - Hacker News top stories (public Firebase API)
  - optional: data/x_topics.json written by a separate X/Twitter reader (see README)

Usage: python3 scripts/refresh_topics.py [--limit 20]
"""
import argparse
import json
import os
import sys
import tempfile
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data", "topics.json")
X_FILE = os.path.join(ROOT, "data", "x_topics.json")
HN = "https://hacker-news.firebaseio.com/v0"


def get_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "ex-exe/0.1"})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.load(r)


def hn_topics(limit):
    ids = get_json(f"{HN}/topstories.json")[: limit * 2]
    with ThreadPoolExecutor(8) as pool:
        items = list(pool.map(lambda i: get_json(f"{HN}/item/{i}.json"), ids))
    out = []
    for it in items:
        if not it or it.get("type") != "story" or not it.get("title"):
            continue
        out.append({"title": it["title"], "url": it.get("url"), "source": "hackernews"})
        if len(out) >= limit:
            break
    return out


def x_topics():
    try:
        with open(X_FILE) as f:
            data = json.load(f)
        return [{"title": t["title"], "url": t.get("url"), "source": "x"} for t in data.get("topics", []) if t.get("title")]
    except (OSError, ValueError, KeyError, TypeError):
        return []


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=20)
    args = ap.parse_args()

    topics = x_topics()
    try:
        topics += hn_topics(args.limit)
    except Exception as e:  # network down: keep the old file rather than writing an empty one
        print(f"hn fetch failed: {e}", file=sys.stderr)
        if not topics:
            return 1

    payload = {"updated": datetime.now(timezone.utc).isoformat(), "topics": topics}
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(OUT), suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        json.dump(payload, f, indent=2)
    os.replace(tmp, OUT)
    print(f"wrote {len(topics)} topics -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
