#pragma once

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

int32_t PPValidateRPPairingFile(const char *path, char *message, size_t messageCapacity);
int32_t PPProbeRSD(const char *pairingPath, const char *host, uint16_t port, char *message, size_t messageCapacity);
int32_t PPLaunchPikmin(const char *pairingPath, const char *host, uint16_t port, char *message, size_t messageCapacity);
int32_t PPTakePhoneScreenshot(const char *pairingPath, const char *host, uint16_t port, const char *outputPath, char *message, size_t messageCapacity);

/// Stage 7.3: create a fresh phone-local RSD tunnel, open the CoreDevice display
/// auth gate, then send one normalized UniversalHID tap. Coordinates 0...65535.
int32_t PPPhoneTap(
    const char *pairingPath,
    const char *host,
    uint16_t port,
    uint16_t x,
    uint16_t y,
    char *message,
    size_t messageCapacity
);

/// Stage 7.3: same transport/auth gate, then send a deliberate UniversalHID drag.
int32_t PPPhoneDrag(
    const char *pairingPath,
    const char *host,
    uint16_t port,
    uint16_t x1,
    uint16_t y1,
    uint16_t x2,
    uint16_t y2,
    char *message,
    size_t messageCapacity
);

#ifdef __cplusplus
}
#endif


int32_t PPLaunchAndTapPikmin(
    const char *pairingPath,
    const char *host,
    uint16_t port,
    uint16_t x,
    uint16_t y,
    char *message,
    size_t messageCapacity
);

int32_t PPLaunchAndDragPikmin(
    const char *pairingPath,
    const char *host,
    uint16_t port,
    uint16_t x1,
    uint16_t y1,
    uint16_t x2,
    uint16_t y2,
    char *message,
    size_t messageCapacity
);
