#!/bin/zsh
# Unit tests for the pure logic (mood engine, action policy, cadence, lines).
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build
swiftc -swift-version 5 Sources/Mood.swift Sources/Policy.swift Sources/Lines.swift Sources/Config.swift Sources/State.swift Tests/main.swift -o build/tests
./build/tests
echo "--- x_reader extractors (fixture) ---"
node scripts/x_reader.mjs --fixture Tests/fixtures/x_home.html | python3 -c '
import json, sys
d = json.load(sys.stdin)
titles = [t["title"] for t in d["topics"]]
assert [t["name"] for t in d["trends"]] == ["Rust", "#LeetCode", "OpenAI"], d["trends"]
assert not any("adco" in t or "toaster" in t for t in titles), "ad leaked"
assert not any("@short" in t for t in titles), "too-short tweet leaked"
assert titles[3].startswith("@crab"), "tweets not ranked by likes"
assert "t.co" not in " ".join(titles), "links not stripped"
print("x_reader fixture: ok (%d topics)" % len(titles))
'
