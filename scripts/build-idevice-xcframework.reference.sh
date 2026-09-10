#!/bin/bash
set -euxo pipefail

PIN="${IDEVICE_PIN:-c65dfbf}"
ROOT="$(pwd)"
CACHE="$ROOT/.build/idevice"

rm -rf "$CACHE"
mkdir -p "$ROOT/.build"

git clone https://github.com/jkcoxson/idevice.git "$CACHE"
cd "$CACHE"
git checkout "$PIN"

rustup target add aarch64-apple-ios aarch64-apple-ios-sim

# Upstream's supported Apple build recipe.
BINDGEN_EXTRA_CLANG_ARGS="--sysroot=$(xcrun --sdk iphoneos --show-sdk-path)" \
IPHONEOS_DEPLOYMENT_TARGET=17.4 \
cargo build --release --target aarch64-apple-ios --features obfuscate

BINDGEN_EXTRA_CLANG_ARGS="--sysroot=$(xcrun --sdk iphonesimulator --show-sdk-path)" \
IPHONEOS_DEPLOYMENT_TARGET=17.4 \
cargo build --release --target aarch64-apple-ios-sim

# Remove embedded LLVM bitcode; modern Xcode/iOS does not require it.
for LIB in \
  target/aarch64-apple-ios/release/libidevice_ffi.a \
  target/aarch64-apple-ios-sim/release/libidevice_ffi.a
do
  xcrun bitcode_strip "$LIB" -r -o "$LIB.stripped"
  mv "$LIB.stripped" "$LIB"
done

mkdir -p "$ROOT/Vendor/IDevice/include"
cp ffi/idevice.h "$ROOT/Vendor/IDevice/include/idevice.h"

rm -rf "$ROOT/Vendor/IDevice/IDevice.xcframework"

xcodebuild -create-xcframework \
  -library target/aarch64-apple-ios/release/libidevice_ffi.a \
  -headers "$ROOT/Vendor/IDevice/include" \
  -library target/aarch64-apple-ios-sim/release/libidevice_ffi.a \
  -headers "$ROOT/Vendor/IDevice/include" \
  -output "$ROOT/Vendor/IDevice/IDevice.xcframework"

echo "Built Vendor/IDevice/IDevice.xcframework"
