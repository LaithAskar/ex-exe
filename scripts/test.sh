#!/bin/zsh
# Unit tests for the pure logic (mood engine, action policy, cadence, lines).
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build
swiftc -swift-version 5 Sources/Mood.swift Sources/Policy.swift Sources/Lines.swift Sources/Config.swift Sources/State.swift Sources/Demo.swift Tests/main.swift -o build/tests
./build/tests
echo "--- x_reader extractors (fixture) ---"
node scripts/x_reader.mjs --fixture Tests/fixtures/x_home.html | python3 -c '
import json, sys
d = json.load(sys.stdin)
titles = [t["title"] for t in d["topics"]]
assert [t["name"] for t in d["trends"]] == ["Cowboys", "Rust", "Election", "#LeetCode"], d["trends"]
assert [t["context"] for t in d["trends"]][0] == "Sports · Trending"
joined = " ".join(titles).lower()
for bad in ["adco", "toaster", "@short", "t.co", "election", "fucking", "@angry", "@pol", "lasagna", "promoted", "earn rewards"]:
    assert bad not in joined, "leaked: " + bad
assert titles[:3] == ["Cowboys (trending in Sports on X)", "Rust (trending in Technology on X)", "#LeetCode (trending on X)"], titles
assert titles[3].startswith("@crab") and titles[4].startswith("@somedev"), "tweets missing or not ranked by likes"
print("x_reader fixture: ok (%d topics)" % len(titles))
'
