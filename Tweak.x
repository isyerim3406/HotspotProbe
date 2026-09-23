#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <unistd.h>
#import <stdio.h>
#import <stdarg.h>

static FILE *HPLogFile(void) {
    static FILE *f = NULL;

    if (!f) {
        f = fopen("/tmp/HotspotProbeV2.log", "a");

        if (!f)
            f = fopen("/var/tmp/HotspotProbeV2.log", "a");
    }

    return f;
}

static void HPLog(NSString *format, ...) {
    FILE *f = HPLogFile();
    if (!f)
        return;

    va_list args;
    va_start(args, format);

    NSString *line =
        [[NSString alloc] initWithFormat:format
                              arguments:args];

    va_end(args);

    NSDateFormatter *df = [NSDateFormatter new];
    df.locale =
        [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];

    df.dateFormat = @"HH:mm:ss.SSS";

    NSString *time =
        [df stringFromDate:[NSDate date]];

    fprintf(
        f,
        "[%s] %s\n",
        time.UTF8String,
        line.UTF8String
    );

    fflush(f);
}


/*
 --------------------------------------------------------
 WiFiUsageSoftApSession
 --------------------------------------------------------
*/

static void (*orig_addSoftApClientEvent)(
    id,
    SEL,
    id,
    id,
    BOOL,
    BOOL,
    BOOL,
    BOOL
);

static void hook_addSoftApClientEvent(
    id self,
    SEL _cmd,
    id event,
    id identifier,
    BOOL isAppleClient,
    BOOL isInstantHotspot,
    BOOL isAutoHotspot,
    BOOL isHidden
) {

    HPLog(
        @"CLIENT EVENT "
         "event=%@ "
         "identifier=%@ "
         "Apple=%d "
         "InstantHS=%d "
         "AutoHS=%d "
         "Hidden=%d",
        event,
        identifier,
        isAppleClient,
        isInstantHotspot,
        isAutoHotspot,
        isHidden
    );

    orig_addSoftApClientEvent(
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


/*
 --------------------------------------------------------
 AWDWiFiSoftAPClient
 --------------------------------------------------------
*/

static void (*orig_setSwitchedToAnotherNetwork)(
    id,
    SEL,
    BOOL
);

static void hook_setSwitchedToAnotherNetwork(
    id self,
    SEL _cmd,
    BOOL value
) {

    HPLog(
        @"AWD setSwitchedToAnotherNetwork=%d object=%@",
        value,
        self
    );

    orig_setSwitchedToAnotherNetwork(
        self,
        _cmd,
        value
    );
}


static void (*orig_setJoinedByAutoHS)(
    id,
    SEL,
    BOOL
);

static void hook_setJoinedByAutoHS(
    id self,
    SEL _cmd,
    BOOL value
) {

    HPLog(
        @"AWD setJoinedByAutoHS=%d object=%@",
        value,
        self
    );

    orig_setJoinedByAutoHS(
        self,
        _cmd,
        value
    );
}


static void (*orig_setFamilyDevice)(
    id,
    SEL,
    BOOL
);

static void hook_setFamilyDevice(
    id self,
    SEL _cmd,
    BOOL value
) {

    HPLog(
        @"AWD setFamilyDevice=%d object=%@",
        value,
        self
    );

    orig_setFamilyDevice(
        self,
        _cmd,
        value
    );
}


/*
 --------------------------------------------------------
 Helper
 --------------------------------------------------------
*/

static void HPHook(
    NSString *className,
    NSString *selectorName,
    IMP replacement,
    IMP *original
) {

    Class cls =
        objc_getClass(className.UTF8String);

    if (!cls) {
        HPLog(
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
        HPLog(
            @"METHOD NOT FOUND: -[%@ %@]",
            className,
            selectorName
        );
        return;
    }

    const char *types =
        method_getTypeEncoding(method);

    HPLog(
        @"HOOKING -[%@ %@] types=%s",
        className,
        selectorName,
        types ? types : "?"
    );

    MSHookMessageEx(
        cls,
        sel,
        replacement,
        original
    );
}


/*
 --------------------------------------------------------
 Init
 --------------------------------------------------------
*/

__attribute__((constructor))
static void HPInit(void) {

    @autoreleasepool {

        NSString *process =
            [NSProcessInfo processInfo].processName;

        if (![process isEqualToString:@"wifid"]) {
            return;
        }

        HPLog(
            @"=============================="
        );

        HPLog(
            @"HotspotProbe V2 started "
             "process=%@ pid=%d",
            process,
            getpid()
        );

        HPLog(
            @"=============================="
        );


        HPHook(
            @"WiFiUsageSoftApSession",
            @"addSoftApClientEvent:identifier:isAppleClient:isInstantHotspot:isAutoHotspot:isHidden:",
            (IMP)hook_addSoftApClientEvent,
            (IMP *)&orig_addSoftApClientEvent
        );


        HPHook(
            @"AWDWiFiSoftAPClient",
            @"setSwitchedToAnotherNetwork:",
            (IMP)hook_setSwitchedToAnotherNetwork,
            (IMP *)&orig_setSwitchedToAnotherNetwork
        );


        HPHook(
            @"AWDWiFiSoftAPClient",
            @"setJoinedByAutoHS:",
            (IMP)hook_setJoinedByAutoHS,
            (IMP *)&orig_setJoinedByAutoHS
        );


        HPHook(
            @"AWDWiFiSoftAPClient",
            @"setFamilyDevice:",
            (IMP)hook_setFamilyDevice,
            (IMP *)&orig_setFamilyDevice
        );


        HPLog(
            @"HotspotProbe V2 hooks installed"
        );
    }
}
