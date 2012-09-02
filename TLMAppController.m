//
//  TLMAppController.m
//  TeX Live Utility
//
//  Created by Adam Maxwell on 12/6/08.
/*
 This software is Copyright (c) 2008-2012
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

#import "TLMAppController.h"
#import "TLMMainWindowController.h"
#import "TLMPreferenceController.h"
#import "TLMLogServer.h"
#import "TLMReleaseNotesController.h"
#import "TLMTask.h"
#import <Sparkle/Sparkle.h>
#import "TLMProxyManager.h"
#import "TLMDatabase.h"
#import "TLMMirrorController.h"
#import "TLMEnvironment.h"
#import "TLMLogWindowController.h"
#import "TLMSizeFormatter.h"

@implementation TLMAppController

@synthesize _installMenuItem;

static void __TLMMigrateBundleIdentifier()
{
    NSString *updateKey = @"TLMDidMigratePreferencesKey";
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:updateKey] == NO) {
        
        /*
         The old bundle identifier was "com.google.mactlmgr.TeX_Live_Utility", which is an incorrect domain and annoying to type.
         We need to preserve previously-set preferences, though, including all of the window frame/nav services defaults for which 
         we don't know the keys.  Note that CFPreferencesCopyMultiple() returns an empty dictionary unless you pass the combination
         kCFPreferencesCurrentUser, kCFPreferencesAnyHost.
         */
        NSDictionary *oldPrefs = [(id)CFPreferencesCopyMultiple(NULL, CFSTR("com.google.mactlmgr.TeX_Live_Utility"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost) autorelease];
        
        // manually copy each key/value pair, since registerDefaults sets them in a volatile domain
        for (id key in oldPrefs)
            [[NSUserDefaults standardUserDefaults] setObject:[oldPrefs objectForKey:key] forKey:key];

        if ([oldPrefs count])
            NSLog(@"Migrated preferences = %@", oldPrefs);
        
        // force synchronization to disk, so we never have to do this again
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:updateKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

+ (void)initialize
{
    static bool didInit = false;
    if (true == didInit) return;
    didInit = true;
    
    __TLMMigrateBundleIdentifier();
    
    NSString *tlnetDefault = @"http://mirror.ctan.org/systems/texlive/tlnet";
    
    // convert from the old-style composed path to full path, preserving user-specified settings
    NSString *userURL = [[NSUserDefaults standardUserDefaults] objectForKey:@"TLMServerURLPreferenceKey"];
    if (userURL && nil == [[NSUserDefaults standardUserDefaults] objectForKey:TLMFullServerURLPreferenceKey]) {
        
        // path portion of the old default for TL 2008
        NSString *serverPath = @"systems/texlive/tlnet";
        if ([[NSUserDefaults standardUserDefaults] objectForKey:@"TLMServerPathPreferenceKey"])
            serverPath = [[NSUserDefaults standardUserDefaults] objectForKey:@"TLMServerPathPreferenceKey"];
        
        tlnetDefault = [NSString stringWithFormat:@"%@/%@", userURL, serverPath];
        
        // no TLMLog yet
        NSLog(@"Converting old-style URL preference to %@", tlnetDefault);
        
        // set the new value and sync to disk
        [[NSUserDefaults standardUserDefaults] setObject:tlnetDefault forKey:TLMFullServerURLPreferenceKey];
        
        if ([[NSUserDefaults standardUserDefaults] synchronize]) {
            // now remove the old values if we synced successfully
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"TLMServerURLPreferenceKey"];
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"TLMServerPathPreferenceKey"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
    }
    
    NSMutableDictionary *defaults = [NSMutableDictionary dictionary];
    [defaults setObject:tlnetDefault forKey:TLMFullServerURLPreferenceKey];
    
    [defaults setObject:@"/usr/texbin" forKey:TLMTexBinPathPreferenceKey];
    
    [defaults setObject:@"install-tl-unx.tar.gz" forKey:TLMNetInstallerPathPreferenceKey];
    [defaults setObject:@"update-tlmgr-latest.sh" forKey:TLMInfraPathPreferenceKey];
    
    // causes syslog performance problems if enabled by default
    [defaults setObject:[NSNumber numberWithBool:NO] forKey:TLMUseSyslogPreferenceKey];
    
    // user-settable from alert sheet; resets itself on various pref changes
    [defaults setObject:[NSNumber numberWithBool:NO] forKey:TLMDisableVersionMismatchWarningKey];
    
    // set to YES for compatibility with tlmgr default behavior
    [defaults setObject:[NSNumber numberWithBool:YES] forKey:TLMAutoInstallPreferenceKey];
    [defaults setObject:[NSNumber numberWithBool:YES] forKey:TLMAutoRemovePreferenceKey];
    
    // disable TL critical repo by default
    [defaults setObject:[NSNumber numberWithBool:NO] forKey:TLMShouldListTLCritical];
    [defaults setObject:@"ftp://tug.org/texlive/tlcritical" forKey:TLMTLCriticalRepository];
    
    // no UI for this at present
    [defaults setObject:[NSNumber numberWithBool:NO] forKey:TLMEnableNetInstall];
    
    // Lion only: http://lists.apple.com/archives/cocoa-dev/2011/Sep/msg00914.html
    [defaults setObject:[NSNumber numberWithBool:YES] forKey:@"NSApplicationShowExceptions"];
    
    // only useful in TL 2012 and later
    [defaults setObject:[NSNumber numberWithInt:0] forKey:TLMLastUpdmapVersionShownKey];
    [defaults setObject:[NSNumber numberWithBool:NO] forKey:TLMEnableUserUpdmapPreferenceKey];
    [defaults setObject:[NSNumber numberWithBool:NO] forKey:TLMDisableUpdmapAlertPreferenceKey];
    
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];   
}

- (void)dealloc
{
    [_mainWindowController release];
    [_aevtUpdateURL release];
    [_sparkleUpdateInvocation release];
    [_installMenuItem release];
    [super dealloc];
}

- (void)awakeFromNib
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:TLMEnableNetInstall] == NO) {
        [[_installMenuItem menu] removeItem:_installMenuItem];
    }
}

- (void)_killNotifier
{
    if (floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_7) {
        NSArray *runningNotifiers = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.googlecode.mactlmgr.TLUNotifier"];
        if ([runningNotifiers count])
            TLMLog(__func__, @"Terminating %ld instance(s) of TLUNotifier.app in case of update", (unsigned long)[runningNotifiers count]);
        [runningNotifiers makeObjectsPerformSelector:@selector(terminate)];
    }
}    

- (void)_setSparkleUpdateInvocation:(NSInvocation *)inv
{
    if (inv != _sparkleUpdateInvocation) {
        [_sparkleUpdateInvocation release];
        _sparkleUpdateInvocation = [inv retain];
    }
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag
{
    [[self mainWindowController] showWindow:nil];
    // let NSApp order in the log window if needed
    return flag;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    return ([[self mainWindowController] windowShouldClose:sender]) ? NSTerminateNow : NSTerminateCancel;
}

// Return YES to delay the relaunch until you do some processing; invoke the given NSInvocation to continue.
- (BOOL)updater:(SUUpdater *)updater shouldPostponeRelaunchForUpdate:(SUAppcastItem *)update untilInvoking:(NSInvocation *)invocation;
{
    if ([[self mainWindowController] windowShouldClose:nil] == NO) {
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"Unable to relaunch", "alert title")];
        [alert setInformativeText:NSLocalizedString(@"You will need to manually quit and relaunch TeX Live Utility to complete installation of the new version.", @"alert text")];
        [alert runModal];
        TLMLog(__func__, @"Delaying update and relaunch since the main window was busy");
        
        // thought about invoking this when all operations are finished, but not sure that's a good idea...
        [self _setSparkleUpdateInvocation:invocation];
        [_sparkleUpdateInvocation autorelease];
        _sparkleUpdateInvocation = [invocation retain];
        return YES;
    }
    /*
     Relaunch fails if we have a sheet attached to the main window, as in the case of infra update alert.
     Try closing the sheet, since the user has chosen to do the app update, and presumably doesn't want
     to do an infra update.
     */
    for (NSWindow *window in [NSApp windows]) {
        NSWindow *sheet = [window attachedSheet];
        if (sheet)
            [NSApp endSheet:sheet returnCode:NSRunAbortedResponse];
    }
    [self _killNotifier];
    return NO;
}

- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent
{
    [_aevtUpdateURL autorelease];
    NSAppleEventDescriptor *desc = [event numberOfItems] ? [event descriptorAtIndex:1] : nil;
    _aevtUpdateURL = [desc stringValue] ? [[NSURL alloc] initWithString:[desc stringValue]] : nil;
    TLMLog(__func__, @"Requesting listing from location %@", [_aevtUpdateURL absoluteString]);
    [[self mainWindowController] showWindow:nil];
    [[self mainWindowController] refreshUpdatedPackageListWithURL:_aevtUpdateURL];
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification;
{
    [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self
                                                       andSelector:@selector(handleGetURLEvent:withReplyEvent:)
                                                     forEventClass:kInternetEventClass
                                                        andEventID:kAEGetURL];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification;
{
    // make sure this gets hooked up early enough that it collects messages
    if (nil == _logWindowController)
        _logWindowController = [TLMLogWindowController new];
    
    NSDictionary *infoPlist = [[NSBundle mainBundle] infoDictionary];
    NSProcessInfo *pInfo = [NSProcessInfo processInfo];
    NSFormatter *memsizeFormatter = [[TLMSizeFormatter new] autorelease];
    NSString *memsize = [memsizeFormatter stringForObjectValue:[NSNumber numberWithUnsignedLongLong:[pInfo physicalMemory]]];
    TLMLog(__func__, @"Welcome to %@ %@, running under Mac OS X %@ with %lu/%lu processors active and %@ physical memory.", [infoPlist objectForKey:(id)kCFBundleNameKey], [infoPlist objectForKey:(id)kCFBundleVersionKey], [pInfo operatingSystemVersionString], (unsigned long)[pInfo activeProcessorCount], (unsigned long)[pInfo processorCount], memsize);
        
    // call before anything uses tlmgr
    [[TLMProxyManager sharedManager] updateProxyEnvironmentForURL:nil];
    
    // make sure this is set up early enough to use tasks anywhere
    [TLMEnvironment updateEnvironment]; 
    
    /*
     Show before main window, so the main window is key when we finish launching,
     and keyboard shortcuts can be used right away.  I'd rather have the main
     window show up first, but forcing it to makeKeyAndOrderFront after opening
     is more jarring than having the log window open first.
     */
    if ([[NSUserDefaults standardUserDefaults] boolForKey:TLMShowLogWindowPreferenceKey])
        [self showLogWindow:nil];
    
    if (nil == _aevtUpdateURL) {
        [[self mainWindowController] showWindow:nil];
#if DEBUG
#warning disabled auto refresh
#else
        [[self mainWindowController] refreshUpdatedPackageList];
#endif
        [[self mainWindowController] checkSystemPaperSize];
    }
    else if ([NSApp isActive] && [[NSUserDefaults standardUserDefaults] boolForKey:TLMShowLogWindowPreferenceKey]) {
        [[[self mainWindowController] window] makeKeyAndOrderFront:nil];
    }

    if (floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_7) {
        // NB: have to include the .app extension here
        NSString *notifierPath = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"TLUNotifier.app"];
        if (notifierPath)
            LSRegisterURL((CFURLRef)[NSURL fileURLWithPath:notifierPath], TRUE);        
    }    
}

- (TLMMainWindowController *)mainWindowController { 
    if (nil == _mainWindowController)
        _mainWindowController = [[TLMMainWindowController alloc] init];
    return _mainWindowController; 
}

- (IBAction)newDocument:(id)sender
{
    [[self mainWindowController] showWindow:sender];
}

- (IBAction)showPreferences:(id)sender
{
    [[TLMPreferenceController sharedPreferenceController] showWindow:nil];
}

- (TLMMirrorController *)mirrorController
{
    if (nil == _mirrorController)
        _mirrorController = [TLMMirrorController new];
    return _mirrorController;
}

- (TLMLogWindowController *)logWindowController
{
    return _logWindowController;
}

- (IBAction)manageMirrors:(id)sender
{
    [[self mirrorController] showWindow:sender];
}

- (IBAction)showLogWindow:(id)sender
{
    [_logWindowController showWindow:sender];
}

#pragma mark Help Menu

- (IBAction)openDisasterRecoveryPage:(id)sender
{
    NSURL *aURL = [NSURL URLWithString:@"http://tug.org/texlive/tlmgr.html"];
    [[NSWorkspace sharedWorkspace] openURL:aURL];
}

- (IBAction)openTLUWiki:(id)sender;
{
    NSURL *aURL = [NSURL URLWithString:@"http://code.google.com/p/mactlmgr/w/list"];
    [[NSWorkspace sharedWorkspace] openURL:aURL];    
}

- (IBAction)openMacTeXWiki:(id)sender;
{
    NSURL *aURL = [NSURL URLWithString:@"http://mactex-wiki.tug.org"];
    [[NSWorkspace sharedWorkspace] openURL:aURL];
}

- (IBAction)openTracker:(id)sender;
{
    NSURL *aURL = [NSURL URLWithString:@"http://code.google.com/p/mactlmgr/issues/list"];
    [[NSWorkspace sharedWorkspace] openURL:aURL];
}

- (IBAction)openReleaseNotes:(id)sender;
{
    [[TLMReleaseNotesController sharedInstance] showWindow:nil];
}

#pragma mark -

#if 0

- (SUAppcastItem *)bestValidUpdateInAppcast:(SUAppcast *)appcast forUpdater:(SUUpdater *)updater;
{
    SUAppcastItem *item;
    NSUInteger year = [[self class] texliveYear];
    
    for (item in [appcast items]) {
    
        // find newest version corresponding to this TL release
        
    }

    return item;
}

#endif

#if 0

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename;
{
    NSString *source = 
    @"tell application \"System Preferences\"\r"
        @"activate\r"
        @"set current pane to pane \"comp.text.tex.distribution.preference\"\r"
    @"end tell";
    NSAppleScript *script = [[[NSAppleScript alloc] initWithSource:source] autorelease];
    NSDictionary *error = nil;  
    id ret = [script executeAndReturnError:&error];
    if (nil == ret)
        NSLog(@"Failed to compile script: %@", error);
    return (nil != ret);
}

#endif

@end
