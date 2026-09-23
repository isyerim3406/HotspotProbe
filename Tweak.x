#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <unistd.h>
#import <stdio.h>
#import <stdarg.h>
#import <string.h>

#pragma mark - Function types

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

typedef void (*SoftApStateDidChangeFn)(
    id,
    SEL,
    BOOL,
    id,
    id,
    id,
    unsigned long long,
    unsigned long long,
    BOOL,
    BOOL,
    BOOL,
    double,
    BOOL,
    double
);

typedef void (*LinkStateDidChangeFn)(
    id,
    SEL,
    BOOL,
    BOOL,
    long long,
    long long,
    id
);

typedef void (*SetTearDownReasonFn)(
    id,
    SEL,
    id
);

#pragma mark - Original implementations

static SoftApClientEventFn originalClientEvent = NULL;
static SoftApStateDidChangeFn originalSoftApState = NULL;
static LinkStateDidChangeFn originalLinkState = NULL;
static SetTearDownReasonFn originalTearDownReason = NULL;

#pragma mark - Logging

static FILE *OpenLog(void)
{
    FILE *f = fopen("/tmp/HotspotDiagV2.log", "a");

    if (!f)
        f = fopen("/var/tmp/HotspotDiagV2.log", "a");

    return f;
}

static void HPLog(NSString *format, ...)
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

    NSDateFormatter *formatter =
        [[NSDateFormatter alloc] init];

    formatter.dateFormat = @"HH:mm:ss.SSS";

    NSString *time =
        [formatter stringFromDate:[NSDate date]];

    fprintf(
        f,
        "[%s] %s\n",
        time.UTF8String,
        line.UTF8String
    );

    fflush(f);
    fclose(f);
}

#pragma mark - Hooks

static void HookClientEvent(
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
        @"CLIENT event=%d identifier=%@ Apple=%d InstantHS=%d AutoHS=%d Hidden=%d",
        event,
        identifier,
        isAppleClient,
        isInstantHotspot,
        isAutoHotspot,
        isHidden
    );

    if (originalClientEvent) {
        originalClientEvent(
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

static void HookSoftApState(
    id self,
    SEL _cmd,
    BOOL state,
    id requester,
    id status,
    id changeReason,
    unsigned long long channelNumber,
    unsigned long long countryCode,
    BOOL isHidden,
    BOOL isInfraConnected,
    BOOL isAwdlUp,
    double lowPowerModeDuration,
    BOOL compatibilityMode,
    double requestToUpLatency
)
{
    HPLog(
        @"SOFTAP state=%d requester=%@ status=%@ changeReason=%@ channel=%llu country=%llu Hidden=%d Infra=%d AWDL=%d lowPowerDuration=%.3f compatibility=%d latency=%.3f",
        state,
        requester,
        status,
        changeReason,
        channelNumber,
        countryCode,
        isHidden,
        isInfraConnected,
        isAwdlUp,
        lowPowerModeDuration,
        compatibilityMode,
        requestToUpLatency
    );

    if (originalSoftApState) {
        originalSoftApState(
            self,
            _cmd,
            state,
            requester,
            status,
            changeReason,
            channelNumber,
            countryCode,
            isHidden,
            isInfraConnected,
            isAwdlUp,
            lowPowerModeDuration,
            compatibilityMode,
            requestToUpLatency
        );
    }
}

static void HookLinkState(
    id self,
    SEL _cmd,
    BOOL linkState,
    BOOL isInvoluntary,
    long long linkChangeReason,
    long long linkChangeSubreason,
    id networkDetails
)
{
    HPLog(
        @"LINK state=%d involuntary=%d reason=%lld subreason=%lld details=%@",
        linkState,
        isInvoluntary,
        linkChangeReason,
        linkChangeSubreason,
        networkDetails
    );

    if (originalLinkState) {
        originalLinkState(
            self,
            _cmd,
            linkState,
            isInvoluntary,
            linkChangeReason,
            linkChangeSubreason,
            networkDetails
        );
    }
}

static void HookTearDownReason(
    id self,
    SEL _cmd,
    id reason
)
{
    HPLog(
        @"TEARDOWN reason=%@",
        reason
    );

    if (originalTearDownReason) {
        originalTearDownReason(
            self,
            _cmd,
            reason
        );
    }
}

#pragma mark - Safe hook installer

static BOOL InstallHook(
    NSString *className,
    NSString *selectorName,
    const char *expectedEncoding,
    IMP replacement,
    IMP *original
)
{
    Class cls =
        objc_getClass(className.UTF8String);

    if (!cls) {
        HPLog(
            @"ERROR class not found: %@",
            className
        );
        return NO;
    }

    SEL sel =
        NSSelectorFromString(selectorName);

    Method method =
        class_getInstanceMethod(cls, sel);

    if (!method) {
        HPLog(
            @"ERROR method not found: %@ %@",
            className,
            selectorName
        );
        return NO;
    }

    const char *encoding =
        method_getTypeEncoding(method);

    if (!encoding ||
        strcmp(encoding, expectedEncoding) != 0) {

        HPLog(
            @"SAFETY STOP %@ encoding=%s expected=%s",
            selectorName,
            encoding ? encoding : "(null)",
            expectedEncoding
        );

        return NO;
    }

    IMP oldImp =
        method_setImplementation(
            method,
            replacement
        );

    if (!oldImp) {
        HPLog(
            @"ERROR hook failed: %@",
            selectorName
        );
        return NO;
    }

    *original = oldImp;

    HPLog(
        @"HOOK INSTALLED: %@",
        selectorName
    );

    return YES;
}

#pragma mark - Init

__attribute__((constructor))
static void HotspotDiagInit(void)
{
    @autoreleasepool {

        NSString *process =
            [NSProcessInfo processInfo].processName;

        if (![process isEqualToString:@"wifid"])
            return;

        HPLog(
            @"=================================================="
        );

        HPLog(
            @"HotspotDiag V2 START pid=%d",
            getpid()
        );

        InstallHook(
            @"WiFiUsageSoftApSession",
            @"addSoftApClientEvent:identifier:isAppleClient:isInstantHotspot:isAutoHotspot:isHidden:",
            "v44@0:8B16@20B28B32B36B40",
            (IMP)HookClientEvent,
            (IMP *)&originalClientEvent
        );

        InstallHook(
            @"WiFiUsageSoftApSession",
            @"softApStateDidChange:requester:status:changeReason:channelNumber:countryCode:isHidden:isInfraConnected:isAwdlUp:lowPowerModeDuration:compatibilityMode:requestToUpLatency:",
            "v92@0:8B16@20@28@36Q44Q52B60B64B68d72B80d84",
            (IMP)HookSoftApState,
            (IMP *)&originalSoftApState
        );

        InstallHook(
            @"WiFiUsageSoftApSession",
            @"linkStateDidChange:isInvoluntary:linkChangeReason:linkChangeSubreason:withNetworkDetails:",
            "v48@0:8B16B20q24q32@40",
            (IMP)HookLinkState,
            (IMP *)&originalLinkState
        );

        InstallHook(
            @"WiFiUsageSoftApSession",
            @"setTearDownReason:",
            "v24@0:8@16",
            (IMP)HookTearDownReason,
            (IMP *)&originalTearDownReason
        );

        HPLog(@"HotspotDiag V2 READY");
    }
}
