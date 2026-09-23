#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <unistd.h>
#import <stdio.h>

static FILE *OpenLog(void) {
    FILE *f = fopen("/tmp/HotspotProbeTypes.log", "a");
    if (!f)
        f = fopen("/var/tmp/HotspotProbeTypes.log", "a");
    return f;
}

static void LogLine(FILE *f, NSString *s) {
    if (!f || !s) return;
    fprintf(f, "%s\n", s.UTF8String);
    fflush(f);
}

static void DumpMethod(FILE *f, NSString *className, NSString *selectorName) {
    Class cls = objc_getClass(className.UTF8String);

    if (!cls) {
        LogLine(f, [NSString stringWithFormat:@"CLASS NOT FOUND: %@", className]);
        return;
    }

    SEL sel = NSSelectorFromString(selectorName);
    Method method = class_getInstanceMethod(cls, sel);

    if (!method) {
        LogLine(
            f,
            [NSString stringWithFormat:
                @"METHOD NOT FOUND: -[%@ %@]",
                className,
                selectorName
            ]
        );
        return;
    }

    const char *types = method_getTypeEncoding(method);
    unsigned int argc = method_getNumberOfArguments(method);

    LogLine(f, @"--------------------------------------------------");
    LogLine(
        f,
        [NSString stringWithFormat:
            @"METHOD: -[%@ %@]",
            className,
            selectorName
        ]
    );

    LogLine(
        f,
        [NSString stringWithFormat:
            @"TYPE ENCODING: %s",
            types ? types : "?"
        ]
    );

    LogLine(
        f,
        [NSString stringWithFormat:
            @"ARGUMENT COUNT: %u",
            argc
        ]
    );

    char returnType[256] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));

    LogLine(
        f,
        [NSString stringWithFormat:
            @"RETURN TYPE: %s",
            returnType
        ]
    );

    for (unsigned int i = 0; i < argc; i++) {
        char argType[256] = {0};

        method_getArgumentType(
            method,
            i,
            argType,
            sizeof(argType)
        );

        LogLine(
            f,
            [NSString stringWithFormat:
                @"ARG %u TYPE: %s",
                i,
                argType
            ]
        );
    }
}

__attribute__((constructor))
static void InitHotspotProbeTypes(void) {
    @autoreleasepool {

        NSString *process =
            [NSProcessInfo processInfo].processName;

        if (![process isEqualToString:@"wifid"]) {
            return;
        }

        FILE *f = OpenLog();

        if (!f)
            return;

        LogLine(f, @"");
        LogLine(f, @"==================================================");
        LogLine(
            f,
            [NSString stringWithFormat:
                @"HotspotProbe Types started process=%@ pid=%d",
                process,
                getpid()
            ]
        );
        LogLine(f, @"==================================================");

        DumpMethod(
            f,
            @"WiFiUsageSoftApSession",
            @"addSoftApClientEvent:identifier:isAppleClient:isInstantHotspot:isAutoHotspot:isHidden:"
        );

        DumpMethod(
            f,
            @"AWDWiFiSoftAPClient",
            @"setSwitchedToAnotherNetwork:"
        );

        DumpMethod(
            f,
            @"AWDWiFiSoftAPClient",
            @"setJoinedByAutoHS:"
        );

        DumpMethod(
            f,
            @"AWDWiFiSoftAPClient",
            @"setFamilyDevice:"
        );

        LogLine(f, @"[END]");
        fclose(f);
    }
}
