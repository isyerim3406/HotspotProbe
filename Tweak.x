#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <unistd.h>
#import <stdio.h>
#import <stdarg.h>

static FILE *HPLogFile(void) {
    static FILE *f = NULL;

    if (!f)
        f = fopen("/tmp/HotspotProbeV4.log", "a");

    if (!f)
        f = fopen("/var/tmp/HotspotProbeV4.log", "a");

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

    fprintf(
        f,
        "%s\n",
        line.UTF8String
    );

    fflush(f);
}


/*
 Real encoding:

 v44@0:8B16@20B28B32B36B40

 self        @
 _cmd        :
 event       BOOL
 identifier  id
 Apple       BOOL
 InstantHS   BOOL
 AutoHS      BOOL
 Hidden      BOOL
*/

static void (*orig_addSoftApClientEvent)(
    id,
    SEL,
    BOOL,
    id,
    BOOL,
    BOOL,
    BOOL,
    BOOL
);

static void hook_addSoftApClientEvent(
    id self,
    SEL _cmd,
    BOOL event,
    id identifier,
    BOOL isAppleClient,
    BOOL isInstantHotspot,
    BOOL isAutoHotspot,
    BOOL isHidden
) {

    HPLog(
        @"EVENT=%d identifier=%@ Apple=%d InstantHS=%d AutoHS=%d Hidden=%d",
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

__attribute__((constructor))
static void HPInit(void) {

    @autoreleasepool {

        NSString *process =
            [NSProcessInfo processInfo].processName;

        if (![process isEqualToString:@"wifid"])
            return;

        HPLog(
            @"HotspotProbe V4 START pid=%d",
            getpid()
        );

        Class cls =
            objc_getClass("WiFiUsageSoftApSession");

        if (!cls) {
            HPLog(@"CLASS NOT FOUND");
            return;
        }

        SEL sel =
            NSSelectorFromString(
                @"addSoftApClientEvent:identifier:isAppleClient:isInstantHotspot:isAutoHotspot:isHidden:"
            );

        Method method =
            class_getInstanceMethod(cls, sel);

        if (!method) {
            HPLog(@"METHOD NOT FOUND");
            return;
        }

        HPLog(
            @"METHOD FOUND encoding=%s",
            method_getTypeEncoding(method)
        );

        MSHookMessageEx(
            cls,
            sel,
            (IMP)hook_addSoftApClientEvent,
            (IMP *)&orig_addSoftApClientEvent
        );

        HPLog(@"HOOK INSTALLED");
    }
}
