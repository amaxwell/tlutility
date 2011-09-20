//
//  TLMPreferenceController.m
//  TeX Live Utility
//
//  Created by Adam Maxwell on 12/08/08.
/*
 This software is Copyright (c) 2008-2011
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

#import "TLMPreferenceController.h"
#import "TLMURLFormatter.h"
#import "TLMLogServer.h"
#import "TLMTask.h"
#import "TLMDownload.h"
#import "TLMReadWriteOperationQueue.h"
#import "TLMOptionOperation.h"
#import "TLMEnvironment.h"
#import <pthread.h>

NSString * const TLMTexBinPathPreferenceKey = @"TLMTexBinPathPreferenceKey";       /* /usr/texbin                      */
NSString * const TLMUseRootHomePreferenceKey = @"TLMUseRootHomePreferenceKey";     /* YES                              */
NSString * const TLMInfraPathPreferenceKey = @"TLMInfraPathPreferenceKey";         /* update-tlmgr-latest.sh           */
NSString * const TLMUseSyslogPreferenceKey = @"TLMUseSyslogPreferenceKey";         /* NO                               */
NSString * const TLMFullServerURLPreferenceKey = @"TLMFullServerURLPreferenceKey"; /* composed URL                     */
NSString * const TLMDisableVersionMismatchWarningKey = @"TLMDisableVersionMismatchWarningKey"; /* NO                   */
NSString * const TLMAutoInstallPreferenceKey = @"TLMAutoInstallPreferenceKey";     /* YES (2009 only)                  */
NSString * const TLMAutoRemovePreferenceKey = @"TLMAutoRemovePreferenceKey";       /* YES (2009 only)                  */
NSString * const TLMSetCommandLineServerPreferenceKey = @"TLMSetCommandLineServerPreferenceKey"; /* NO                 */
NSString * const TLMNetInstallerPathPreferenceKey = @"TLMNetInstallerPathPreferenceKey"; /* install-tl-unx.tar.gz      */
NSString * const TLMShouldListTLCritical = @"TLMShouldListTLCritical";             /* NO (obsolete)                    */
NSString * const TLMTLCriticalRepository = @"TLMTLCriticalRepository";             /* ftp://tug.org/texlive/tlcritical */
NSString * const TLMEnableNetInstall = @"TLMEnableNetInstall";                     /* NO                               */
NSString * const TLMShowLogWindowPreferenceKey = @"TLMShowLogWindowPreferenceKey"; /* NO                               */

#define URL_TIMEOUT   30.0

@implementation TLMPreferenceController

@synthesize _texbinPathControl;
@synthesize _rootHomeCheckBox;
@synthesize _useSyslogCheckBox;
@synthesize _autoremoveCheckBox;
@synthesize _autoinstallCheckBox;

// Do not use directly!  File scope only because pthread_once doesn't take an argument.
static id _sharedInstance = nil;
static void __TLMPrefControllerInit() { _sharedInstance = [TLMPreferenceController new]; }

+ (TLMPreferenceController *)sharedPreferenceController;
{
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    (void) pthread_once(&once, __TLMPrefControllerInit);
    return _sharedInstance;
}

- (id)init
{
    return [self initWithWindowNibName:[self windowNibName]];
}

- (void)dealloc
{
    [_texbinPathControl release];
    [_rootHomeCheckBox release];
    [_useSyslogCheckBox release];
    [_autoremoveCheckBox release];
    [_autoinstallCheckBox release];
    [super dealloc];
}

- (void)updateUI
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [_rootHomeCheckBox setState:[defaults boolForKey:TLMUseRootHomePreferenceKey]];
    [_useSyslogCheckBox setState:[defaults boolForKey:TLMUseSyslogPreferenceKey]];
    [_autoinstallCheckBox setState:[defaults boolForKey:TLMAutoInstallPreferenceKey]];
    [_autoremoveCheckBox setState:[defaults boolForKey:TLMAutoRemovePreferenceKey]];   
}

- (void)windowDidBecomeMain:(NSNotification *)notification
{
    // account for possible TeXDist prefpane changes (this was for TL 2008 vs. 2009 differences)
    [self updateUI];
}

- (void)awakeFromNib
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *texbinPath = [defaults objectForKey:TLMTexBinPathPreferenceKey];
    [_texbinPathControl setURL:[NSURL fileURLWithPath:texbinPath]];    
    [self updateUI];    
}

- (IBAction)toggleUseRootHome:(id)sender;
{
    [[NSUserDefaults standardUserDefaults] setBool:([sender state] == NSOnState) forKey:TLMUseRootHomePreferenceKey];
}

- (IBAction)toggleUseSyslog:(id)sender;
{
    [[NSUserDefaults standardUserDefaults] setBool:([sender state] == NSOnState) forKey:TLMUseSyslogPreferenceKey];
}

- (IBAction)toggleAutoinstall:(id)sender;
{
    [[NSUserDefaults standardUserDefaults] setBool:([sender state] == NSOnState) forKey:TLMAutoInstallPreferenceKey];
}

- (IBAction)toggleAutoremove:(id)sender;
{
    [[NSUserDefaults standardUserDefaults] setBool:([sender state] == NSOnState) forKey:TLMAutoRemovePreferenceKey];
}

- (void)updateTeXBinPathWithURL:(NSURL *)aURL
{
    [_texbinPathControl setURL:aURL];
    [[NSUserDefaults standardUserDefaults] setObject:[aURL path] forKey:TLMTexBinPathPreferenceKey];
            
    // update environment, or tlmgr will be non-functional
    [TLMEnvironment updateEnvironment];

    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:TLMDisableVersionMismatchWarningKey];
    [self updateUI];
}

- (void)openPanelDidEnd:(NSOpenPanel*)panel returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    [panel orderOut:self];
    
    if (NSOKButton == returnCode) {
        [self updateTeXBinPathWithURL:[panel URL]];
    }
}

// 10.6 and later
- (BOOL)panel:(id)sender validateURL:(NSURL *)url error:(NSError **)outError
{
    if (NO == [TLMEnvironment isValidTexbinPath:[url path]]) {
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
        [userInfo setObject:url forKey:NSURLErrorKey];
        [userInfo setObject:NSLocalizedString(@"Necessary programs for TeX Live do not exist in that folder", @"alert title in preferences") forKey:NSLocalizedDescriptionKey];
        [userInfo setObject:NSLocalizedString(@"The tlmgr and kpsewhich tools must be present in this folder for basic functionality.", @"alert message text in preferences") forKey:NSLocalizedRecoverySuggestionErrorKey];
        if (outError) *outError = [NSError errorWithDomain:@"com.googlecode.mactlmgr.errors" code:1 userInfo:userInfo];
        return NO;
    }
    return YES;
}

// 10.5
- (BOOL)panel:(id)sender isValidFilename:(NSString *)filename;
{
    return [TLMEnvironment isValidTexbinPath:filename];
}

- (IBAction)changeTexBinPath:(id)sender
{
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    [openPanel setCanChooseDirectories:YES];
    // avoid resolving symlinks
    [openPanel setResolvesAliases:NO];
    [openPanel setCanChooseFiles:NO];
    [openPanel setAllowsMultipleSelection:NO];
    [openPanel setPrompt:NSLocalizedString(@"Choose", @"button title in open panel (must be short)")];
    [openPanel setDelegate:self];
    [openPanel beginSheetForDirectory:@"/usr" file:nil 
                       modalForWindow:[self window] modalDelegate:self 
                       didEndSelector:@selector(openPanelDidEnd:returnCode:contextInfo:) contextInfo:NULL];
}

- (NSString *)windowNibName { return @"Preferences"; }

// make sure to end editing on close
- (BOOL)windowShouldClose:(id)sender;
{
    return [[self window] makeFirstResponder:nil];
}

#pragma mark Path control delegate

- (NSDragOperation)pathControl:(NSPathControl*)pathControl validateDrop:(id <NSDraggingInfo>)info
{
    NSURL *dragURL = [NSURL URLFromPasteboard:[info draggingPasteboard]];
    BOOL isDir = NO;
    if (dragURL)
        [[NSFileManager defaultManager] fileExistsAtPath:[dragURL path] isDirectory:&isDir];
    return isDir ? NSDragOperationCopy : NSDragOperationNone;
}

-(BOOL)pathControl:(NSPathControl*)pathControl acceptDrop:(id <NSDraggingInfo>)info
{
    NSURL *dragURL = [NSURL URLFromPasteboard:[info draggingPasteboard]];
    if (dragURL) [self updateTeXBinPathWithURL:dragURL];
    return (nil != dragURL);
}

@end
