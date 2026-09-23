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

static FILE *OpenLog(void)
{
    FILE *f = fopen("/tmp/HotspotDiag.log", "a");

    if (!f)
        f = fopen("/var/tmp/HotspotDiag.log", "a");

    return f;
}

static void LogLine(NSString *format, ...)
{
    FILE *f = OpenLog();

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

static void DumpMethod(
    NSString *className,
    NSString *selectorName
)
{
    Class cls = objc_getClass(className.UTF8String);

    if (!cls) {
        LogLine(
            @"CLASS NOT FOUND: %@",
            className
        );
        return;
    }

    SEL sel =
        NSSelectorFromString(selectorName);

    Method method =
        class_getInstanceMethod(cls, sel);

    if (!method) {
        LogLine(
            @"METHOD NOT FOUND: -[%@ %@]",
            className,
            selectorName
        );
        return;
    }

    const char *encoding =
        method_getTypeEncoding(method);

    unsigned int count =
        method_getNumberOfArguments(method);

    LogLine(@"--------------------------------------------------");

    LogLine(
        @"METHOD: -[%@ %@]",
        className,
        selectorName
    );

    LogLine(
        @"ENCODING: %s",
        encoding ? encoding : "(null)"
    );

    LogLine(
        @"ARGUMENT COUNT: %u",
        count
    );

    char returnType[256] = {0};

    method_getReturnType(
        method,
        returnType,
        sizeof(returnType)
    );

    LogLine(
        @"RETURN TYPE: %s",
        returnType
    );

    for (unsigned int i = 0; i < count; i++) {

        char type[256] = {0};

        method_getArgumentType(
            method,
            i,
            type,
            sizeof(type)
        );

        LogLine(
            @"ARG %u TYPE: %s",
            i,
            type
        );
    }
}

/*
 Stable V5 event logger.
 This DOES NOT change any value.
*/

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
    LogLine(
        @"CLIENT EVENT=%d identifier=%@ Apple=%d InstantHS=%d AutoHS=%d Hidden=%d",
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
            isInstantHotspot,
            isAutoHotspot,
            isHidden
        );
    }
}

static void InstallSafeClientHook(void)
{
    Class cls =
        objc_getClass("WiFiUsageSoftApSession");

    if (!cls) {
        LogLine(@"CLIENT HOOK CLASS NOT FOUND");
        return;
    }

    SEL sel =
        NSSelectorFromString(
            @"addSoftApClientEvent:identifier:isAppleClient:isInstantHotspot:isAutoHotspot:isHidden:"
        );

    Method method =
        class_getInstanceMethod(cls, sel);

    if (!method) {
        LogLine(@"CLIENT HOOK METHOD NOT FOUND");
        return;
    }

    const char *encoding =
        method_getTypeEncoding(method);

    const char *expected =
        "v44@0:8B16@20B28B32B36B40";

    if (!encoding ||
        strcmp(encoding, expected) != 0) {

        LogLine(
            @"CLIENT HOOK SAFETY STOP encoding=%s",
            encoding ? encoding : "(null)"
        );

        return;
    }

    IMP oldImp =
        method_setImplementation(
            method,
            (IMP)HookSoftApClientEvent
        );

    if (!oldImp) {
        LogLine(@"CLIENT HOOK INSTALL FAILED");
        return;
    }

    originalSoftApClientEvent =
        (SoftApClientEventFn)oldImp;

    LogLine(@"CLIENT HOOK INSTALLED");
}

__attribute__((constructor))
static void HotspotDiagInit(void)
{
    @autoreleasepool {

        NSString *process =
            [NSProcessInfo processInfo].processName;

        if (![process isEqualToString:@"wifid"])
            return;

        LogLine(
            @"=================================================="
        );

        LogLine(
            @"HotspotDiag START pid=%d",
            getpid()
        );

        /*
         Stable V5 logger
        */
        InstallSafeClientHook();

        /*
         Only READ the signatures below.
         No hooks are installed on these methods.
        */

        DumpMethod(
            @"WiFiUsageSoftApSession",
            @"softApStateDidChange:requester:status:changeReason:channelNumber:countryCode:isHidden:isInfraConnected:isAwdlUp:lowPowerModeDuration:compatibilityMode:requestToUpLatency:"
        );

        DumpMethod(
            @"WiFiUsageMonitor",
            @"setSoftApState:requester:status:changeReason:channelNumber:countryCode:isHidden:isInfraConnected:isAwdlUp:lowPowerModeDuration:compatibilityMode:requestToUpLatency:"
        );

        DumpMethod(
            @"WiFiUsageSoftApSession",
            @"linkStateDidChange:isInvoluntary:linkChangeReason:linkChangeSubreason:withNetworkDetails:"
        );

        DumpMethod(
            @"WiFiUsageMonitor",
            @"setLinkEvent:isInvoluntary:linkChangeReason:linkChangeSubreason:withNetworkDetails:forInterface:"
        );

        DumpMethod(
            @"WiFiUsageSoftApSession",
            @"setTearDownReason:"
        );

        LogLine(@"[INIT COMPLETE]");
    }
}
