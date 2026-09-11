// Pikmin Pilot Stage 8.0
// Command-driven XCTest execution over the existing phone-local RSD transport.
// No WDA HTTP transport. Commands are passed to the signed XCTest Runner via
// runner launch environment, allowing DVT screenshot coordinates to be tapped.

use std::ffi::c_char;
use std::ptr;
use std::time::Duration;

use crate::core_device_proxy::AdapterHandle;
use crate::rsd::RsdHandshakeHandle;
use crate::run_sync_local;

use idevice::RsdService;
use idevice::services::dvt::xctest::TestConfig;
use idevice::services::installation_proxy::InstallationProxyClient;

fn write_message(message: *mut c_char, capacity: usize, text: &str) {
    if message.is_null() || capacity == 0 {
        return;
    }
    let bytes = text.as_bytes();
    let copy_len = bytes.len().min(capacity.saturating_sub(1));
    unsafe {
        ptr::copy_nonoverlapping(bytes.as_ptr(), message.cast::<u8>(), copy_len);
        *message.add(copy_len) = 0;
    }
}

async fn run_command(
    adapter_ref: &mut idevice::tcp::handle::AdapterHandle,
    handshake_ref: &idevice::services::rsd::RsdHandshake,
    command: &str,
    x: f64,
    y: f64,
) -> Result<String, String> {
    let mut inst = InstallationProxyClient::connect_rsd(adapter_ref, handshake_ref)
        .await
        .map_err(|e| format!("step=installation-proxy-connect • {e:?}"))?;

    let apps = inst
        .get_apps(Some("User"), None)
        .await
        .map_err(|e| format!("step=installation-proxy-list • {e:?}"))?;

    let mut runner_ids: Vec<String> = apps
        .keys()
        .filter(|id| {
            let l = id.to_ascii_lowercase();
            l.ends_with(".xctrunner")
                || l.contains("pikminpilotrunner")
                || l.contains("pikminpilotrunneruitests")
        })
        .cloned()
        .collect();
    runner_ids.sort();

    let runner_id = runner_ids
        .first()
        .ok_or_else(|| {
            format!(
                "step=runner-discovery • no installed XCUITest runner among {} user apps",
                apps.len()
            )
        })?
        .clone();

    let target_id = "com.nianticlabs.pikmin";
    if !apps.contains_key(target_id) {
        return Err("step=target-discovery • Pikmin Bloom is not installed".into());
    }

    let mut cfg = TestConfig::from_installation_proxy(
        &mut inst,
        &runner_id,
        Some(target_id),
    )
    .await
    .map_err(|e| format!("step=test-config • {e:?}"))?;

    // The Runner has one test method. Its behavior is selected without changing
    // or relaunching the target app by passing these values to the Runner itself.
    let mut env = cfg.runner_env.take().unwrap_or_default();
    env.insert("PIKMIN_PILOT_COMMAND".to_owned(), command.to_owned().into());
    env.insert("PIKMIN_PILOT_X".to_owned(), format!("{x:.8}").into());
    env.insert("PIKMIN_PILOT_Y".to_owned(), format!("{y:.8}").into());
    cfg.runner_env = Some(env);

    drop(inst);

    let pid = idevice::services::dvt::xctest::pilot_run_existing_rsd_xctest(
        adapter_ref,
        handshake_ref,
        cfg,
        26,
        Some(Duration::from_secs(60)),
    )
    .await?;

    Ok(format!(
        "PHONE-LOCAL XCTEST COMMAND COMPLETED • command={} • x={:.5} • y={:.5} • runner={} • pid={} • target={}",
        command, x, y, runner_id, pid, target_id
    ))
}

unsafe fn execute_command_impl(
    adapter: *mut AdapterHandle,
    handshake: *mut RsdHandshakeHandle,
    command: &str,
    x: f64,
    y: f64,
    message: *mut c_char,
    message_capacity: usize,
) -> i32 {
    if adapter.is_null() || handshake.is_null() {
        write_message(message, message_capacity, "XCTest execute received NULL RSD handles");
        return -120;
    }
    if !(0.0..=1.0).contains(&x) || !(0.0..=1.0).contains(&y) {
        write_message(message, message_capacity, "XCTest normalized coordinate must be within 0...1");
        return -122;
    }

    let result: Result<String, String> = run_sync_local(async move {
        let adapter_ref = unsafe { &mut (*adapter).0 };
        let handshake_ref = unsafe { &mut (*handshake).0 };
        run_command(adapter_ref, &*handshake_ref, command, x, y).await
    });

    match result {
        Ok(detail) => {
            write_message(message, message_capacity, &detail);
            0
        }
        Err(error) => {
            write_message(
                message,
                message_capacity,
                &format!("PHONE-LOCAL XCTEST COMMAND FAILED • command={command} • {error}"),
            );
            -121
        }
    }
}

pub(crate) unsafe fn pilot_xctest_execute_center_tap_impl(
    adapter: *mut AdapterHandle,
    handshake: *mut RsdHandshakeHandle,
    message: *mut c_char,
    message_capacity: usize,
) -> i32 {
    unsafe {
        execute_command_impl(
            adapter,
            handshake,
            "center",
            0.5,
            0.5,
            message,
            message_capacity,
        )
    }
}

pub(crate) unsafe fn pilot_xctest_execute_activate_impl(
    adapter: *mut AdapterHandle,
    handshake: *mut RsdHandshakeHandle,
    message: *mut c_char,
    message_capacity: usize,
) -> i32 {
    unsafe {
        execute_command_impl(
            adapter,
            handshake,
            "activate",
            0.5,
            0.5,
            message,
            message_capacity,
        )
    }
}

pub(crate) unsafe fn pilot_xctest_execute_tap_impl(
    adapter: *mut AdapterHandle,
    handshake: *mut RsdHandshakeHandle,
    x: f64,
    y: f64,
    message: *mut c_char,
    message_capacity: usize,
) -> i32 {
    unsafe {
        execute_command_impl(
            adapter,
            handshake,
            "tap",
            x,
            y,
            message,
            message_capacity,
        )
    }
}
