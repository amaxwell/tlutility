//
//  TLUNotifier.m
//  TLUNotifier
//
//  Created by Adam R. Maxwell on 08/09/12.
/*
 This software is Copyright (c) 2012
 Adam Maxwell. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:
 
 - Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 
 - Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in
 the documentation and/or other materials provided with the
 distribution.
 
 - Neither the name of Adam Maxwell nor the names of any
 contributors may be used to endorse or promote products derived
 from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "TLUNotifier.h"


#define TLU_BUNDLE "com.googlecode.mactlmgr.tlu"

@implementation TLUNotifier

#ifdef MAC_OS_X_VERSION_10_8

@synthesize repository = _repository;

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification;
{
    if ([notification activationType] == NSUserNotificationActivationTypeActionButtonClicked) {
        NSRunningApplication *targetApplication = [[NSRunningApplication runningApplicationsWithBundleIdentifier:@TLU_BUNDLE] lastObject];
        if (targetApplication) {
            NSLog(@"TeX Live Utility is already running; sending kAEGetURL");
            pid_t targetPID = [targetApplication processIdentifier];
            NSAppleEventDescriptor *tluProcess = [NSAppleEventDescriptor descriptorWithDescriptorType:typeKernelProcessID
                                                                                                bytes:&targetPID
                                                                                                length:sizeof(targetPID)];
            NSAppleEventDescriptor *event = [NSAppleEventDescriptor appleEventWithEventClass:kInternetEventClass
                                                                                     eventID:kAEGetURL
                                                                            targetDescriptor:tluProcess
                                                                                    returnID:kAutoGenerateReturnID
                                                                               transactionID:kAnyTransactionID];
            NSAppleEventDescriptor *keyDesc = [NSAppleEventDescriptor descriptorWithString:[[self repository] absoluteString]];
            [event setParamDescriptor:keyDesc forKeyword:keyDirectObject];
            OSStatus err = AESendMessage([event aeDesc], NULL, kAENoReply, 0);
            
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated"
            if (noErr != err)
                NSLog(@"Failed to send URL to TeX Live Utility with error %s", GetMacOSStatusErrorString(err));
#pragma clang diagnostic pop

        }
        else {
            CFURLRef appURL;
            if (noErr == LSFindApplicationForInfo(kLSUnknownCreator, CFSTR(TLU_BUNDLE), NULL, NULL, &appURL)) {
                LSLaunchURLSpec spec;
                memset(&spec, 0, sizeof(LSLaunchURLSpec));
                spec.appURL = appURL;
                spec.itemURLs = (__bridge CFArrayRef)[NSArray arrayWithObjects:[self repository], nil];
                LSOpenFromURLSpec(&spec, NULL);
            }
            else {
                NSLog(@"Unable to find TeX Live Utility");
            }
        }
    }
}

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification;
{
    // don't present if TLU is frontmost
    NSRunningApplication *tlu = [[NSRunningApplication runningApplicationsWithBundleIdentifier:@TLU_BUNDLE] lastObject];
    return [tlu isActive] == NO;
}

- (void)_notifyUser
{
    NSUserNotificationCenter *nc = [NSUserNotificationCenter defaultUserNotificationCenter];
    NSUserNotification *note = [NSUserNotification new];
    
    [nc setDelegate:self];
    [note setTitle:NSLocalizedString(@"TeX Live Updates", @"alert title")];
    [note setInformativeText:NSLocalizedString(@"Launch TeX Live Utility to install updates", @"alert message")];
    [note setHasActionButton:YES];
    [note setActionButtonTitle:NSLocalizedString(@"Launch", @"Button title")];
    [note setOtherButtonTitle:NSLocalizedString(@"Ignore", @"Button title")];
    [nc deliverNotification:note];
    
}

- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent
{
    NSAppleEventDescriptor *desc = [event numberOfItems] ? [event descriptorAtIndex:1] : nil;
    [self setRepository:([desc stringValue] ? [NSURL URLWithString:[desc stringValue]] : nil)];
    // logging since this is failing for reasons I don't understand
    NSLog(@"Received AE %@", desc);
    [self _notifyUser];
}

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification
{
    /*
     Likely only a problem on my development system, but I had 3 instances of
     this running one morning, and each one launched a separate instance of TLU,
     which was kind of hilarious.
     */
    NSMutableArray *runningNotifiers = [[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.googlecode.mactlmgr.TLUNotifier"] mutableCopy];
    [runningNotifiers removeObject:[NSRunningApplication currentApplication]];
    if ([runningNotifiers count])
        NSLog(@"Terminating %lu previously launched instances of TLUNotifier", [runningNotifiers count]);
    [runningNotifiers makeObjectsPerformSelector:@selector(terminate)];
    [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self
                                                       andSelector:@selector(handleGetURLEvent:withReplyEvent:)
                                                     forEventClass:kInternetEventClass
                                                        andEventID:kAEGetURL];
}

#endif // 10.8

@end
