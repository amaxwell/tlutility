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
#import "TLMReleaseNotesController.h"

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
    // one path per line, according to man page for path_helper(8)
    for (NSString *path in [str componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        
        // trim and check for empty string, in case of empty/trailing line
        path = [path stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([path isEqualToString:@""] == NO)
            [paths addObject:path];
    }
    return paths;
}

+ (void)updatePathEnvironment;
{
    /*
     
     I originally tried using the path to tlmgr itself as the sole setting, but it needs kpsewhich etc., 
     so we have to pass tlmgr a correct, usable environment.
     
     Next rev was to append the path from prefs (typically /usr/texbin) to the existing PATH variable.  
     Unfortunately, there are at least a couple of problems with this:
     
        1) If the user has a teTeX install in PATH prior to TeX Live, kpsewhich breaks horribly.
        2) If the pref previously pointed directly to a TeX Live install, that version of TL should
           be removed from the path, and there's no good way to do that.
     
     The main breakage came from our ancient enemy environment.plist, of course.  The best solution 
     appears to be to set a clean path from /etc/paths, then append /usr/texbin.  This should work 
     even if the user did something stupid like set PATH in environment.plist, and is more secure than
     prepending /usr/texbin to the PATH.
     
     Even though PATH is now reset, we still check for environment.plist and use a log as a LART,
     since it can still break TeX in strange ways.  No point in wasting more time on this.

     NB: I set the path globally for convenience, since the app is basically useless without tlmgr.  This
     avoids the hassle of passing the environment to each child process.

     */
    
    NSDictionary *env = [NSDictionary dictionaryWithContentsOfFile:[@"~/.MacOSX/environment.plist" stringByStandardizingPath]];
    if (env) {
        
        // look for path, or something possibly TeX related like TEXINPUTS/BIBINPUTS
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"(SELF contains[cd] 'PATH') OR "
                                                                  @"(SELF contains[cd] 'TEX') OR "
                                                                  @"(SELF contains 'INPUTS')"];
        NSArray *keys = [[env allKeys] filteredArrayUsingPredicate:predicate];
        if ([keys count]) {
            TLMLog(__func__, @"*** WARNING *** ~/.MacOSX/environment.plist alters critical variables; ignoring PATH if present in %@", keys);
        }
        else {
            // log anyway, since it's a huge PITA to diagnose a screwed up environment
            TLMLog(__func__, @"Found ~/.MacOSX/environment.plist%Cdidn't look too evil.", 0x2026);
        }
    }
    
    // get the base path from /etc
    NSMutableArray *systemPaths = [self _systemPaths];
    
    // could abort here, but try the default on 10.5+
    if (nil == systemPaths) {
        systemPaths = [NSMutableArray arrayWithObjects:@"/usr/bin", @"/bin", @"/usr/sbin", @"/sbin", @"/usr/local/bin", nil];
        TLMLog(__func__, @"*** ERROR *** Unable to read /etc/paths.");
    }
    
    NSParameterAssert([[NSUserDefaults standardUserDefaults] objectForKey:TLMTexBinPathPreferenceKey]);
    [systemPaths addObject:[[NSUserDefaults standardUserDefaults] objectForKey:TLMTexBinPathPreferenceKey]];
    NSString *newPath = [systemPaths componentsJoinedByString:@":"];
    NSParameterAssert(newPath);
    
    setenv("PATH", [newPath fileSystemRepresentation], 1);
    TLMLog(__func__, @"Using PATH = \"%@\"", systemPaths);
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

- (IBAction)openReleaseNotes:(id)sender;
{
    [[TLMReleaseNotesController sharedInstance] showWindow:nil];
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
