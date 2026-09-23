#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <unistd.h>
#import <stdio.h>

static FILE *HPOpenLog(void) {
    const char *paths[] = {
        "/tmp/HotspotProbe.log",
        "/var/tmp/HotspotProbe.log",
        "/var/mobile/HotspotProbe.log"
    };

    for (unsigned int i = 0;
         i < sizeof(paths) / sizeof(paths[0]);
         i++) {

        FILE *f = fopen(paths[i], "a");

        if (f) {
            fprintf(f, "LOGPATH=%s\n", paths[i]);
            fflush(f);
            return f;
        }
    }

    return NULL;
}

static BOOL HPContainsInterestingText(NSString *text) {
    if (!text)
        return NO;

    NSString *s = [text lowercaseString];

    NSArray<NSString *> *keys = @[
        @"hotspot",
        @"hostap",
        @"tether",
        @"internetsharing",
        @"mobileinternetsharing",
        @"beacon",
        @"vendor",
        @"informationelement",
        @"80211",
        @"wifi",
        @"wireless",
        @"personalhotspot"
    ];

    for (NSString *key in keys) {
        if ([s containsString:key])
            return YES;
    }

    return NO;
}

static void HPWriteLine(FILE *f, NSString *line) {
    if (!f || !line)
        return;

    fprintf(f, "%s\n", line.UTF8String);
    fflush(f);
}

__attribute__((constructor))
static void HPInit(void) {
    @autoreleasepool {

        NSString *proc =
            [NSProcessInfo processInfo].processName ?: @"unknown";

        if (!([proc isEqualToString:@"misd"] ||
              [proc isEqualToString:@"sharingd"] ||
              [proc isEqualToString:@"wifid"])) {
            return;
        }

        FILE *f = HPOpenLog();

        if (!f)
            return;

        HPWriteLine(f, @"");
        HPWriteLine(
            f,
            @"============================================================"
        );

        HPWriteLine(
            f,
            [NSString stringWithFormat:
                @"PROCESS=%@ PID=%d",
                proc,
                getpid()]
        );

        HPWriteLine(
            f,
            @"============================================================"
        );

        HPWriteLine(f, @"[LOADED IMAGES]");

        uint32_t imageCount = _dyld_image_count();

        for (uint32_t i = 0; i < imageCount; i++) {
            const char *name = _dyld_get_image_name(i);

            if (!name)
                continue;

            NSString *path =
                [NSString stringWithUTF8String:name];

            if (HPContainsInterestingText(path)) {
                HPWriteLine(f, path);
            }
        }

        HPWriteLine(
            f,
            @"[INTERESTING OBJC CLASSES / METHODS]"
        );

        unsigned int classCount = 0;

        Class *classes =
            objc_copyClassList(&classCount);

        if (!classes) {
            HPWriteLine(
                f,
                @"objc_copyClassList failed"
            );

            fclose(f);
            return;
        }

        for (unsigned int i = 0;
             i < classCount;
             i++) {

            Class cls = classes[i];

            NSString *className =
                NSStringFromClass(cls);

            BOOL classHit =
                HPContainsInterestingText(className);

            unsigned int methodCount = 0;

            Method *methods =
                class_copyMethodList(
                    cls,
                    &methodCount
                );

            for (unsigned int m = 0;
                 m < methodCount;
                 m++) {

                SEL sel =
                    method_getName(methods[m]);

                NSString *methodName =
                    NSStringFromSelector(sel);

                if (classHit ||
                    HPContainsInterestingText(methodName)) {

                    HPWriteLine(
                        f,
                        [NSString stringWithFormat:
                            @"-[%@ %@]",
                            className,
                            methodName]
                    );
                }
            }

            if (methods)
                free(methods);

            Class meta =
                object_getClass(cls);

            methodCount = 0;

            methods =
                class_copyMethodList(
                    meta,
                    &methodCount
                );

            for (unsigned int m = 0;
                 m < methodCount;
                 m++) {

                SEL sel =
                    method_getName(methods[m]);

                NSString *methodName =
                    NSStringFromSelector(sel);

                if (classHit ||
                    HPContainsInterestingText(methodName)) {

                    HPWriteLine(
                        f,
                        [NSString stringWithFormat:
                            @"+[%@ %@]",
                            className,
                            methodName]
                    );
                }
            }

            if (methods)
                free(methods);
        }

        free(classes);

        HPWriteLine(f, @"[END]");

        fclose(f);
    }
}
