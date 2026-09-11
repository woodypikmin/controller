Stage 7.4 — Phone-local XCTest service probe

Why:
- iOS 26.6.1 target reports UniversalHID ServiceNotFound.
- CoreDevice HID path is therefore stopped.
- Modern iOS 17+ XCTest uses RSD services including:
  com.apple.dt.testmanagerd.remote
  com.apple.instruments.dtservicehub

This build only checks whether those services are advertised over the already
working RPPairing -> LocalDevVPN -> RSD path.

Expected success:
PHONE-LOCAL XCTEST SERVICES READY
testmanagerd.remote=YES:<port>
dtservicehub=YES:<port>

If READY, next stage is full phone-local XCTest runner bootstrap.
No WDA localhost transport fallback is used.
