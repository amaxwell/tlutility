//
//  TLMAppController.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/6/08.
/*
 This software is Copyright (c) 2008-2009
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

@implementation TLMAppController

+ (void)initialize
{
    static bool didInit = false;
    if (true == didInit) return;
    didInit = true;
    
    // force setup of the log server
    [TLMLogServer sharedServer];
    
    NSMutableDictionary *defaults = [NSMutableDictionary dictionary];
    // see /usr/local/texlive/2008/tlpkg/TeXLive/TLConfig.pm
    [defaults setObject:@"http://mirror.ctan.org/" forKey:TLMServerURLPreferenceKey];
    [defaults setObject:@"systems/texlive/tlnet/2008" forKey:TLMServerPathPreferenceKey];
    
    [defaults setObject:@"/usr/texbin" forKey:TLMTexBinPathPreferenceKey];
    // typically avoids problems with junk in your home directory
    [defaults setObject:[NSNumber numberWithBool:YES] forKey:TLMUseRootHomePreferenceKey];
    [defaults setObject:@"update-tlmgr-latest.sh" forKey:TLMInfraPathPreferenceKey];
    
    // causes syslog performance problems if enabled by default
    [defaults setObject:[NSNumber numberWithBool:NO] forKey:TLMUseSyslogPreferenceKey];
    
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
    
    // make sure this is set up early enough to use tasks anywhere
    [self updatePathEnvironment];
}

+ (NSMutableArray *)_systemPaths
{
    NSString *str = [NSString stringWithContentsOfFile:@"/etc/paths" encoding:NSUTF8StringEncoding error:NULL];
    NSMutableArray *paths = [NSMutableArray array];
    for (NSString *path in [str componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        path = [path stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([path isEqualToString:@""] == NO)
            [paths addObject:path];
    }
    return paths;
}

+ (void)updatePathEnvironment;
{
    NSString *originalPath = [NSString stringWithUTF8String:getenv("PATH")];
    
    // ??? maybe _systemPaths should be the default, and getenv() as a fallback
    if (nil == originalPath) originalPath = [[self _systemPaths] componentsJoinedByString:@":"];
    
    bool badEnvironment = false;
    
    // if the user has a teTeX install in PATH prior to TeX Live, kpsewhich is going to be broken
    if ([originalPath rangeOfString:@"tetex" options:NSCaseInsensitiveSearch].length) {
        TLMLog(__func__, @"*** WARNING *** teTeX found in path\n%@", originalPath);
        badEnvironment = true;
    }
    
    // if pointing directly to a texlive install, we need to remove any prior version
    if ([originalPath rangeOfString:@"texlive" options:NSCaseInsensitiveSearch].length) {
        TLMLog(__func__, @"*** WARNING *** TeX Live found in path\n%@", originalPath);
        badEnvironment = true;
    }
    
    // check for environment.plist and see if we need a LART...
    NSDictionary *env = [NSDictionary dictionaryWithContentsOfFile:[@"~/.MacOSX/environment.plist" stringByStandardizingPath]];
    if (env) {
        // look for path, something possibly TeX related, or TEXINPUTS/BIBINPUTS
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"(SELF contains[cd] 'PATH') OR "
                                                                  @"(SELF contains[cd] 'TEX') OR "
                                                                  @"(SELF contains 'INPUTS')"];
        NSArray *keys = [[env allKeys] filteredArrayUsingPredicate:predicate];
        if ([keys count]) {
            NSMutableDictionary *d = [NSMutableDictionary dictionary];
            for (NSString *key in keys)
                [d setObject:[env objectForKey:key] forKey:key];
            TLMLog(__func__, @"*** WARNING *** ~/.MacOSX/environment.plist detected, trouble ahead:\n%@", d);
            badEnvironment = true;
        }
        else {
            // log anyway, since it's a huge PITA to diagnose a screwed up environment
            TLMLog(__func__, @"Found ~/.MacOSX/environment.plist%Clooked okay.", 0x2026);
        }
    }
    
    // if we don't add this to the path, tlmgr falls all over itself when it tries to run kpsewhich etc.
    NSString *texbinPath = [[NSUserDefaults standardUserDefaults] objectForKey:TLMTexBinPathPreferenceKey];
    NSString *newPath = nil;
    
    if (badEnvironment) {
        NSMutableArray *sysPaths = [self _systemPaths];
        
        // try to use a minimal default path from /etc/paths
        if ([sysPaths count]) {
            [sysPaths addObject:texbinPath];
            newPath = [sysPaths componentsJoinedByString:@":"];
            TLMLog(__func__, @"*** WARNING *** Reset path to system default first:\nPATH = %@", newPath);
        }
        // ??? prepending to path is a bad idea in general; maybe better to just die here
        else {
            TLMLog(__func__, @"*** WARNING *** Bad environment.  Prepending \"%@\" to path for tlmgr support.", texbinPath);
            newPath = [texbinPath stringByAppendingFormat:@":%@", originalPath];
        }
    }
    else {
        TLMLog(__func__, @"Appending \"%@\" to path for tlmgr support.", texbinPath);
        newPath = [originalPath stringByAppendingFormat:@":%@", texbinPath];
    }
    
    // set the path globally for convenience, since the app is basically useless without tlmgr
    if (newPath) setenv("PATH", [newPath fileSystemRepresentation], 1);
}

- (void)dealloc
{
    [_mainWindowController release];
    [super dealloc];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    return ([_mainWindowController windowShouldClose:sender]) ? NSTerminateNow : NSTerminateCancel;
}

- (void)awakeFromNib
{
    if (nil == _mainWindowController)
        _mainWindowController = [[TLMMainWindowController alloc] init];
    [_mainWindowController showWindow:nil];
}

- (IBAction)newDocument:(id)sender
{
    [_mainWindowController showWindow:nil];
}

- (IBAction)showPreferences:(id)sender
{
    [[TLMPreferenceController sharedPreferenceController] showWindow:nil];
}

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
