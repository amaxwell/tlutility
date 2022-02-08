//
//  main.m
//  texliveupdatecheck
//
//  Created by Maxwell, Adam R on 2/1/22.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "TLMListUpdatesParser.h"
#import "TLMTask.h"

// parser calls TLMLog, so reimplement as NSLog in this target
void TLMLog(const char *sender, NSString *format, ...)
{
    va_list list;
    va_start(list, format);
    NSString *message = [[[NSString alloc] initWithFormat:format arguments:list] autorelease];
    va_end(list);
    
    NSLog(@"%@", message);
    
}

void TLMLogServerSync()
{
    // do nothing
}

static NSInteger check_for_updates(NSString *tlmgrAbsolutePath, NSURL *repository, NSURL **actualRepository)
{
    NSCParameterAssert(NULL != actualRepository);
    *actualRepository = NULL;
    
    NSArray *options = [NSArray arrayWithObjects:@"--machine-readable", @"--repository", [repository absoluteString], @"update", @"--list", @"--all", nil];
    TLMTask *task = [TLMTask launchedTaskWithLaunchPath:tlmgrAbsolutePath arguments:options];
    [task waitUntilExit];
    
    if ([task terminationStatus])
        return -1;
    
    if (nil == [task outputString])
        NSLog(@"No output from %@ %@: error %@", tlmgrAbsolutePath, [options componentsJoinedByString:@" "], [task errorString]);
    
    NSArray *packages = [TLMListUpdatesParser packagesFromListUpdatesOutput:[task outputString] atLocationURL:actualRepository];

    return [packages count];
}

int main(int argc, const char * argv[]) {
    
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
        
    // some checks since we're likely running in the background as a launchd agent
    NSDictionary *sessionInfo = [(NSDictionary *)CGSessionCopyCurrentDictionary() autorelease];
    if (nil == sessionInfo)
        return 0;
    
    // not running as console user
    if (nil == [sessionInfo objectForKey:(id)kCGSessionOnConsoleKey])
        return 0;
    
    // login incomplete
    if (nil == [sessionInfo objectForKey:(id)kCGSessionLoginDoneKey])
        return 0;
    
    /*
     Used to check CGDisplayIsCaptured(CGMainDisplayID()) here for full screen mode,
     but the call is deprecated with no replacement. The alternative is to use
     NSApplicationPresentationOptions, but then I have to drag in AppKit for a CLI
     tool. The hell with that: post the notification and let the OS figure out if
     it should be displayed or not.
     */
    
    NSString *texbinPath = [(id)CFPreferencesCopyAppValue(CFSTR("TLMTexBinPathPreferenceKey"), CFSTR("com.googlecode.mactlmgr.tlu")) autorelease];
    
    // default from TLMAppController
    if (nil == texbinPath)
        texbinPath = (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber10_10) ? @"/Library/TeX/texbin" : @"/usr/texbin";
    
    NSString *repositoryString = [(id)CFPreferencesCopyAppValue(CFSTR("TLMFullServerURLPreferenceKey"), CFSTR("com.googlecode.mactlmgr.tlu")) autorelease];
    
    // default from TLMAppController
    if (nil == repositoryString)
        repositoryString = @"https://mirror.ctan.org/systems/texlive/tlnet";
    
    NSURL *actualRepository = nil;
    NSInteger updateCount = check_for_updates([texbinPath stringByAppendingPathComponent:@"tlmgr"], [NSURL URLWithString:repositoryString], &actualRepository);
    NSLog(@"Found %ld packages for update from %@", updateCount, actualRepository);
    
    if (0 == updateCount)
        return 0;
    
    // maybe a weird parsing error
    if (nil == actualRepository) {
        NSLog(@"failed to get actual repository");
        return -1;
    }
    
    // try and find a running instance, since Launch Services is screwing up on Mojave and Catalina
    NSArray *runningApplications = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.googlecode.mactlmgr.TLUNotifier"];
    NSURL *tlnURL = [[runningApplications firstObject] bundleURL];
    if (nil == tlnURL)
        tlnURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:@"com.googlecode.mactlmgr.TLUNotifier"];
    NSLog(@"Will send URL %@ to TLUNotifier %@", actualRepository, tlnURL);
    
    if (tlnURL && actualRepository) {
        LSLaunchURLSpec launchSpec;
        memset(&launchSpec, 0, sizeof(LSLaunchURLSpec));
        launchSpec.appURL = (CFURLRef)tlnURL;
        launchSpec.launchFlags = kLSLaunchDefaults;
        launchSpec.itemURLs = actualRepository ? (CFArrayRef)[NSArray arrayWithObject:actualRepository] : NULL;
        OSStatus ret;
        ret = LSOpenFromURLSpec(&launchSpec, NULL);
        if (ret)
            NSLog(@"Unable to find and launch TLUNotifier; LSOpenFromURLSpec returned %d", ret);
    }

    [pool release];
    return 0;
}
