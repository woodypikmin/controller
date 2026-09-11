#!/bin/bash
set -euxo pipefail

# Stage 7.4: phone-local RSD XCTest service manifest probe.
# Keep this aligned with the newer idevice revision used during Stage 7.3.
PIN="${IDEVICE_PIN:-7a1cca3}"
ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
CACHE="$ROOT/.build/idevice"
OUT="$ROOT/Vendor/IDevice/IDevice.xcframework"
HEADERS="$ROOT/Vendor/IDevice/include"

rm -rf "$CACHE" "$OUT" "$HEADERS"
mkdir -p "$ROOT/.build" "$HEADERS"

git clone https://github.com/jkcoxson/idevice.git "$CACHE"
cd "$CACHE"
git checkout "$PIN"

cp "$ROOT/RustPatch/pilot_xctest_probe.rs" ffi/src/pilot_xctest_probe.rs

cat >> ffi/src/lib.rs <<'RUST'

// Pikmin Pilot Stage 7.4 phone-local XCTest service probe.
mod pilot_xctest_probe;

#[unsafe(no_mangle)]
pub unsafe extern "C" fn pilot_xctest_service_probe(
    handshake: *mut rsd::RsdHandshakeHandle,
    message: *mut std::ffi::c_char,
    message_capacity: usize,
) -> i32 {
    unsafe {
        pilot_xctest_probe::pilot_xctest_service_probe_impl(
            handshake,
            message,
            message_capacity,
        )
    }
}
RUST

rustup target add aarch64-apple-ios

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
BINDGEN_EXTRA_CLANG_ARGS="--sysroot=$SDK" \
IPHONEOS_DEPLOYMENT_TARGET=17.4 \
cargo build \
  -p idevice-ffi \
  --release \
  --locked \
  --target aarch64-apple-ios \
  --no-default-features \
  --features "obfuscate,ring,core_device,tunnel_tcp_stack,dvt"

LIB="target/aarch64-apple-ios/release/libidevice_ffi.a"
test -f "$LIB"
ls -lh "$LIB"

# Format-agnostic check; Apple nm cannot parse every Rust LLVM object format.
python3 - "$LIB" <<'PY'
from pathlib import Path
import sys
data = Path(sys.argv[1]).read_bytes()
if b"pilot_xctest_service_probe" not in data:
    raise SystemExit("Missing pilot_xctest_service_probe export")
print("Stage 7.4 XCTest probe export present.")
PY

cp ffi/idevice.h "$HEADERS/idevice.h"

xcodebuild -create-xcframework \
  -library "$LIB" \
  -headers "$HEADERS" \
  -output "$OUT"

test -f "$OUT/Info.plist"
test -f "$OUT/ios-arm64/libidevice_ffi.a"
test -f "$OUT/ios-arm64/Headers/idevice.h"
ls -lh "$OUT/ios-arm64/libidevice_ffi.a"
echo "Built Stage 7.4 $OUT"
