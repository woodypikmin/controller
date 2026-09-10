# Pikmin Pilot — Stage 7.0.2.2

這是從 PC/WDA 架構切換到 **iPhone 本機 embedded device transport** 的第一版專案。

## 這版已包含

- Stage 5 已完成的水果辨識來源碼
- Stage 5 的單次派遣 / Continuous Loop 來源碼
- `PilotTransport` transport boundary
- Remote Pairing Record 匯入與保存
- 明確禁止 Stage 7 靜默 fallback 到 `127.0.0.1:8100`
- GitHub Actions unsigned IPA build
- GitHub Actions / script 建 `jkcoxson/idevice` XCFramework

## 這版尚未假裝完成的部分

`EmbeddedDeviceTransport.connect()` 現在會明確回：

    Stage 7 Embedded Device Engine 尚未連接完成

這是故意的，不是假成功。

下一個 gate（Stage 7.1）是把 `IDevice.xcframework` 真正接到：

    pairing record
    → RPPairing / local tunnel
    → RSD
    → CoreDevice / XCTest or HID

再把 Stage 5 Bot 的 screenshot/tap/swipe 改走這個 transport。

## 為什麼這條路和成品直接相關

`idevice` 是設計給「嵌入 App / server」使用的 Rust library，支援 RSD、CoreDevice、XCTest/WDA bootstrap。
現有 iOS 專案也已經使用同一類架構在手機端處理 pairing、tunnel、display、HID。

Stage 7 的成品目標：

    安裝 Pikmin Pilot
    → 首次匯入 pairing record
    → 之後手機直接 RUN
    → 平常不用 Windows / CMD

### iOS 26.x 的現實

iOS 26.x 目前仍需要先有一份 Remote Pairing Record。
這可以做成一次性的首次設定，而不是每次執行都接電腦。

## Build

1. 上傳整個專案到 GitHub。
2. Actions → `Build Pikmin Pilot Stage 7.0.2.2`
3. 下載：
   - `PikminPilot-Stage7.0-unsigned`
   - `IDevice-xcframework`（Stage 7.1 用）

## Stage 7.0.2.2 測試

這一版只要確認：

1. IPA 能安裝 / 開啟。
2. `匯入 Pairing Record` 可以選 plist。
3. 匯入後顯示 byte size。
4. `TEST PHONE-LOCAL ENGINE` 會明確顯示 embedded engine 尚未接線，而不是偷連 WDA。

這個 gate 確認後，後續不再回 Windows Runner 架構。


## Stage 7.0.2.2 fix

GitHub Actions now invokes the idevice build script through `bash` and also
sets its executable bit first. This avoids `Permission denied` when repository
uploads do not preserve Unix executable permissions.


## Stage 7.0.2 build fix

The GitHub Actions workflow no longer executes
`scripts/build-idevice-xcframework.sh` at all.

The `build-idevice` job now performs these steps inline:

1. clone `jkcoxson/idevice`
2. build `idevice-ffi` for `aarch64-apple-ios`
3. copy `ffi/idevice.h`
4. create `IDevice.xcframework`
5. upload the XCFramework artifact

Therefore ZIP/Git executable-bit preservation is irrelevant and this build
cannot fail with `./scripts/...: Permission denied`.
