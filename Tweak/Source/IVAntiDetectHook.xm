#import <Foundation/Foundation.h>
#import <substrate.h>
#import <dlfcn.h>
#import <sys/stat.h>
#import <stdio.h>
#import <objc/runtime.h>
#import <errno.h>

static NSArray *sPaths() {
    return @[@"/Applications/Cydia.app",
             @"/Library/MobileSubstrate/MobileSubstrate.dylib",
             @"/Library/MobileSubstrate/DynamicLibraries",
             @"/bin/bash", @"/bin/sh",
             @"/usr/sbin/sshd", @"/usr/bin/ssh", @"/usr/bin/cycript",
             @"/usr/local/bin/cycript",
             @"/usr/libexec/cydia", @"/usr/lib/libcycript.dylib",
             @"/usr/lib/tweak-inject", @"/usr/lib/substrate",
             @"/usr/sbin/dpkg", @"/usr/bin/dpkg",
             @"/private/etc/apt", @"/private/var/lib/cydia", @"/private/var/stash",
             @"/var/cache/apt", @"/var/lib/cydia", @"/var/lib/dpkg", @"/etc/apt"];
}

static NSArray *sSchemes() {
    return @[@"cydia://", @"sileo://", @"zbra://", @"filza://", @"activator://"];
}

static BOOL isJailbreakPath(NSString *path) {
    for (NSString *sp in sPaths()) {
        if ([path hasPrefix:sp]) return YES;
    }
    return NO;
}

static BOOL isJailbreakURL(NSString *url) {
    for (NSString *sc in sSchemes()) {
        if ([url hasPrefix:sc]) return YES;
    }
    return NO;
}

#pragma mark - NSFileManager hooks

typedef BOOL (*origFileExistsFunc)(id, SEL, NSString *);
typedef BOOL (*origFileExistsDirFunc)(id, SEL, NSString *, BOOL *);

static origFileExistsFunc orig_fileExists = NULL;
static origFileExistsDirFunc orig_fileExistsDir = NULL;

static BOOL hook_fileExists(id self, SEL _cmd, NSString *p) {
    if (isJailbreakPath(p)) return NO;
    return orig_fileExists(self, _cmd, p);
}

static BOOL hook_fileExistsDir(id self, SEL _cmd, NSString *p, BOOL *d) {
    if (isJailbreakPath(p)) {
        if (d) *d = NO;
        return NO;
    }
    return orig_fileExistsDir(self, _cmd, p, d);
}

#pragma mark - UIApplication hooks

typedef BOOL (*origCanOpenFunc)(id, SEL, NSURL *);

static origCanOpenFunc orig_canOpen = NULL;

static BOOL hook_canOpen(id self, SEL _cmd, NSURL *u) {
    NSString *s = [u absoluteString];
    if (isJailbreakURL(s)) return NO;
    return orig_canOpen(self, _cmd, u);
}

#pragma mark - C function hooks

static int (*o_stat)(const char*, struct stat*);
static int h_stat(const char *p, struct stat *b) {
    if (p) {
        NSString *s = [NSString stringWithUTF8String:p];
        if (isJailbreakPath(s)) { errno = ENOENT; return -1; }
    }
    return o_stat(p, b);
}

static int (*o_lstat)(const char*, struct stat*);
static int h_lstat(const char *p, struct stat *b) {
    if (p) {
        NSString *s = [NSString stringWithUTF8String:p];
        if (isJailbreakPath(s)) { errno = ENOENT; return -1; }
    }
    return o_lstat(p, b);
}

static FILE *(*o_fopen)(const char*, const char*);
static FILE *h_fopen(const char *p, const char *m) {
    if (p) {
        NSString *s = [NSString stringWithUTF8String:p];
        if (isJailbreakPath(s)) return NULL;
    }
    return o_fopen(p, m);
}

static void *(*o_dlopen)(const char*, int);
static void *h_dlopen(const char *p, int m) {
    if (p) {
        NSString *s = [NSString stringWithUTF8String:p];
        if (isJailbreakPath(s)) return NULL;
    }
    return o_dlopen(p, m);
}

__attribute__((constructor))
static void initAntiDetect() {
    Class fmClass = [NSFileManager class];
    Method m1 = class_getInstanceMethod(fmClass, @selector(fileExistsAtPath:));
    orig_fileExists = (origFileExistsFunc)method_getImplementation(m1);
    method_setImplementation(m1, (IMP)hook_fileExists);

    Method m2 = class_getInstanceMethod(fmClass, @selector(fileExistsAtPath:isDirectory:));
    orig_fileExistsDir = (origFileExistsDirFunc)method_getImplementation(m2);
    method_setImplementation(m2, (IMP)hook_fileExistsDir);

    Class appClass = objc_getClass("UIApplication");
    if (appClass) {
        Method m3 = class_getInstanceMethod(appClass, @selector(canOpenURL:));
        if (m3) {
            orig_canOpen = (origCanOpenFunc)method_getImplementation(m3);
            method_setImplementation(m3, (IMP)hook_canOpen);
        }
    }

    MSHookFunction((void*)stat, (void*)h_stat, (void**)&o_stat);
    MSHookFunction((void*)lstat, (void*)h_lstat, (void**)&o_lstat);
    MSHookFunction((void*)fopen, (void*)h_fopen, (void**)&o_fopen);
    MSHookFunction((void*)dlopen, (void*)h_dlopen, (void**)&o_dlopen);

    NSLog(@"[InstaVault] AntiDetect hook installed");
}
