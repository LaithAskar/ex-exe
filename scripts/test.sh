#!/bin/zsh
# Unit tests for the pure logic (mood engine, action policy, cadence, lines).
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build
swiftc -swift-version 5 Sources/Mood.swift Sources/Policy.swift Sources/Lines.swift Sources/Config.swift Tests/main.swift -o build/tests
./build/tests
