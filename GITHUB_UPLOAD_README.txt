Pikmin Pilot Stage 7.1 — GitHub-ready source package

WHY THIS PACKAGE IS SMALL
- The original libidevice_ffi.a was ~186.8 MB because it contained embedded LLVM bitcode.
- This GitHub-ready package does NOT commit the XCFramework binary at all.
- GitHub Actions builds the pinned idevice commit on macOS, strips bitcode, creates the XCFramework, then builds the unsigned IPA.

UPLOAD
1. Extract this ZIP.
2. Upload the extracted project files to the repository.
3. Commit to main.
4. Open Actions -> Build Pikmin Pilot Stage 7.1 -> Run workflow.
5. Download artifact: PikminPilot-Stage7.1-unsigned.

IMPORTANT
- Do not manually upload Vendor/IDevice/IDevice.xcframework.
- The workflow creates it on the runner.
- No WDA localhost:8100 fallback was added.
