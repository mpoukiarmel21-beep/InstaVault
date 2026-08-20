#import <Foundation/Foundation.h>
#import <substrate.h>
static NSArray *sPaths(){return @[@"/Applications/Cydia.app",@"/Library/MobileSubstrate/MobileSubstrate.dylib",@"/Library/MobileSubstrate/DynamicLibraries",@"/bin/bash",@"/bin/sh",@"/usr/sbin/sshd",@"/usr/bin/ssh",@"/usr/bin/cycript",@"/usr/local/bin/cycript",@"/usr/libexec/cydia",@"/usr/lib/libcycript.dylib",@"/usr/lib/tweak-inject",@"/usr/lib/substrate",@"/usr/sbin/dpkg",@"/usr/bin/dpkg",@"/private/etc/apt",@"/private/var/lib/cydia",@"/private/var/stash",@"/var/cache/apt",@"/var/lib/cydia",@"/var/lib/dpkg",@"/etc/apt"];}
static NSArray *sSchemes(){return @[@"cydia://",@"sileo://",@"zbra://",@"filza://",@"activator://"];}
%hook NSFileManager
- (BOOL)fileExistsAtPath:(NSString *)p{for(NSString *s in sPaths())if([p hasPrefix:s])return NO;return %orig;}
- (BOOL)fileExistsAtPath:(NSString *)p isDirectory:(BOOL *)d{for(NSString *s in sPaths())if([p hasPrefix:s]){if(d)*d=NO;return NO;}return %orig;}
%end
%hook UIApplication
- (BOOL)canOpenURL:(NSURL *)u{NSString *s=[u absoluteString];for(NSString *sc in sSchemes())if([s hasPrefix:sc])return NO;return %orig;}
%end
static int (*o_stat)(const char*,struct stat*);static int h_stat(const char*p,struct stat*b){if(p){NSString *s=[NSString stringWithUTF8String:p];for(NSString *sp in sPaths())if([s hasPrefix:sp]){errno=ENOENT;return -1;}}return o_stat(p,b);}
static int (*o_lstat)(const char*,struct stat*);static int h_lstat(const char*p,struct stat*b){if(p){NSString *s=[NSString stringWithUTF8String:p];for(NSString *sp in sPaths())if([s hasPrefix:sp]){errno=ENOENT;return -1;}}return o_lstat(p,b);}
static FILE *(*o_fopen)(const char*,const char*);static FILE*h_fopen(const char*p,const char*m){if(p){NSString *s=[NSString stringWithUTF8String:p];for(NSString *sp in sPaths())if([s hasPrefix:sp])return NULL;}return o_fopen(p,m);}
static void*(*o_dlopen)(const char*,int);static void*h_dlopen(const char*p,int m){if(p){NSString *s=[NSString stringWithUTF8String:p];for(NSString *sp in sPaths())if([s hasPrefix:sp])return NULL;}return o_dlopen(p,m);}
%ctor{MSHookFunction((void*)stat,(void*)h_stat,(void**)&o_stat);MSHookFunction((void*)lstat,(void*)h_lstat,(void**)&o_lstat);MSHookFunction((void*)fopen,(void*)h_fopen,(void**)&o_fopen);MSHookFunction((void*)dlopen,(void*)h_dlopen,(void**)&o_dlopen);NSLog(@"[InstaVault] AntiDetect");}
