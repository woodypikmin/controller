# Pikmin Pilot — Stage 7.1

This build vendors the exact `IDevice.xcframework` produced by Stage 7.0.2.

## What is real in 7.1

The app now calls the idevice FFI directly:

1. `rp_pairing_file_read`
2. `rp_pairing_file_to_bytes`
3. `tunnel_create_rppairing`
4. `rsd_get_uuid`
5. `app_service_connect_rsd`
6. `app_service_launch_app("com.nianticlabs.pikmin")`

There is no `127.0.0.1:8100` WDA fallback and no Windows Runner path.

## Device test order

### A. Import a real RPPairing record

In Pikmin Pilot:

`匯入 RPPairing Record`

Then:

`VALIDATE WITH IDEVICE`

Expected:

`IDEVICE LINKED • RPPairing OK • ... bytes`

This proves the Rust static library is linked and the imported record is in the
RPPairing format expected by idevice.

### B. Enable loopback VPN

For the current on-device RPPairing recipe, the test target is:

`10.7.0.1:49152`

This is the LocalDevVPN-style device endpoint used by existing on-device
idevice integrations.

Then press:

`CONNECT PHONE-LOCAL RSD`

Expected:

`PHONE-LOCAL RSD ONLINE • UUID ...`

### C. Launch Pikmin without Windows

Press:

`PHONE-LOCAL → LAUNCH PIKMIN`

Expected:

Pikmin Bloom comes to the foreground.

If this succeeds, the next stage replaces the remaining Stage 5 WDA
`screenshot/tap/swipe` primitives with the phone-local RSD/CoreDevice
equivalents and restores RUN / 5 / 10 / 20 / 50 / infinite loop controls.

## Final-product note

Stage 7.1 still assumes a valid RPPairing record and a loopback VPN transport
exist on the phone. These are setup/transport components, not Windows runtime
dependencies. The final packaging work will try to fold as much of this setup
into Pikmin Pilot as iOS signing/Network Extension entitlements allow.


## Stage 7.1 GitHub-ready package note

This package intentionally does **not** commit the large `IDevice.xcframework` binary.
GitHub Actions builds the pinned idevice revision on the macOS runner, strips embedded LLVM bitcode, creates the iPhone arm64 XCFramework, and then builds Pikmin Pilot.

This keeps every repository file small enough for browser upload while preserving the Stage 7.1 FFI integration.

The first device gate is deliberately small:
validate the pairing file, then attempt the phone-local RPPairing/RSD path,
then use CoreDevice AppService to launch Pikmin.

Screenshot/tap/swipe are NOT claimed complete in Stage 7.1; those move next
after RSD/AppService is proven on-device.
