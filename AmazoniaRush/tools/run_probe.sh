#!/bin/bash
# Builds the oracle for the host and drives every Swift frame decoder against
# it. This is the protocol test: it fails loudly if a writer and a reader drift.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

export PATH="$HOME/.cargo/bin:$PATH"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$here/.cargo-build}"

host="$(rustc -vV | awk '/^host:/ { print $2 }')"
cargo build -q -p verdant_oracle --release --target "$host"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export HOME="$work"

cp tools/probe.swift "$work/main.swift"

swiftc -O \
    -import-objc-header App/Supporting/VerdantOracle.h \
    App/Source/Bridge/Oracle.swift \
    App/Source/Bridge/Frames.swift \
    "$work/main.swift" \
    -L "$CARGO_TARGET_DIR/$host/release" \
    -lverdant_oracle \
    -o "$work/probe" 2>&1 | grep -v "^$" || true

"$work/probe"
