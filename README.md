# Pikmin Pilot — Stage 7.6.2

## Real XCUITest Runner package

Stage 7.5.1 is empirically proven on the target iPhone:
- phone-local RSD
- `com.apple.instruments.dtservicehub`
- two `com.apple.dt.testmanagerd.remote` DTX capability handshakes
- `PHONE-LOCAL XCTEST DTX READY`

Stage 7.6.2 adds a real UI-testing target built by GitHub Actions.

The runner test does:

1. `XCUIApplication(bundleIdentifier: "com.nianticlabs.pikmin")`
2. launch Pikmin Bloom
3. wait for foreground
4. tap the center coordinate

Actions produces two unsigned IPAs:
- `PikminPilot-Stage7.6.2-unsigned.ipa`
- `PikminPilotRunner-Stage7.6.2-unsigned.ipa`

Sign/install both with Sideloadly.

The main app adds `FIND INSTALLED XCTEST RUNNER`, using InstallationProxy over
the already-working phone-local RSD tunnel. This confirms the signed runner
bundle is actually visible to iOS before we wire the full XCTest session start.

No WDA localhost:8100 fallback is used.
