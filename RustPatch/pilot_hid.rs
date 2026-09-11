// Pikmin Pilot Stage 7.3 custom FFI for phone-local CoreDevice HID.
// This module is copied into idevice-ffi at GitHub Actions build time.

use std::ffi::c_char;
use std::ptr;
use std::time::Duration;

use idevice::RsdService;
use idevice::core_device::hid::UniversalHidServiceClient;

use crate::core_device_proxy::AdapterHandle;
use crate::pilot_coredevice_stream::start_screen_media_stream;
use crate::rsd::RsdHandshakeHandle;
use crate::run_sync_local;

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

async fn tap_impl(
    adapter: &mut idevice::tcp::handle::AdapterHandle,
    handshake: &mut idevice::rsd::RsdHandshake,
    x: u16,
    y: u16,
) -> Result<(), String> {
    // On modern iOS, BackBoard rejects synthetic digitizer reports unless a
    // displayservice media stream is active from the same RSD generation.
    let mut session = start_screen_media_stream(adapter, handshake, 1).await?;
    let _audio_udp = session.audio_udp;
    let _video_udp = session.video_udp;

    tokio::time::sleep(Duration::from_millis(300)).await;

    let gesture_result = async {
        let mut hid = UniversalHidServiceClient::connect_rsd(adapter, handshake)
            .await
            .map_err(|e| format!("UniversalHID connect failed: {e:?}"))?;

        hid.tap(x, y)
            .await
            .map_err(|e| format!("UniversalHID tap failed: {e:?}"))?;
        Ok::<(), String>(())
    }
    .await;

    let stop_result = session
        .client
        .stop_media_stream()
        .await
        .map_err(|e| format!("display stream stop failed: {e:?}"));

    gesture_result?;
    stop_result?;
    Ok(())
}

async fn drag_impl(
    adapter: &mut idevice::tcp::handle::AdapterHandle,
    handshake: &mut idevice::rsd::RsdHandshake,
    x1: u16,
    y1: u16,
    x2: u16,
    y2: u16,
) -> Result<(), String> {
    let mut session = start_screen_media_stream(adapter, handshake, 1).await?;
    let _audio_udp = session.audio_udp;
    let _video_udp = session.video_udp;

    tokio::time::sleep(Duration::from_millis(300)).await;

    let gesture_result = async {
        let mut hid = UniversalHidServiceClient::connect_rsd(adapter, handshake)
            .await
            .map_err(|e| format!("UniversalHID connect failed: {e:?}"))?;

        // Mirrors upstream idevice-tools HID: deliberate ~0.6 second drag.
        hid.drag(x1, y1, x2, y2, 30, 20)
            .await
            .map_err(|e| format!("UniversalHID drag failed: {e:?}"))?;
        Ok::<(), String>(())
    }
    .await;

    let stop_result = session
        .client
        .stop_media_stream()
        .await
        .map_err(|e| format!("display stream stop failed: {e:?}"));

    gesture_result?;
    stop_result?;
    Ok(())
}

/// Internal implementation called by the crate-root C ABI wrapper.
/// Coordinates are 0...65535.
pub(crate) unsafe fn pilot_hid_tap_rsd_impl(
    provider: *mut AdapterHandle,
    handshake: *mut RsdHandshakeHandle,
    x: u16,
    y: u16,
    message: *mut c_char,
    message_capacity: usize,
) -> i32 {
    if provider.is_null() || handshake.is_null() {
        write_message(message, message_capacity, "HID received NULL RSD handles");
        return -40;
    }

    let result: Result<(), String> = run_sync_local(async move {
        let adapter_ref = unsafe { &mut (*provider).0 };
        let handshake_ref = unsafe { &mut (*handshake).0 };
        tap_impl(adapter_ref, handshake_ref, x, y).await
    });

    match result {
        Ok(()) => {
            write_message(
                message,
                message_capacity,
                &format!("PHONE-LOCAL HID TAP SENT • {x},{y}"),
            );
            0
        }
        Err(error) => {
            write_message(message, message_capacity, &format!("HID tap failed: {error}"));
            -41
        }
    }
}

/// Internal implementation called by the crate-root C ABI wrapper.
/// Coordinates are 0...65535.
pub(crate) unsafe fn pilot_hid_drag_rsd_impl(
    provider: *mut AdapterHandle,
    handshake: *mut RsdHandshakeHandle,
    x1: u16,
    y1: u16,
    x2: u16,
    y2: u16,
    message: *mut c_char,
    message_capacity: usize,
) -> i32 {
    if provider.is_null() || handshake.is_null() {
        write_message(message, message_capacity, "HID received NULL RSD handles");
        return -42;
    }

    let result: Result<(), String> = run_sync_local(async move {
        let adapter_ref = unsafe { &mut (*provider).0 };
        let handshake_ref = unsafe { &mut (*handshake).0 };
        drag_impl(adapter_ref, handshake_ref, x1, y1, x2, y2).await
    });

    match result {
        Ok(()) => {
            write_message(
                message,
                message_capacity,
                &format!("PHONE-LOCAL HID DRAG SENT • {x1},{y1} → {x2},{y2}"),
            );
            0
        }
        Err(error) => {
            write_message(message, message_capacity, &format!("HID drag failed: {error}"));
            -43
        }
    }
}
