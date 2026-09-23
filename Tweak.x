#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <unistd.h>
#import <stdio.h>

static FILE *OpenLog(void)
{
    FILE *f = fopen("/tmp/HotspotProbeV8.log", "a");

    if (!f)
        f = fopen("/var/tmp/HotspotProbeV8.log", "a");

    return f;
}

static void LogLine(FILE *f, NSString *line)
{
    if (!f || !line)
        return;

    fprintf(f, "%s\n", line.UTF8String);
    fflush(f);
}

static void DumpMethod(
    FILE *f,
    NSString *className,
    NSString *selectorName
)
{
    Class cls = objc_getClass(className.UTF8String);

    if (!cls) {
        LogLine(
            f,
            [NSString stringWithFormat:
             @"CLASS NOT FOUND: %@",
             className]
        );
        return;
    }

    SEL sel = NSSelectorFromString(selectorName);

    Method method =
        class_getInstanceMethod(cls, sel);

    if (!method) {
        LogLine(
            f,
            [NSString stringWithFormat:
             @"METHOD NOT FOUND: -[%@ %@]",
             className,
             selectorName]
        );
        return;
    }

    const char *encoding =
        method_getTypeEncoding(method);

    unsigned int count =
        method_getNumberOfArguments(method);

    LogLine(f, @"========================================");

    LogLine(
        f,
        [NSString stringWithFormat:
         @"METHOD: -[%@ %@]",
         className,
         selectorName]
    );

    LogLine(
        f,
        [NSString stringWithFormat:
         @"ENCODING: %s",
         encoding ? encoding : "(null)"]
    );

    LogLine(
        f,
        [NSString stringWithFormat:
         @"ARGUMENT COUNT: %u",
         count]
    );

    char returnType[256] = {0};

    method_getReturnType(
        method,
        returnType,
        sizeof(returnType)
    );

    LogLine(
        f,
        [NSString stringWithFormat:
         @"RETURN: %s",
         returnType]
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
            f,
            [NSString stringWithFormat:
             @"ARG %u: %s",
             i,
             type]
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

        FILE *f = OpenLog();

        if (!f)
            return;

        LogLine(
            f,
            [NSString stringWithFormat:
             @"===== HotspotProbe V8 pid=%d =====",
             getpid()]
        );

        DumpMethod(
            f,
            @"WiFiUsageSoftApSession",
            @"softApStateDidChange:requester:status:changeReason:channelNumber:countryCode:isHidden:isInfraConnected:isAwdlUp:lowPowerModeDuration:compatibilityMode:requestToUpLatency:"
        );

        LogLine(f, @"[END]");

        fclose(f);
    }
}
