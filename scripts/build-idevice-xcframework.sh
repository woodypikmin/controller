#!/bin/bash
set -euxo pipefail

# Stage 7.8: execute a real XCUITest over the already-proven phone-local RSD tunnel.
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

# Stage 7.8 execution hook. This deliberately lives inside the upstream xctest
# module so it can reuse the exact private orchestration primitives while using
# Pikmin Pilot's already-established phone-local Adapter/RSD handles.
cat >> idevice/src/services/dvt/xctest/mod.rs <<'RUST'

struct PilotNoopXCTestListener;
impl XCUITestListener for PilotNoopXCTestListener {}

/// Runs a normal XCTest plan using an existing phone-local RSD tunnel.
/// This is the same lifecycle as XCUITestService::run(), except transport setup
/// is not recreated through an IdeviceProvider/CoreDeviceProxy. No WDA fallback.
pub async fn pilot_run_existing_rsd_xctest(
    handle: &mut crate::tcp::handle::AdapterHandle,
    handshake: &crate::services::rsd::RsdHandshake,
    cfg: TestConfig,
    ios_major_version: u8,
    timeout: Option<std::time::Duration>,
) -> Result<u64, String> {
    let session_id = uuid::Uuid::new_v4();
    let xctest_path = format!(
        "/tmp/{}.xctestconfiguration",
        session_id.to_string().to_uppercase()
    );

    let xctest_config = cfg
        .build_xctest_configuration(session_id, ios_major_version)
        .map_err(|e| format!("step=xctest-configuration • {e:?}"))?;

    // Exactly three DTX connections, all through the existing RSD adapter.
    let dvt = rsd_connect(
        handle,
        handshake,
        "com.apple.instruments.dtservicehub",
        "pikmin-pilot-exec-dtservicehub",
        true,
    )
    .await
    .map_err(|e| format!("step=dtx-dtservicehub • {e:?}"))?;

    let ctrl = rsd_connect(
        handle,
        handshake,
        TESTMANAGERD_RSD_SERVICE,
        "pikmin-pilot-exec-testmanagerd-ctrl",
        false,
    )
    .await
    .map_err(|e| format!("step=dtx-testmanagerd-ctrl • {e:?}"))?;

    let main = rsd_connect(
        handle,
        handshake,
        TESTMANAGERD_RSD_SERVICE,
        "pikmin-pilot-exec-testmanagerd-main",
        false,
    )
    .await
    .map_err(|e| format!("step=dtx-testmanagerd-main • {e:?}"))?;

    let mut conns = TestManagerConnections {
        ctrl,
        main,
        dvt,
        rsd_handles: Vec::new(),
    };

    let mut ctrl_proxy = TestManagerProxy::open(&mut conns.ctrl, ios_major_version)
        .await
        .map_err(|e| format!("step=open-testmanager-ctrl • {e:?}"))?;
    let mut main_proxy = TestManagerProxy::open(&mut conns.main, ios_major_version)
        .await
        .map_err(|e| format!("step=open-testmanager-main • {e:?}"))?;
    let mut process_control = XCTestProcessControlChannel::open(&mut conns.dvt)
        .await
        .map_err(|e| format!("step=open-process-control • {e:?}"))?;

    initialize_testmanager_sessions(&mut ctrl_proxy, &mut main_proxy, &xctest_config)
        .await
        .map_err(|e| format!("step=install-bootstrap-handlers • {e:?}"))?;

    register_early_driver_channel_handler(&mut conns.main, &xctest_config).await;

    initialize_testmanager_daemon_sessions(
        &mut ctrl_proxy,
        &mut main_proxy,
        ios_major_version,
        &session_id,
        &xctest_config,
    )
    .await
    .map_err(|e| format!("step=initialize-xctest-session • {e:?}"))?;

    let config_name = cfg.config_name().to_owned();
    let (launch_args, launch_env, launch_options) = build_launch_env(
        ios_major_version,
        &session_id,
        &cfg.runner_app_path,
        &cfg.runner_app_container,
        &config_name,
        &xctest_path,
        cfg.runner_env.as_ref(),
        cfg.runner_args.as_deref(),
    );

    let pid = launch_and_authorize_test_runner(
        &mut ctrl_proxy,
        &mut process_control,
        ios_major_version,
        &cfg.runner_bundle_id,
        launch_args,
        launch_env,
        launch_options,
    )
    .await
    .map_err(|e| format!("step=launch-authorize-runner • {e:?}"))?;

    let driver_channel = start_test_plan_session(&mut conns.main, &mut main_proxy)
        .await
        .map_err(|e| format!("step=wait-driver-start-plan • {e:?}"))?;

    let mut listener = PilotNoopXCTestListener;
    run_dispatch_loop_until_done_or_disconnect(
        &mut conns.main,
        driver_channel,
        &xctest_config,
        &mut listener,
        timeout,
    )
    .await
    .map_err(|e| format!("step=execute-test-plan • {e:?}"))?;

    Ok(pid)
}
RUST

cp "$ROOT/RustPatch/pilot_xctest_probe.rs" ffi/src/pilot_xctest_probe.rs
cp "$ROOT/RustPatch/pilot_xctest_dtx.rs" ffi/src/pilot_xctest_dtx.rs
cp "$ROOT/RustPatch/pilot_xctest_runner.rs" ffi/src/pilot_xctest_runner.rs
cp "$ROOT/RustPatch/pilot_xctest_metadata.rs" ffi/src/pilot_xctest_metadata.rs
cp "$ROOT/RustPatch/pilot_xctest_execute.rs" ffi/src/pilot_xctest_execute.rs

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

// Pikmin Pilot Stage 7.8 retained probes + real XCTest execution.
mod pilot_xctest_probe;
mod pilot_xctest_dtx;
mod pilot_xctest_runner;
mod pilot_xctest_metadata;
mod pilot_xctest_execute;

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
pub unsafe extern "C" fn pilot_xctest_execute_center_tap(
    adapter: *mut core_device_proxy::AdapterHandle,
    handshake: *mut rsd::RsdHandshakeHandle,
    message: *mut std::ffi::c_char,
    message_capacity: usize,
) -> i32 {
    unsafe {
        pilot_xctest_execute::pilot_xctest_execute_center_tap_impl(
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
    b"pilot_xctest_execute_center_tap",
]
missing = [name.decode() for name in required if name not in data]
if missing:
    raise SystemExit("Missing Stage 7.8 export(s): " + ", ".join(missing))
print("Stage 7.8 XCTest execute export set present.")
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
echo "Built Stage 7.8 execute-center-tap $OUT"
