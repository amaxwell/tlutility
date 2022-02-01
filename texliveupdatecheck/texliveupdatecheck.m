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
    
    NSArray *packages = [TLMListUpdatesParser packagesFromListUpdatesOutput:[task outputString] atLocationURL:actualRepository];

    return [packages count];
}

int main(int argc, const char * argv[]) {
    
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
        
    NSDictionary *sessionInfo = [(NSDictionary *)CGSessionCopyCurrentDictionary() autorelease];
    if (nil == sessionInfo)
        return 0;
    
    // not running as console user
    if (nil == [sessionInfo objectForKey:(id)kCGSessionOnConsoleKey])
        return 0;
    
    // login incomplete
    if (nil == [sessionInfo objectForKey:(id)kCGSessionLoginDoneKey])
        return 0;
    
    // display is captured; no point in continuing
    if (CGDisplayIsCaptured(CGMainDisplayID()))
        return 0;
    
    NSString *texbinPath = [(id)CFPreferencesCopyAppValue(CFSTR("TLMTexBinPathPreferenceKey"), CFSTR("com.googlecode.mactlmgr.tlu")) autorelease];
    
    // default from TLMAppController
    if (nil == texbinPath)
        texbinPath = (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber10_10) ? @"/Library/TeX/texbin" : @"/usr/texbin";
    
    NSString *repositoryString = [(id)CFPreferencesCopyAppValue(CFSTR("TLMFullServerURLPreferenceKey"), CFSTR("com.googlecode.mactlmgr.tlu")) autorelease];
    
    // default from TLMAppController
    if (nil == repositoryString)
        repositoryString = @"https://mirror.ctan.org/systems/texlive/tlnet";
    
    NSURL *actualRepository = NULL;
    NSInteger updateCount = check_for_updates([texbinPath stringByAppendingPathComponent:@"tlmgr"], [NSURL URLWithString:repositoryString], &actualRepository);
    
    if (0 == updateCount)
        return 0;
    
    CFURLRef tlnURL;
    OSStatus ret;
    ret = LSFindApplicationForInfo(kLSUnknownCreator, CFSTR("com.googlecode.mactlmgr.TLUNotifier"), NULL, NULL, &tlnURL);
    if (noErr == ret) {
        LSLaunchURLSpec launchSpec;
        launchSpec.appURL = tlnURL;
        launchSpec.itemURLs = actualRepository ? (CFArrayRef)[NSArray arrayWithObject:actualRepository] : NULL;
        ret = LSOpenFromURLSpec(&launchSpec, NULL);
        if (ret)
            NSLog(@"Unable to find and launch TLUNotifier; LSOpenFromURLSpec returned %d", ret);
    }
        
    [pool release];
    return 0;
}
