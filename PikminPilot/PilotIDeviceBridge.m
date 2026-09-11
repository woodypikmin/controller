
#import "PilotIDeviceBridge.h"
#import "idevice.h"

#import <Foundation/Foundation.h>
#import <arpa/inet.h>
#import <netinet/in.h>
#import <sys/socket.h>



extern int32_t pilot_xctest_metadata(
    struct AdapterHandle *adapter,
    struct RsdHandshakeHandle *handshake,
    char *message,
    size_t message_capacity
);

// Custom Stage 7.6 runner discovery export injected into idevice-ffi.
extern int32_t pilot_xctest_runner_discovery(
    struct AdapterHandle *adapter,
    struct RsdHandshakeHandle *handshake,
    char *message,
    size_t message_capacity
);

// Custom Stage 7.5 C ABI export injected into idevice-ffi at build time.
extern int32_t pilot_xctest_dtx_bootstrap(
    struct AdapterHandle *adapter,
    struct RsdHandshakeHandle *handshake,
    char *message,
    size_t message_capacity
);


// Custom Stage 7.4 C ABI export injected into idevice-ffi at build time.
extern int32_t pilot_xctest_service_probe(
    struct RsdHandshakeHandle *handshake,
    char *message,
    size_t message_capacity
);


static void PPWriteMessage(char *message, size_t capacity, NSString *text) {
    if (message == NULL || capacity == 0) {
        return;
    }

    const char *utf8 = text.UTF8String ?: "";
    snprintf(message, capacity, "%s", utf8);
    message[capacity - 1] = '\0';
}

static int32_t PPConsumeError(
    struct IdeviceFfiError *error,
    char *message,
    size_t capacity,
    NSString *prefix
) {
    if (error == NULL) {
        return 0;
    }

    int32_t code = error->code;
    int32_t subCode = error->sub_code;
    NSString *detail = error->message != NULL
        ? [NSString stringWithUTF8String:error->message]
        : @"unknown idevice error";

    PPWriteMessage(
        message,
        capacity,
        [NSString stringWithFormat:@"%@: code=%d sub=%d %@",
         prefix, code, subCode, detail]
    );

    idevice_error_free(error);
    return code == 0 ? -1 : code;
}

static int32_t PPLoadPairing(
    const char *path,
    struct RpPairingFileHandle **outPairing,
    char *message,
    size_t capacity
) {
    if (path == NULL || outPairing == NULL) {
        PPWriteMessage(message, capacity, @"Pairing path is missing");
        return -10;
    }

    *outPairing = NULL;

    struct IdeviceFfiError *error =
        rp_pairing_file_read(path, outPairing);

    if (error != NULL) {
        return PPConsumeError(
            error,
            message,
            capacity,
            @"RPPairing read failed"
        );
    }

    if (*outPairing == NULL) {
        PPWriteMessage(message, capacity, @"RPPairing parser returned NULL");
        return -11;
    }

    return 0;
}

static int32_t PPCreateTunnel(
    const char *pairingPath,
    const char *host,
    uint16_t port,
    struct AdapterHandle **outAdapter,
    struct RsdHandshakeHandle **outHandshake,
    char *message,
    size_t capacity
) {
    if (outAdapter == NULL || outHandshake == NULL) {
        PPWriteMessage(message, capacity, @"Invalid tunnel outputs");
        return -20;
    }

    *outAdapter = NULL;
    *outHandshake = NULL;

    struct RpPairingFileHandle *pairing = NULL;

    int32_t loadResult =
        PPLoadPairing(
            pairingPath,
            &pairing,
            message,
            capacity
        );

    if (loadResult != 0) {
        return loadResult;
    }

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));

#if defined(__APPLE__)
    address.sin_len = sizeof(address);
#endif

    address.sin_family = AF_INET;
    address.sin_port = htons(port);

    if (host == NULL ||
        inet_pton(AF_INET, host, &address.sin_addr) != 1) {
        rp_pairing_file_free(pairing);
        PPWriteMessage(message, capacity, @"Invalid IPv4 address");
        return -21;
    }

    struct IdeviceFfiError *error =
        tunnel_create_rppairing(
            (const idevice_sockaddr *)&address,
            (idevice_socklen_t)sizeof(address),
            "Pikmin Pilot",
            pairing,
            NULL,
            NULL,
            outAdapter,
            outHandshake
        );

    // The pairing file is borrowed by tunnel_create_rppairing.
    // Persist any pair-verify refresh/update before freeing it.
    if (error == NULL) {
        struct IdeviceFfiError *writeError =
            rp_pairing_file_write(pairing, pairingPath);

        if (writeError != NULL) {
            // Connection succeeded. Do not fail the tunnel solely because
            // persistence failed; free the diagnostic.
            idevice_error_free(writeError);
        }
    }

    rp_pairing_file_free(pairing);

    if (error != NULL) {
        return PPConsumeError(
            error,
            message,
            capacity,
            @"RPPairing tunnel failed"
        );
    }

    if (*outAdapter == NULL || *outHandshake == NULL) {
        PPWriteMessage(message, capacity, @"Tunnel returned empty RSD handles");
        return -22;
    }

    return 0;
}

int32_t PPValidateRPPairingFile(
    const char *path,
    char *message,
    size_t messageCapacity
) {
    struct RpPairingFileHandle *pairing = NULL;

    int32_t result =
        PPLoadPairing(
            path,
            &pairing,
            message,
            messageCapacity
        );

    if (result != 0) {
        return result;
    }

    uint8_t *serialized = NULL;
    uintptr_t length = 0;

    struct IdeviceFfiError *error =
        rp_pairing_file_to_bytes(
            pairing,
            &serialized,
            &length
        );

    if (error != NULL) {
        rp_pairing_file_free(pairing);
        return PPConsumeError(
            error,
            message,
            messageCapacity,
            @"RPPairing serialize failed"
        );
    }

    if (serialized != NULL) {
        idevice_data_free(serialized, length);
    }

    rp_pairing_file_free(pairing);

    PPWriteMessage(
        message,
        messageCapacity,
        [NSString stringWithFormat:
         @"IDEVICE LINKED • RPPairing OK • %llu bytes",
         (unsigned long long)length]
    );

    return 0;
}

int32_t PPProbeRSD(
    const char *pairingPath,
    const char *host,
    uint16_t port,
    char *message,
    size_t messageCapacity
) {
    struct AdapterHandle *adapter = NULL;
    struct RsdHandshakeHandle *handshake = NULL;

    int32_t tunnelResult =
        PPCreateTunnel(
            pairingPath,
            host,
            port,
            &adapter,
            &handshake,
            message,
            messageCapacity
        );

    if (tunnelResult != 0) {
        return tunnelResult;
    }

    char *uuid = NULL;
    struct IdeviceFfiError *uuidError =
        rsd_get_uuid(handshake, &uuid);

    NSString *uuidText = @"RSD connected";

    if (uuidError == NULL && uuid != NULL) {
        uuidText =
            [NSString stringWithFormat:
             @"PHONE-LOCAL RSD ONLINE • UUID %s",
             uuid];
        idevice_string_free(uuid);
    } else if (uuidError != NULL) {
        idevice_error_free(uuidError);
    }

    rsd_handshake_free(handshake);
    adapter_free(adapter);

    PPWriteMessage(message, messageCapacity, uuidText);
    return 0;
}

int32_t PPLaunchPikmin(
    const char *pairingPath,
    const char *host,
    uint16_t port,
    char *message,
    size_t messageCapacity
) {
    struct AdapterHandle *adapter = NULL;
    struct RsdHandshakeHandle *handshake = NULL;

    int32_t tunnelResult =
        PPCreateTunnel(
            pairingPath,
            host,
            port,
            &adapter,
            &handshake,
            message,
            messageCapacity
        );

    if (tunnelResult != 0) {
        return tunnelResult;
    }

    struct AppServiceHandle *appService = NULL;

    struct IdeviceFfiError *connectError =
        app_service_connect_rsd(
            adapter,
            handshake,
            &appService
        );

    if (connectError != NULL) {
        rsd_handshake_free(handshake);
        adapter_free(adapter);

        return PPConsumeError(
            connectError,
            message,
            messageCapacity,
            @"AppService connect failed"
        );
    }

    struct LaunchResponseC *response = NULL;

    struct IdeviceFfiError *launchError =
        app_service_launch_app(
            appService,
            "com.nianticlabs.pikmin",
            NULL,
            0,
            0,
            0,
            NULL,
            &response
        );

    if (launchError != NULL) {
        app_service_free(appService);
        rsd_handshake_free(handshake);
        adapter_free(adapter);

        return PPConsumeError(
            launchError,
            message,
            messageCapacity,
            @"Pikmin launch failed"
        );
    }

    if (response != NULL) {
        app_service_free_launch_response(response);
    }

    app_service_free(appService);
    rsd_handshake_free(handshake);
    adapter_free(adapter);

    PPWriteMessage(
        message,
        messageCapacity,
        @"PHONE-LOCAL AppService → Pikmin launch SENT"
    );

    return 0;
}


int32_t PPTakePhoneScreenshot(
    const char *pairingPath,
    const char *host,
    uint16_t port,
    const char *outputPath,
    char *message,
    size_t messageCapacity
) {
    if (outputPath == NULL || outputPath[0] == '\0') {
        PPWriteMessage(message, messageCapacity, @"Screenshot output path is missing");
        return -30;
    }

    struct AdapterHandle *adapter = NULL;
    struct RsdHandshakeHandle *handshake = NULL;

    int32_t tunnelResult =
        PPCreateTunnel(
            pairingPath,
            host,
            port,
            &adapter,
            &handshake,
            message,
            messageCapacity
        );

    if (tunnelResult != 0) {
        return tunnelResult;
    }

    // iOS 17+ developer screenshot path:
    // RSD -> com.apple.instruments.dtservicehub -> DVT screenshot channel.
    // Do not use classic Screenshotr here; that service may not be advertised
    // on modern RSD transports and produced "service not found" on iOS 26.6.1.
    struct RemoteServerHandle *remoteServer = NULL;
    struct IdeviceFfiError *remoteError =
        remote_server_connect_rsd(adapter, handshake, &remoteServer);

    if (remoteError != NULL) {
        rsd_handshake_free(handshake);
        adapter_free(adapter);
        return PPConsumeError(
            remoteError,
            message,
            messageCapacity,
            @"DVT RemoteServer connect failed"
        );
    }

    if (remoteServer == NULL) {
        rsd_handshake_free(handshake);
        adapter_free(adapter);
        PPWriteMessage(message, messageCapacity, @"DVT RemoteServer returned NULL");
        return -31;
    }

    struct ScreenshotClientHandle *client = NULL;
    struct IdeviceFfiError *clientError =
        screenshot_client_new(remoteServer, &client);

    if (clientError != NULL) {
        remote_server_free(remoteServer);
        rsd_handshake_free(handshake);
        adapter_free(adapter);
        return PPConsumeError(
            clientError,
            message,
            messageCapacity,
            @"DVT Screenshot channel failed"
        );
    }

    if (client == NULL) {
        remote_server_free(remoteServer);
        rsd_handshake_free(handshake);
        adapter_free(adapter);
        PPWriteMessage(message, messageCapacity, @"DVT Screenshot returned NULL client");
        return -32;
    }

    uint8_t *imageBytes = NULL;
    uintptr_t imageLength = 0;
    struct IdeviceFfiError *shotError =
        screenshot_client_take_screenshot(client, &imageBytes, &imageLength);

    if (shotError != NULL) {
        screenshot_client_free(client);
        remote_server_free(remoteServer);
        rsd_handshake_free(handshake);
        adapter_free(adapter);
        return PPConsumeError(
            shotError,
            message,
            messageCapacity,
            @"DVT Screenshot failed"
        );
    }

    if (imageBytes == NULL || imageLength == 0) {
        if (imageBytes != NULL) {
            idevice_data_free(imageBytes, imageLength);
        }
        screenshot_client_free(client);
        remote_server_free(remoteServer);
        rsd_handshake_free(handshake);
        adapter_free(adapter);
        PPWriteMessage(message, messageCapacity, @"DVT Screenshot returned empty data");
        return -33;
    }

    NSData *imageData =
        [NSData dataWithBytes:imageBytes length:(NSUInteger)imageLength];
    NSString *path = [NSString stringWithUTF8String:outputPath];
    NSError *writeError = nil;
    BOOL wrote = [imageData writeToFile:path options:NSDataWritingAtomic error:&writeError];
    uintptr_t byteCount = imageLength;

    idevice_data_free(imageBytes, imageLength);
    screenshot_client_free(client);
    remote_server_free(remoteServer);
    rsd_handshake_free(handshake);
    adapter_free(adapter);

    if (!wrote) {
        NSString *detail = writeError.localizedDescription ?: @"unknown file write error";
        PPWriteMessage(
            message,
            messageCapacity,
            [NSString stringWithFormat:@"DVT Screenshot save failed: %@", detail]
        );
        return -34;
    }

    PPWriteMessage(
        message,
        messageCapacity,
        [NSString stringWithFormat:
         @"PHONE-LOCAL DVT SCREENSHOT OK • %llu bytes",
         (unsigned long long)byteCount]
    );

    return 0;
}


int32_t PPProbePhoneLocalXCTestServices(
    const char *pairingPath,
    const char *host,
    uint16_t port,
    char *message,
    size_t messageCapacity
) {
    struct AdapterHandle *adapter = NULL;
    struct RsdHandshakeHandle *handshake = NULL;

    int32_t tunnelResult =
        PPCreateTunnel(
            pairingPath,
            host,
            port,
            &adapter,
            &handshake,
            message,
            messageCapacity
        );

    if (tunnelResult != 0) {
        return tunnelResult;
    }

    int32_t result =
        pilot_xctest_service_probe(
            handshake,
            message,
            messageCapacity
        );

    rsd_handshake_free(handshake);
    adapter_free(adapter);
    return result;
}


int32_t PPBootstrapPhoneLocalXCTestDTX(
    const char *pairingPath,
    const char *host,
    uint16_t port,
    char *message,
    size_t messageCapacity
) {
    struct AdapterHandle *adapter = NULL;
    struct RsdHandshakeHandle *handshake = NULL;

    int32_t tunnelResult =
        PPCreateTunnel(
            pairingPath,
            host,
            port,
            &adapter,
            &handshake,
            message,
            messageCapacity
        );

    if (tunnelResult != 0) {
        return tunnelResult;
    }

    int32_t result =
        pilot_xctest_dtx_bootstrap(
            adapter,
            handshake,
            message,
            messageCapacity
        );

    rsd_handshake_free(handshake);
    adapter_free(adapter);
    return result;
}


int32_t PPDiscoverPhoneLocalXCTestRunner(
    const char *pairingPath,
    const char *host,
    uint16_t port,
    char *message,
    size_t messageCapacity
) {
    struct AdapterHandle *adapter = NULL;
    struct RsdHandshakeHandle *handshake = NULL;

    int32_t tunnelResult =
        PPCreateTunnel(
            pairingPath,
            host,
            port,
            &adapter,
            &handshake,
            message,
            messageCapacity
        );

    if (tunnelResult != 0) {
        return tunnelResult;
    }

    int32_t result =
        pilot_xctest_runner_discovery(
            adapter,
            handshake,
            message,
            messageCapacity
        );

    rsd_handshake_free(handshake);
    adapter_free(adapter);
    return result;
}


int32_t PPLaunchBundleID(
    const char *pairingPath,
    const char *host,
    uint16_t port,
    const char *bundleID,
    char *message,
    size_t messageCapacity
) {
    if (bundleID == NULL || bundleID[0] == '\0') {
        PPWriteMessage(
            message,
            messageCapacity,
            @"Bundle ID is empty"
        );
        return -100;
    }

    struct AdapterHandle *adapter = NULL;
    struct RsdHandshakeHandle *handshake = NULL;

    int32_t tunnelResult =
        PPCreateTunnel(
            pairingPath,
            host,
            port,
            &adapter,
            &handshake,
            message,
            messageCapacity
        );

    if (tunnelResult != 0) {
        return tunnelResult;
    }

    struct AppServiceHandle *appService = NULL;

    struct IdeviceFfiError *connectError =
        app_service_connect_rsd(
            adapter,
            handshake,
            &appService
        );

    if (connectError != NULL) {
        rsd_handshake_free(handshake);
        adapter_free(adapter);

        return PPConsumeError(
            connectError,
            message,
            messageCapacity,
            @"AppService connect failed"
        );
    }

    struct LaunchResponseC *response = NULL;

    struct IdeviceFfiError *launchError =
        app_service_launch_app(
            appService,
            bundleID,
            NULL,
            0,
            0,
            0,
            NULL,
            &response
        );

    if (launchError != NULL) {
        app_service_free(appService);
        rsd_handshake_free(handshake);
        adapter_free(adapter);

        return PPConsumeError(
            launchError,
            message,
            messageCapacity,
            @"Bundle launch failed"
        );
    }

    if (response != NULL) {
        app_service_free_launch_response(response);
    }

    NSString *bundleString =
        [NSString stringWithUTF8String:bundleID]
        ?: @"<invalid bundle id>";

    app_service_free(appService);
    rsd_handshake_free(handshake);
    adapter_free(adapter);

    PPWriteMessage(
        message,
        messageCapacity,
        [NSString stringWithFormat:
            @"PHONE-LOCAL XCTEST RUNNER LAUNCH SENT • %@",
            bundleString
        ]
    );

    return 0;
}


int32_t PPPreparePhoneLocalXCTestMetadata(
    const char *pairingPath,
    const char *host,
    uint16_t port,
    char *message,
    size_t messageCapacity
) {
    struct AdapterHandle *adapter = NULL;
    struct RsdHandshakeHandle *handshake = NULL;

    int32_t tunnelResult = PPCreateTunnel(
        pairingPath, host, port,
        &adapter, &handshake,
        message, messageCapacity
    );
    if (tunnelResult != 0) {
        return tunnelResult;
    }

    int32_t result = pilot_xctest_metadata(
        adapter, handshake,
        message, messageCapacity
    );

    rsd_handshake_free(handshake);
    adapter_free(adapter);
    return result;
}
