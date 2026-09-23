#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <unistd.h>
#import <stdio.h>
#import <string.h>

static BOOL HPContainsInterestingText(NSString *text) {
    if (!text) return NO;

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
        if ([s containsString:key]) return YES;
    }
    return NO;
}

static void HPWriteLine(FILE *f, NSString *line) {
    if (!f || !line) return;
    fprintf(f, "%s\n", line.UTF8String);
    fflush(f);
}

__attribute__((constructor))
static void HPInit(void) {
    @autoreleasepool {
        NSString *proc = [NSProcessInfo processInfo].processName ?: @"unknown";
        if (!([proc isEqualToString:@"misd"] ||
              [proc isEqualToString:@"sharingd"] ||
              [proc isEqualToString:@"wifid"])) {
            return;
        }

        const char *logPath = "/var/mobile/HotspotProbe.log";
        FILE *f = fopen(logPath, "a");
        if (!f) return;

        NSDateFormatter *fmt = [NSDateFormatter new];
        fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss Z";

        HPWriteLine(f, @"");
        HPWriteLine(f, @"============================================================");
        HPWriteLine(f, [NSString stringWithFormat:@"PROCESS=%@ PID=%d TIME=%@",
                        proc, getpid(), [fmt stringFromDate:[NSDate date]]]);
        HPWriteLine(f, @"============================================================");

        HPWriteLine(f, @"[LOADED IMAGES]");
        uint32_t imageCount = _dyld_image_count();
        for (uint32_t i = 0; i < imageCount; i++) {
            const char *name = _dyld_get_image_name(i);
            if (!name) continue;
            NSString *path = [NSString stringWithUTF8String:name];
            if (HPContainsInterestingText(path)) {
                HPWriteLine(f, path);
            }
        }

        HPWriteLine(f, @"");
        HPWriteLine(f, @"[INTERESTING OBJC CLASSES / METHODS]");

        unsigned int classCount = 0;
        Class *classes = objc_copyClassList(&classCount);
        if (!classes) {
            HPWriteLine(f, @"objc_copyClassList failed");
            fclose(f);
            return;
        }

        for (unsigned int i = 0; i < classCount; i++) {
            Class cls = classes[i];
            NSString *className = NSStringFromClass(cls);
            BOOL classHit = HPContainsInterestingText(className);

            unsigned int methodCount = 0;
            Method *methods = class_copyMethodList(cls, &methodCount);

            for (unsigned int m = 0; m < methodCount; m++) {
                SEL sel = method_getName(methods[m]);
                NSString *methodName = NSStringFromSelector(sel);
                if (classHit || HPContainsInterestingText(methodName)) {
                    HPWriteLine(f,
                        [NSString stringWithFormat:@"-[%@ %@]",
                         className, methodName]);
                }
            }
            if (methods) free(methods);

            Class meta = object_getClass(cls);
            methodCount = 0;
            methods = class_copyMethodList(meta, &methodCount);

            for (unsigned int m = 0; m < methodCount; m++) {
                SEL sel = method_getName(methods[m]);
                NSString *methodName = NSStringFromSelector(sel);
                if (classHit || HPContainsInterestingText(methodName)) {
                    HPWriteLine(f,
                        [NSString stringWithFormat:@"+[%@ %@]",
                         className, methodName]);
                }
            }
            if (methods) free(methods);
        }

        free(classes);
        HPWriteLine(f, @"[END]");
        fclose(f);
    }
}
