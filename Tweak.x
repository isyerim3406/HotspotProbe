#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <unistd.h>
#import <stdio.h>
#import <stdarg.h>
#import <string.h>

typedef void (*SoftApClientEventFn)(
    id,
    SEL,
    BOOL,
    id,
    BOOL,
    BOOL,
    BOOL,
    BOOL
);

static SoftApClientEventFn originalSoftApClientEvent = NULL;

static void HPLog(NSString *format, ...)
{
    FILE *f = fopen("/tmp/HotspotProbeV7.log", "a");

    if (!f)
        f = fopen("/var/tmp/HotspotProbeV7.log", "a");

    if (!f)
        return;

    va_list args;
    va_start(args, format);

    NSString *line =
        [[NSString alloc] initWithFormat:format
                              arguments:args];

    va_end(args);

    fprintf(f, "%s\n", line.UTF8String);
    fflush(f);
    fclose(f);
}

static void HookSoftApClientEvent(
    id self,
    SEL _cmd,
    BOOL event,
    id identifier,
    BOOL isAppleClient,
    BOOL isInstantHotspot,
    BOOL isAutoHotspot,
    BOOL isHidden
)
{
    HPLog(
        @"EVENT=%d identifier=%@ RECEIVED Apple=%d InstantHS=%d AutoHS=%d Hidden=%d -> PASS InstantHS=0",
        event,
        identifier,
        isAppleClient,
        isInstantHotspot,
        isAutoHotspot,
        isHidden
    );

    if (originalSoftApClientEvent) {
        originalSoftApClientEvent(
            self,
            _cmd,
            event,
            identifier,
            isAppleClient,
            NO,
            isAutoHotspot,
            isHidden
        );
    }
}

__attribute__((constructor))
static void HotspotProbeInit(void)
{
    @autoreleasepool {

        NSString *process =
            [NSProcessInfo processInfo].processName;

        if (![process isEqualToString:@"wifid"])
            return;

        HPLog(
            @"===== HotspotProbe V7 FORCE-INSTANT-OFF pid=%d =====",
            getpid()
        );

        Class cls =
            objc_getClass("WiFiUsageSoftApSession");

        if (!cls) {
            HPLog(@"ERROR: class not found");
            return;
        }

        SEL sel =
            NSSelectorFromString(
                @"addSoftApClientEvent:identifier:isAppleClient:isInstantHotspot:isAutoHotspot:isHidden:"
            );

        Method method =
            class_getInstanceMethod(cls, sel);

        if (!method) {
            HPLog(@"ERROR: method not found");
            return;
        }

        const char *encoding =
            method_getTypeEncoding(method);

        HPLog(
            @"Encoding=%s",
            encoding ? encoding : "(null)"
        );

        const char *expected =
            "v44@0:8B16@20B28B32B36B40";

        if (!encoding ||
            strcmp(encoding, expected) != 0) {

            HPLog(@"SAFETY STOP: encoding mismatch");
            return;
        }

        IMP oldImplementation =
            method_setImplementation(
                method,
                (IMP)HookSoftApClientEvent
            );

        if (!oldImplementation) {
            HPLog(@"ERROR: method_setImplementation failed");
            return;
        }

        originalSoftApClientEvent =
            (SoftApClientEventFn)oldImplementation;

        HPLog(@"V7 HOOK INSTALLED - InstantHS forced to 0");
    }
}
