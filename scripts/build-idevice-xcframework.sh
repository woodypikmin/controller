#!/bin/bash
set -euxo pipefail

# Stage 7.6: phone-local XCTest DTX bootstrap on the already-proven RSD tunnel.
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

# The public idevice xctest orchestrator internally already contains the correct
# iOS 17+ RSD DTX handshake logic, but its low-level rsd_connect helper is private.
# Expose one tiny diagnostic helper *inside the idevice crate* so it can reuse
# those exact private primitives against Pikmin Pilot's existing Adapter/RSD handles.
cat >> idevice/src/services/dvt/xctest/mod.rs <<'RUST'

// Pikmin Pilot Stage 7.6 diagnostic hook.
// Uses the same private rsd_connect() implementation as the upstream XCTest
// orchestrator, but reuses an RSD adapter/handshake supplied by the embedding app.
pub async fn pilot_probe_existing_rsd_dtx(
    handle: &mut crate::tcp::handle::AdapterHandle,
    handshake: &crate::services::rsd::RsdHandshake,
) -> Result<String, crate::IdeviceError> {
    let dvt_port = handshake
        .services
        .get("com.apple.instruments.dtservicehub")
        .map(|service| service.port)
        .ok_or(crate::IdeviceError::ServiceNotFound)?;

    let tm_port = handshake
        .services
        .get(TESTMANAGERD_RSD_SERVICE)
        .map(|service| service.port)
        .ok_or(crate::IdeviceError::ServiceNotFound)?;

    // DVT includes the process-control termination callback capability exactly
    // like connect_rsd_stack_once() in upstream XCTest.
    let dvt = rsd_connect(
        handle,
        handshake,
        "com.apple.instruments.dtservicehub",
        "pikmin-pilot-dtservicehub",
        true,
    )
    .await?;

    // XCTest needs two independent testmanagerd DTX connections.
    let ctrl = rsd_connect(
        handle,
        handshake,
        TESTMANAGERD_RSD_SERVICE,
        "pikmin-pilot-testmanagerd-ctrl",
        false,
    )
    .await?;

    let main = rsd_connect(
        handle,
        handshake,
        TESTMANAGERD_RSD_SERVICE,
        "pikmin-pilot-testmanagerd-main",
        false,
    )
    .await?;

    // Keep all three clients alive until every handshake has completed.
    let _keep_alive = (dvt, ctrl, main);

    Ok(format!(
        "PHONE-LOCAL XCTEST DTX READY • dtservicehub={} • testmanagerd.ctrl={} • testmanagerd.main={} • {} RSD services",
        dvt_port,
        tm_port,
        tm_port,
        handshake.services.len()
    ))
}
RUST

cp "$ROOT/RustPatch/pilot_xctest_probe.rs" ffi/src/pilot_xctest_probe.rs
cp "$ROOT/RustPatch/pilot_xctest_dtx.rs" ffi/src/pilot_xctest_dtx.rs
cp "$ROOT/RustPatch/pilot_xctest_runner.rs" ffi/src/pilot_xctest_runner.rs
cp "$ROOT/RustPatch/pilot_xctest_metadata.rs" ffi/src/pilot_xctest_metadata.rs

# Add a focused FFI-only feature under the existing [features] table.
python3 - <<'PY'
from pathlib import Path
p = Path("ffi/Cargo.toml")
s = p.read_text()
needle = "[features]\n"
if needle not in s:
    raise SystemExit("ffi/Cargo.toml has no [features] table")
s = s.replace(
    needle,
    needle + 'pilot_xctest = ["idevice/xctest"]\n',
    1,
)
p.write_text(s)
PY

cat >> ffi/src/lib.rs <<'RUST'

// Pikmin Pilot Stage 7.6 retained service probe + DTX bootstrap.
mod pilot_xctest_probe;
mod pilot_xctest_dtx;
mod pilot_xctest_runner;
mod pilot_xctest_metadata;

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


#[unsafe(no_mangle)]
pub unsafe extern "C" fn pilot_xctest_runner_discovery(
    adapter: *mut core_device_proxy::AdapterHandle,
    handshake: *mut rsd::RsdHandshakeHandle,
    message: *mut std::ffi::c_char,
    message_capacity: usize,
) -> i32 {
    unsafe {
        pilot_xctest_runner::pilot_xctest_runner_discovery_impl(
            adapter,
            handshake,
            message,
            message_capacity,
        )
    }
}


#[unsafe(no_mangle)]
pub unsafe extern "C" fn pilot_xctest_metadata(
    adapter: *mut core_device_proxy::AdapterHandle,
    handshake: *mut rsd::RsdHandshakeHandle,
    message: *mut std::ffi::c_char,
    message_capacity: usize,
) -> i32 {
    unsafe {
        pilot_xctest_metadata::pilot_xctest_metadata_impl(
            adapter,
            handshake,
            message,
            message_capacity,
        )
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn pilot_xctest_dtx_bootstrap(
    adapter: *mut core_device_proxy::AdapterHandle,
    handshake: *mut rsd::RsdHandshakeHandle,
    message: *mut std::ffi::c_char,
    message_capacity: usize,
) -> i32 {
    unsafe {
        pilot_xctest_dtx::pilot_xctest_dtx_bootstrap_impl(
            adapter,
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
  --features "obfuscate,ring,core_device,tunnel_tcp_stack,dvt,pilot_xctest"

LIB="target/aarch64-apple-ios/release/libidevice_ffi.a"
test -f "$LIB"
ls -lh "$LIB"

# Apple nm may not understand every LLVM object emitted by current Rust;
# use a format-agnostic archive string check instead.
python3 - "$LIB" <<'PY'
from pathlib import Path
import sys
data = Path(sys.argv[1]).read_bytes()
required = [
    b"pilot_xctest_service_probe",
    b"pilot_xctest_dtx_bootstrap",
    b"pilot_xctest_runner_discovery",
    b"pilot_xctest_metadata",
]
missing = [name.decode() for name in required if name not in data]
if missing:
    raise SystemExit("Missing Stage 7.6 export(s): " + ", ".join(missing))
print("Stage 7.6 service-probe + DTX exports present.")
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
echo "Built Stage 7.6 $OUT"
