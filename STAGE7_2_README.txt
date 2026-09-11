Pikmin Pilot Stage 7.2.1 — Phone-local Screenshot Probe

已證明保留：
- RPPairing VALIDATE
- LocalDevVPN loopback
- 10.7.0.1:49152 RSD ONLINE
- CoreDevice AppService launch Pikmin

本版新增：
- idevice feature: screenshotr
- screenshotr_connect_rsd
- screenshotr_take_screenshot
- 將 screenshot 寫到 App temporary directory
- SwiftUI 直接顯示截圖

實機測試：
1. 開 LocalDevVPN，確認 Connected。
2. 開 Pikmin Pilot。
3. 若 pairing record 還在，不用重匯；否則匯入正確的 idevice RPPairing plist。
4. 按 CONNECT PHONE-LOCAL RSD，確認 ONLINE。
5. 按 PHONE-LOCAL → TAKE SCREENSHOT。
6. 成功標準：顯示 PHONE-LOCAL SCREENSHOT OK • xxxx bytes，下面出現截圖。

注意：
- 這版沒有 WDA localhost:8100。
- 這版先驗證 screenshot transport。
- Tap/Swipe 不硬塞進這一版，因為目前 pinned idevice c65dfbf 的 C FFI 沒有 phone-local HID exports；下一關會單獨接 HID，而不是 fallback WDA。
