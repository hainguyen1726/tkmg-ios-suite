#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios >/dev/null 2>&1 || true

echo "==> Running tkmg_core unit tests..."
cargo test

echo "==> Building staticlib for iphoneos (aarch64-apple-ios)..."
cargo build --release --target aarch64-apple-ios

echo "==> Building staticlib for iphonesimulator (aarch64-apple-ios-sim + x86_64-apple-ios)..."
cargo build --release --target aarch64-apple-ios-sim
cargo build --release --target x86_64-apple-ios

IOS_LIB="$ROOT/target/aarch64-apple-ios/release/libtkmg_core.a"
SIM_ARM="$ROOT/target/aarch64-apple-ios-sim/release/libtkmg_core.a"
SIM_X64="$ROOT/target/x86_64-apple-ios/release/libtkmg_core.a"

for APP_DIR in "../TKMGPlayer-iOS" "../TKMGScanner-iOS"; do
  DEST="$ROOT/$APP_DIR/Vendor/TkmgCore"
  mkdir -p "$DEST/iphoneos" "$DEST/iphonesimulator"
  cp "$IOS_LIB" "$DEST/iphoneos/libtkmg_core.a"
  lipo -create "$SIM_ARM" "$SIM_X64" -output "$DEST/iphonesimulator/libtkmg_core.a"
  cp "$ROOT/include/tkmg_core.h" "$DEST/tkmg_core.h"
  cp "$ROOT/include/module.modulemap" "$DEST/module.modulemap"
  echo "Synced Rust staticlib -> $DEST ({iphoneos,iphonesimulator}/libtkmg_core.a)"
done
