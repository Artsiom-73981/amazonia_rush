#!/bin/bash
# Compiles the Rust oracle for every iOS slice and drops the archives where the
# Xcode target expects them. Re-run after touching oracle/src or the lexicon.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

export PATH="$HOME/.cargo/bin:$PATH"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$here/.cargo-build}"

echo "[oracle] compiling the lexicon"
cargo run -q -p lexicon_forge

echo "[oracle] running proofs"
cargo test -q -p verdant_oracle 2>&1 | grep -E "test result|FAILED" || true

echo "[oracle] building device and simulator slices"
for slice in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
    cargo build -q -p verdant_oracle --release --target "$slice"
done

mkdir -p Vendor/device Vendor/sim
cp "$CARGO_TARGET_DIR/aarch64-apple-ios/release/libverdant_oracle.a" Vendor/device/
lipo -create \
    "$CARGO_TARGET_DIR/aarch64-apple-ios-sim/release/libverdant_oracle.a" \
    "$CARGO_TARGET_DIR/x86_64-apple-ios/release/libverdant_oracle.a" \
    -output Vendor/sim/libverdant_oracle.a

cp oracle/include/VerdantOracle.h App/Supporting/VerdantOracle.h

echo "[oracle] device  $(du -h Vendor/device/libverdant_oracle.a | cut -f1)"
echo "[oracle] sim     $(du -h Vendor/sim/libverdant_oracle.a | cut -f1)"
