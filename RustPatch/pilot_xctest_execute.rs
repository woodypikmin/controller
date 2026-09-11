// Pikmin Pilot Stage 7.8
// Execute the installed UI-test runner end-to-end over the already-established
// phone-local RSD transport. No WDA HTTP transport is involved.

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

pub(crate) unsafe fn pilot_xctest_execute_center_tap_impl(
    adapter: *mut AdapterHandle,
    handshake: *mut RsdHandshakeHandle,
    message: *mut c_char,
    message_capacity: usize,
) -> i32 {
    if adapter.is_null() || handshake.is_null() {
        write_message(
            message,
            message_capacity,
            "XCTest execute received NULL RSD handles",
        );
        return -120;
    }

    let result: Result<String, String> = run_sync_local(async move {
        let adapter_ref = unsafe { &mut (*adapter).0 };
        let handshake_ref = unsafe { &mut (*handshake).0 };

        // Discover the exact post-Sideloadly bundle ID instead of assuming the
        // unsigned bundle identifier. The previous Stage 7.8 metadata probe
        // proved this data is available phone-locally through InstallationProxy.
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

        // Let upstream idevice build the exact modern XCTestConfiguration and
        // launch environment from the actual on-device runner/target metadata.
        let cfg = TestConfig::from_installation_proxy(
            &mut inst,
            &runner_id,
            Some(target_id),
        )
        .await
        .map_err(|e| format!("step=test-config • {e:?}"))?;

        // Release InstallationProxy before the DTX lifecycle reuses the same
        // software-tunnel adapter for three long-lived service connections.
        drop(inst);

        // The attached device is iOS 26.6.1. Passing 26 intentionally selects
        // the modern iOS 17+ RSD/testmanagerd path and never the lockdown/WDA path.
        let pid = idevice::services::dvt::xctest::pilot_run_existing_rsd_xctest(
            adapter_ref,
            &*handshake_ref,
            cfg,
            26,
            Some(Duration::from_secs(60)),
        )
        .await?;

        Ok(format!(
            "PHONE-LOCAL XCTEST CENTER TAP COMPLETED • runner={} • pid={} • target={}",
            runner_id, pid, target_id
        ))
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
                &format!("PHONE-LOCAL XCTEST CENTER TAP FAILED • {error}"),
            );
            -121
        }
    }
}
