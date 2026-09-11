#!/bin/bash
set -euxo pipefail

# Stage 7.3.2 needs the newer CoreDevice display/HID implementation.
# Pin the exact upstream commit seen in idevice CI on 2026-09-11.
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

# Reuse upstream's current display-stream negotiation helper exactly. It is
# also what idevice-tools HID uses as the touch authentication gate.
cp tools/src/coredevice_stream.rs ffi/src/pilot_coredevice_stream.rs
cp "$ROOT/RustPatch/pilot_hid.rs" ffi/src/pilot_hid.rs

# Register our two internal modules in idevice-ffi.
cat >> ffi/src/lib.rs <<'RUST'

// Pikmin Pilot Stage 7.3.2 additions. No WDA transport is used here.
mod pilot_coredevice_stream;
mod pilot_hid;

// Export the custom HID entry points from the crate root. Keeping the C ABI
// symbols at crate root prevents rustc/staticlib reachability from dropping a
// no_mangle function that lives only inside a private helper module.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn pilot_hid_tap_rsd(
    provider: *mut core_device_proxy::AdapterHandle,
    handshake: *mut rsd::RsdHandshakeHandle,
    x: u16,
    y: u16,
    message: *mut std::ffi::c_char,
    message_capacity: usize,
) -> i32 {
    unsafe {
        pilot_hid::pilot_hid_tap_rsd_impl(
            provider, handshake, x, y, message, message_capacity,
        )
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn pilot_hid_drag_rsd(
    provider: *mut core_device_proxy::AdapterHandle,
    handshake: *mut rsd::RsdHandshakeHandle,
    x1: u16,
    y1: u16,
    x2: u16,
    y2: u16,
    message: *mut std::ffi::c_char,
    message_capacity: usize,
) -> i32 {
    unsafe {
        pilot_hid::pilot_hid_drag_rsd_impl(
            provider, handshake, x1, y1, x2, y2, message, message_capacity,
        )
    }
}
RUST

# Ensure idevice-ffi enables idevice's display_stream implementation even if
# upstream does not expose a same-named FFI feature yet.
python3 - <<'PY'
from pathlib import Path
import re
p = Path("ffi/Cargo.toml")
s = p.read_text()
if "pilot_hid =" not in s:
    marker = "[features]"
    if marker not in s:
        raise SystemExit("ffi/Cargo.toml has no [features] section")
    s = s.replace(marker, marker + '\npilot_hid = ["idevice/display_stream", "idevice/core_device", "idevice/rsd"]', 1)
p.write_text(s)
PY

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
  --features "obfuscate,ring,core_device,tunnel_tcp_stack,dvt,pilot_hid"

LIB="target/aarch64-apple-ios/release/libidevice_ffi.a"
test -f "$LIB"
ls -lh "$LIB"

# Xcode 26.6's Apple nm cannot parse LLVM 22 bitcode metadata emitted by
# Rust 1.98, so do a format-agnostic raw archive check instead. The exported
# C ABI names are stored plainly in the Mach-O/archive symbol/string tables.
echo "Checking Stage 7.3.2 HID exports in $LIB without Apple nm ..."
python3 - "$LIB" <<'PY'
from pathlib import Path
import sys

data = Path(sys.argv[1]).read_bytes()
missing = [
    name for name in (b"pilot_hid_tap_rsd", b"pilot_hid_drag_rsd")
    if name not in data
]
if missing:
    raise SystemExit("Missing HID export(s): " + ", ".join(x.decode() for x in missing))
print("HID export names present in static archive.")
PY

# The app declares the two custom C symbols in PilotIDeviceBridge.m, so the
# generated idevice.h only needs the normal upstream FFI handle definitions.
# This avoids making the build depend on cbindgen exporting private modules.
cp ffi/idevice.h "$HEADERS/idevice.h"

xcodebuild -create-xcframework \
  -library "$LIB" \
  -headers "$HEADERS" \
  -output "$OUT"

test -f "$OUT/Info.plist"
test -f "$OUT/ios-arm64/libidevice_ffi.a"
test -f "$OUT/ios-arm64/Headers/idevice.h"
ls -lh "$OUT/ios-arm64/libidevice_ffi.a"
echo "Built Stage 7.3.2 HID-enabled $OUT"
