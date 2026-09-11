// Pikmin Pilot Stage 7.3 custom FFI for phone-local CoreDevice HID.
// This module is copied into idevice-ffi at GitHub Actions build time.

use std::ffi::c_char;
use std::ptr;
use std::time::Duration;

use idevice::RsdService;
use idevice::core_device::hid::{
    UniversalHidServiceClient,
    DIGITIZER_SURFACE_MAIN_TOUCHSCREEN,
    TOUCHSCREEN_STATE_CONTACT,
    TOUCHSCREEN_STATE_RELEASE,
    build_touchscreen_report,
};

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

async fn resolve_touchscreen_surface(
    hid: &mut UniversalHidServiceClient<Box<dyn idevice::ReadWrite>>,
) -> Result<(u64, String), String> {
    let surfaces = hid
        .list_connected_services()
        .await
        .map_err(|e| format!("UniversalHID surface list failed: {e:?}"))?;

    let summary = surfaces
        .iter()
        .map(|surface| {
            format!(
                "{}:{}",
                surface.service_id,
                surface.product.as_deref().unwrap_or("unnamed")
            )
        })
        .collect::<Vec<_>>()
        .join(", ");

    let service_id = surfaces
        .iter()
        .find(|surface| {
            surface
                .product
                .as_deref()
                .unwrap_or("")
                .to_ascii_lowercase()
                .contains("touchscreen")
        })
        .map(|surface| surface.service_id)
        .or_else(|| {
            surfaces
                .iter()
                .find(|surface| surface.service_id == DIGITIZER_SURFACE_MAIN_TOUCHSCREEN)
                .map(|surface| surface.service_id)
        })
        .ok_or_else(|| format!("No touchscreen HID surface found. Surfaces: {summary}"))?;

    Ok((service_id, summary))
}

async fn send_touch_sample(
    hid: &mut UniversalHidServiceClient<Box<dyn idevice::ReadWrite>>,
    service_id: u64,
    state: u8,
    x: u16,
    y: u16,
) -> Result<(), String> {
    hid.send_report(
        service_id,
        build_touchscreen_report(state, x, y, None),
    )
    .await
    .map_err(|e| format!("UniversalHID report failed: {e:?}"))
}

async fn tap_impl(
    adapter: &mut idevice::tcp::handle::AdapterHandle,
    handshake: &mut idevice::rsd::RsdHandshake,
    x: u16,
    y: u16,
) -> Result<String, String> {
    let mut session = start_screen_media_stream(adapter, handshake, 1).await?;
    let _audio_udp = session.audio_udp;
    let _video_udp = session.video_udp;

    tokio::time::sleep(Duration::from_millis(500)).await;

    let gesture_result = async {
        let mut hid = UniversalHidServiceClient::connect_rsd(adapter, handshake)
            .await
            .map_err(|e| format!("UniversalHID connect failed: {e:?}"))?;

        let (service_id, surfaces) = resolve_touchscreen_surface(&mut hid).await?;

        send_touch_sample(
            &mut hid,
            service_id,
            TOUCHSCREEN_STATE_CONTACT,
            x,
            y,
        )
        .await?;

        tokio::time::sleep(Duration::from_millis(90)).await;

        send_touch_sample(
            &mut hid,
            service_id,
            TOUCHSCREEN_STATE_RELEASE,
            x,
            y,
        )
        .await?;

        Ok::<String, String>(format!(
            "PHONE-LOCAL HID TAP SENT • screen={x},{y} • surface={service_id} • {surfaces}"
        ))
    }
    .await;

    tokio::time::sleep(Duration::from_millis(250)).await;

    let stop_result = session
        .client
        .stop_media_stream()
        .await
        .map_err(|e| format!("display stream stop failed: {e:?}"));

    let detail = gesture_result?;
    stop_result?;
    Ok(detail)
}

async fn drag_impl(
    adapter: &mut idevice::tcp::handle::AdapterHandle,
    handshake: &mut idevice::rsd::RsdHandshake,
    x1: u16,
    y1: u16,
    x2: u16,
    y2: u16,
) -> Result<String, String> {
    let mut session = start_screen_media_stream(adapter, handshake, 1).await?;
    let _audio_udp = session.audio_udp;
    let _video_udp = session.video_udp;

    tokio::time::sleep(Duration::from_millis(500)).await;

    let gesture_result = async {
        let mut hid = UniversalHidServiceClient::connect_rsd(adapter, handshake)
            .await
            .map_err(|e| format!("UniversalHID connect failed: {e:?}"))?;

        let (service_id, surfaces) = resolve_touchscreen_surface(&mut hid).await?;

        let steps: u32 = 36;
        for i in 0..steps {
            let t = i as f64 / steps as f64;
            let x = (x1 as f64 + (x2 as f64 - x1 as f64) * t).round() as u16;
            let y = (y1 as f64 + (y2 as f64 - y1 as f64) * t).round() as u16;
            send_touch_sample(
                &mut hid,
                service_id,
                TOUCHSCREEN_STATE_CONTACT,
                x,
                y,
            )
            .await?;
            tokio::time::sleep(Duration::from_millis(20)).await;
        }

        send_touch_sample(
            &mut hid,
            service_id,
            TOUCHSCREEN_STATE_CONTACT,
            x2,
            y2,
        )
        .await?;
        tokio::time::sleep(Duration::from_millis(25)).await;
        send_touch_sample(
            &mut hid,
            service_id,
            TOUCHSCREEN_STATE_RELEASE,
            x2,
            y2,
        )
        .await?;

        Ok::<String, String>(format!(
            "PHONE-LOCAL HID SWIPE SENT • {x1},{y1}->{x2},{y2} • surface={service_id} • {surfaces}"
        ))
    }
    .await;

    tokio::time::sleep(Duration::from_millis(250)).await;

    let stop_result = session
        .client
        .stop_media_stream()
        .await
        .map_err(|e| format!("display stream stop failed: {e:?}"));

    let detail = gesture_result?;
    stop_result?;
    Ok(detail)
}

/// Internal implementation called by the crate-root C ABI wrapper.
/// Coordinates are iOS screen-space points (u16).
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

    let result: Result<String, String> = run_sync_local(async move {
        let adapter_ref = unsafe { &mut (*provider).0 };
        let handshake_ref = unsafe { &mut (*handshake).0 };
        tap_impl(adapter_ref, handshake_ref, x, y).await
    });

    match result {
        Ok(detail) => {
            write_message(message, message_capacity, &detail);
            0
        }
        Err(error) => {
            write_message(message, message_capacity, &format!("HID tap failed: {error}"));
            -41
        }
    }
}

/// Internal implementation called by the crate-root C ABI wrapper.
/// Coordinates are iOS screen-space points (u16).
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

    let result: Result<String, String> = run_sync_local(async move {
        let adapter_ref = unsafe { &mut (*provider).0 };
        let handshake_ref = unsafe { &mut (*handshake).0 };
        drag_impl(adapter_ref, handshake_ref, x1, y1, x2, y2).await
    });

    match result {
        Ok(detail) => {
            write_message(message, message_capacity, &detail);
            0
        }
        Err(error) => {
            write_message(message, message_capacity, &format!("HID drag failed: {error}"));
            -43
        }
    }
}
