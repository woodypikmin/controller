Stage 7.3 goal: prove phone-local HID.

Already real-device proven:
- RPPairing OK
- LocalDevVPN loopback OK
- RSD ONLINE
- launch Pikmin OK
- DVT screenshot OK

New probes:
- TAP CENTER: normalized 32768,32768
- SWIPE UP: 32768,48000 -> 32768,18000

Important: modern CoreDevice touch requires an active display media-stream auth gate.
This build starts that gate before UniversalHID and does NOT use WDA.
