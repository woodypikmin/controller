# Pikmin Pilot — Stage 7.3 NO_VENDOR

Stage 7.3 adds a **phone-local CoreDevice HID Tap / Drag probe** on top of the already proven:

- RPPairing record validation
- LocalDevVPN loopback (`10.7.0.1:49152`)
- phone-local RSD
- CoreDevice AppService launch
- DVT screenshot over RSD

## New in 7.3

The GitHub Actions build pins a newer `jkcoxson/idevice` revision containing the modern CoreDevice HID/display implementation. During the runner build it adds a tiny FFI module that:

1. Starts the CoreDevice display media stream auth gate.
2. Keeps the audio/video UDP sockets alive.
3. Waits 300 ms for BackBoard to authenticate the synthetic HID surface.
4. Connects `UniversalHidServiceClient` over the **same RSD generation**.
5. Sends either `tap()` or `drag()`.
6. Stops the display media stream.

No WDA `localhost:8100` fallback is used.

## Test on iPhone

1. Open LocalDevVPN and confirm it is connected.
2. Open Pikmin Pilot.
3. `VALIDATE WITH IDEVICE`.
4. `CONNECT PHONE-LOCAL RSD`.
5. `PHONE-LOCAL → LAUNCH PIKMIN`.
6. Put Pikmin Bloom on a screen where a center tap / vertical swipe is visible.
7. Return to Pikmin Pilot and try:
   - `PHONE-LOCAL → TAP CENTER`
   - `PHONE-LOCAL → SWIPE UP`
8. Report both the status text and whether Pikmin Bloom actually reacted.

## Repository size

This is still NO_VENDOR. The large Rust static library / XCFramework is produced temporarily by GitHub Actions and is not committed to the repository.
