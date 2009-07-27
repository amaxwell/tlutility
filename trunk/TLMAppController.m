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
#import "TLMTask.h"

@implementation TLMAppController

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
            TLMLog(__func__, @"Migrated preferences = %@", oldPrefs);
        
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
    
    // force setup of the log server
    [TLMLogServer sharedServer];
    
    __TLMMigrateBundleIdentifier();
    
    NSString *tlnetDefault = @"http://mirror.ctan.org/systems/texlive/tlnet/2008";
    
    // convert from the old-style composed path to full path, preserving user-specified settings
    NSString *userURL = [[NSUserDefaults standardUserDefaults] objectForKey:@"TLMServerURLPreferenceKey"];
    if (userURL && nil == [[NSUserDefaults standardUserDefaults] objectForKey:TLMFullServerURLPreferenceKey]) {
        
        // path portion of the old default for TL 2008
        NSString *serverPath = @"systems/texlive/tlnet/2008";
        if ([[NSUserDefaults standardUserDefaults] objectForKey:@"TLMServerPathPreferenceKey"])
            serverPath = [[NSUserDefaults standardUserDefaults] objectForKey:@"TLMServerPathPreferenceKey"];
        
        tlnetDefault = [NSString stringWithFormat:@"%@/%@", userURL, serverPath];
        TLMLog(__func__, @"Converting old-style URL preference to %@", tlnetDefault);
        
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
    // typically avoids problems with junk in your home directory
    [defaults setObject:[NSNumber numberWithBool:YES] forKey:TLMUseRootHomePreferenceKey];
    [defaults setObject:@"update-tlmgr-latest.sh" forKey:TLMInfraPathPreferenceKey];
    
    // causes syslog performance problems if enabled by default
    [defaults setObject:[NSNumber numberWithBool:NO] forKey:TLMUseSyslogPreferenceKey];
    
    [defaults setObject:[NSNumber numberWithBool:NO] forKey:TLMDisableVersionMismatchWarningKey];
    
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

- (void)versionWarningDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    if ([[alert suppressionButton] state] == NSOnState)
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:TLMDisableVersionMismatchWarningKey];
}

- (void)checkVersionConsistency
{
    TLMLog(__func__, @"Checking TeX Live version%C", 0x2026);
    // always run the check and log the result
    TLMTask *tlmgrTask = [[TLMTask new] autorelease];
    [tlmgrTask setLaunchPath:[[TLMPreferenceController sharedPreferenceController] tlmgrAbsolutePath]];
    [tlmgrTask setArguments:[NSArray arrayWithObject:@"--version"]];
    [tlmgrTask launch];
    [tlmgrTask waitUntilExit];
    
    NSString *versionString = [tlmgrTask terminationStatus] ? nil : [tlmgrTask outputString];
    
    // !!! this happens periodically, and I don't yet know why...
    if (nil == versionString)
        TLMLog(__func__, @"Failed to read version string: %@", [tlmgrTask errorString]);
    
    versionString = [versionString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    TLMLog(__func__, @"Using tlmgr version:\n%@", versionString);
    NSArray *versionLines = [versionString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSInteger texliveYear = 0;
    
    if ([versionLines count]) {
        
        /*
         froude:~ amaxwell$ tlmgr --version
         tlmgr revision 14230 (2009-07-11 14:56:31 +0200)
         tlmgr using installation: /usr/local/texlive/2009
         TeX Live (http://tug.org/texlive) version 2009-dev
         
         froude:~ amaxwell$ tlmgr --version
         tlmgr revision 12152 (2009-02-12 13:08:37 +0100)
         tlmgr using installation: /usr/local/texlive/2008
         TeX Live (http://tug.org/texlive) version 2008
         texlive-20080903
         */         
        
        for (versionString in versionLines) {
            
            if ([versionString hasPrefix:@"TeX Live"]) {
                NSScanner *scanner = [NSScanner scannerWithString:versionString];
                [scanner setCharactersToBeSkipped:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]];
                [scanner scanInteger:&texliveYear];
                break;
            }
        }
    }
    
    if (texliveYear ) {
        
        TLMLog(__func__, @"Looks like you're using TeX Live %d%Cgood!", texliveYear, 0x2026);
        
        NSString *URLString = [[[TLMPreferenceController sharedPreferenceController] defaultServerURL] absoluteString];
        
        /*
         Currently we only have to actual cases to be concerned with, so there's no point in overgeneralizing here.
         TL 2008 appended the year to the URL, but 2009 (and presumably following) releases do not.  Unfortunately,
         tlmgr handles the multiplexer URLs specially, and if someone uses a 2009 pretest tlmgr with a 2008 URL,
         tlmgr converts it to a 2009 URL and you get a 404 page instead of an error about a version mismatch.  This
         may or may not be an issue with later releases, so it's something of a special case for now.
         */
        
        NSAlert *alert = nil;
        
        if (2008 == texliveYear && [URLString hasSuffix:@"2008"] == NO) {
            
            alert = [[NSAlert new] autorelease];
            [alert setMessageText:NSLocalizedString(@"Mirror URL may not match TeX Live version", @"")];
            [alert setInformativeText:NSLocalizedString(@"Mirror URLs for TeX Live 2008 generally have \"2008\" appended to them.  If any operations fail, you may need to adjust your mirror URL in the preferences.", @"")];
            
        }
        else if (texliveYear > 2008 && [URLString hasSuffix:@"2008"]) {
            
            alert = [[NSAlert new] autorelease];
            [alert setMessageText:NSLocalizedString(@"Mirror URL may not match TeX Live version", @"")];
            [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Your TeX Live version is %d, but your mirror URL appears to be for TeX Live 2008.  If any operations fail, you may need to adjust your mirror URL in the preferences.", @"two integer specifiers"), (int)texliveYear]];
        }
        else {
            TLMLog(__func__, @"Mirror URL looks okay for TeX Live %d", texliveYear);
        }
        
        // always log a message in case the user turned off the warning, so there is no plausible deniability when things fail...
        if (alert)
            TLMLog(__func__, @"*** WARNING *** Potential version mismatch between tlmgr and mirror URL %@", URLString);
        
        if (alert && [[NSUserDefaults standardUserDefaults] boolForKey:TLMDisableVersionMismatchWarningKey] == NO) {
            [alert setShowsSuppressionButton:YES];
            
            // always show on the main window
            [alert beginSheetModalForWindow:[_mainWindowController window] 
                              modalDelegate:self 
                             didEndSelector:@selector(versionWarningDidEnd:returnCode:contextInfo:) 
                                contextInfo:NULL];            
        }
    }
    else if (versionString) {
        TLMLog(__func__, @"Unable to determine TeX Live year from tlmgr --version: %@", versionString);
    }
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
