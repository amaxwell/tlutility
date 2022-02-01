//
//  main.m
//  texliveupdatecheck
//
//  Created by Maxwell, Adam R on 2/1/22.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "TLMTask.h"

NSInteger check_for_updates(NSString *tlmgrAbsolutePath, NSURL *repository, NSURL **actualRepository)
{
    NSCParameterAssert(NULL != actualRepository);
    *actualRepository = NULL;
    
    return 0;
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
    
    if (NULL == texbinPath)
        return 1;
    
    NSString *repository = [(id)CFPreferencesCopyAppValue(CFSTR("TLMFullServerURLPreferenceKey"), CFSTR("com.googlecode.mactlmgr.tlu")) autorelease];
    
    NSURL *actualRepository = NULL;
    NSInteger updateCount = check_for_updates([texbinPath stringByAppendingPathComponent:@"tlmgr"], [NSURL URLWithString:repository], &actualRepository);
    
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
