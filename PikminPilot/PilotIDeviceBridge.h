
#pragma once

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Returns 0 on success. Writes a human-readable result into message.
int32_t PPValidateRPPairingFile(
    const char *path,
    char *message,
    size_t messageCapacity
);

/// Creates an on-device RPPairing tunnel to host:port and performs an RSD
/// handshake. Returns 0 on success.
int32_t PPProbeRSD(
    const char *pairingPath,
    const char *host,
    uint16_t port,
    char *message,
    size_t messageCapacity
);

/// Creates the same phone-local tunnel and uses CoreDevice AppService to
/// launch Pikmin Bloom. Returns 0 on success.
int32_t PPLaunchPikmin(
    const char *pairingPath,
    const char *host,
    uint16_t port,
    char *message,
    size_t messageCapacity
);

#ifdef __cplusplus
}
#endif
