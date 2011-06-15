//
//  TLMPreferenceController.m
//  TeX Live Manager
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

#define URL_TIMEOUT   30.0

@implementation TLMPreferenceController

@synthesize _texbinPathControl;
@synthesize _serverComboBox;
@synthesize _setCommandLineServerCheckbox;
@synthesize _rootHomeCheckBox;
@synthesize _useSyslogCheckBox;
@synthesize _progressPanel;
@synthesize _progressIndicator;
@synthesize _progressField;
@synthesize _autoremoveCheckBox;
@synthesize _autoinstallCheckBox;
@synthesize defaultServers = _servers;

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

- (id)initWithWindowNibName:(NSString *)name
{
    NSParameterAssert([NSThread isMainThread]);
    self = [super initWithWindowNibName:name];
    if (self) {
        // current server from prefs seems to be added automatically when setting stringValue
        NSString *plistPath = [[NSBundle mainBundle] pathForResource:@"DefaultMirrors" ofType:@"plist"];
        NSDictionary *mirrorsByYear = nil;
        if (plistPath)
            mirrorsByYear = [NSDictionary dictionaryWithContentsOfFile:plistPath];
        NSMutableArray *servers = [NSMutableArray arrayWithArray:[mirrorsByYear objectForKey:@"tlnet"]];
        
        // insert TL critical repo if this hidden pref is set
        if ([[NSUserDefaults standardUserDefaults] boolForKey:TLMShouldListTLCritical])
            [servers insertObject:[[NSUserDefaults standardUserDefaults] objectForKey:TLMTLCriticalRepository] atIndex:0];
        
        _servers = [servers copy];

    }
    return self;
}

- (void)dealloc
{
    [_texbinPathControl release];
    [_serverComboBox release];
    [_rootHomeCheckBox release];
    [_useSyslogCheckBox release];
    [_servers release];
    [_progressPanel release];
    [_progressIndicator release];
    [_progressField release];
    [_autoremoveCheckBox release];
    [_autoinstallCheckBox release];
    [_setCommandLineServerCheckbox release];
    [super dealloc];
}

static NSURL * __TLMParseLocationOption(NSString *location)
{
    if (location) {
        location = [location stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        location = [[location componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lastObject];
        // remove trailing slashes before comparison, although this is a directory
        while ([location hasSuffix:@"/"])
            location = [location substringToIndex:([location length] - 1)];        
    }
    return location ? [NSURL URLWithString:location] : nil;
}

- (void)updateUI
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [_rootHomeCheckBox setState:[defaults boolForKey:TLMUseRootHomePreferenceKey]];
    [_useSyslogCheckBox setState:[defaults boolForKey:TLMUseSyslogPreferenceKey]];
    [_autoinstallCheckBox setState:[defaults boolForKey:TLMAutoInstallPreferenceKey]];
    [_autoremoveCheckBox setState:[defaults boolForKey:TLMAutoRemovePreferenceKey]];   
    [_setCommandLineServerCheckbox setState:[defaults boolForKey:TLMSetCommandLineServerPreferenceKey]];
}

- (void)windowDidBecomeMain:(NSNotification *)notification
{
    // account for possible TeXDist prefpane changes (this was for TL 2008 vs. 2009 differences)
    [self updateUI];
}

- (void)_handleLocationTaskTerminated:(NSNotification *)aNote
{
    TLMTask *checkTask = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSTaskDidTerminateNotification
                                                  object:checkTask];
    NSURL *serverURL = [[TLMEnvironment currentEnvironment] defaultServerURL];
    NSURL *tlmgrURL = nil;
    if ([checkTask terminationStatus] == 0)
        tlmgrURL = __TLMParseLocationOption([checkTask outputString]);
    if ([tlmgrURL isEqual:serverURL] == NO && [[NSUserDefaults standardUserDefaults] boolForKey:TLMSetCommandLineServerPreferenceKey]) {
        TLMLog(__func__, @"Default server URL mismatch with tlmgr; unsetting preference key.\n\tDefault: %@\n\ttlmgr: %@", serverURL, tlmgrURL);
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:TLMSetCommandLineServerPreferenceKey];
        [self updateUI];
    }
    else if ([[NSUserDefaults standardUserDefaults] boolForKey:TLMSetCommandLineServerPreferenceKey]) {
        TLMLog(__func__, @"Default server URL same as tlmgr default:\n\t %@", [serverURL absoluteString]);
    }
}

- (void)awakeFromNib
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *texbinPath = [defaults objectForKey:TLMTexBinPathPreferenceKey];
    [_texbinPathControl setURL:[NSURL fileURLWithPath:texbinPath]];    
    // only display the hostname part
    [_serverComboBox setStringValue:[defaults objectForKey:TLMFullServerURLPreferenceKey]];
    [_serverComboBox setFormatter:[[TLMURLFormatter new] autorelease]];
    [_serverComboBox setDataSource:self];
        
    // this needs to be asynchronous, since it really slows down the panel opening
    NSArray *args = [NSArray arrayWithObjects:@"--machine-readable", @"option", @"location", nil];
    TLMTask *checkTask = [[TLMTask new] autorelease];
    [checkTask setLaunchPath:[[TLMEnvironment currentEnvironment] tlmgrAbsolutePath]];
    [checkTask setArguments:args];
    [checkTask setCurrentDirectoryPath:NSTemporaryDirectory()];
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(_handleLocationTaskTerminated:) 
                                                 name:NSTaskDidTerminateNotification 
                                               object:checkTask];
    [checkTask launch];
    [self updateUI];    
}

- (IBAction)toggleUseRootHome:(id)sender;
{
    [[NSUserDefaults standardUserDefaults] setBool:([sender state] == NSOnState) forKey:TLMUseRootHomePreferenceKey];
}

- (NSURL *)_currentTeXLiveLocationOption
{
    NSArray *args = [NSArray arrayWithObjects:@"--machine-readable", @"option", @"location", nil];
    TLMTask *checkTask = [TLMTask launchedTaskWithLaunchPath:[[TLMEnvironment currentEnvironment] tlmgrAbsolutePath] arguments:args];
    [checkTask waitUntilExit];
    return ([checkTask terminationStatus] == 0) ? __TLMParseLocationOption([checkTask outputString]) : nil;
}

- (void)_handleLocationOperationFinished:(NSNotification *)aNote
{
    TLMOptionOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    NSParameterAssert(_pendingOptionChangeCount);
    _pendingOptionChangeCount -= 1;
    
    NSString *location = [[self _currentTeXLiveLocationOption] absoluteString];
    if (nil == location)
        location = NSLocalizedString(@"Error reading location from TeX Live", @"");
    
    if ([op failed] || [op isCancelled]) {
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"The location in the TeX Live database was not changed", @"")];
        [alert setInformativeText:[NSString stringWithFormat:@"%@ %@", NSLocalizedString(@"The current location is:", @""), location]];
        [alert beginSheetModalForWindow:[self window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
        // now out of sync, so disable this pref and uncheck the box so that's obvious
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:TLMSetCommandLineServerPreferenceKey];
        [self updateUI];
    }
    else {
        TLMLog(__func__, @"Finished setting command line server location:\n\tlocation = %@", location);
    }
}   

- (void)_syncCommandLineServerOption
{
    // !!! early return since there's nothing to do here...
    if ([[NSUserDefaults standardUserDefaults] boolForKey:TLMSetCommandLineServerPreferenceKey] == NO)
        return;
    
    NSURL *location = [self _currentTeXLiveLocationOption];
    NSURL *defaultServerURL = [[TLMEnvironment currentEnvironment] defaultServerURL];

    // this is kind of slow, so avoid doing it unless we really have to
    if ([location isEqual:defaultServerURL] == NO) {
        TLMLog(__func__, @"Setting command line server location to %@", [defaultServerURL absoluteString]);
        TLMOptionOperation *op = [[TLMOptionOperation alloc] initWithKey:@"location" value:[defaultServerURL absoluteString]];
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(_handleLocationOperationFinished:) 
                                                     name:TLMOperationFinishedNotification 
                                                   object:op];
        // make sure we can't close the window until this is finished
        _pendingOptionChangeCount += 1;
        [[TLMReadWriteOperationQueue defaultQueue] addOperation:op];
        [op release];
    }
}

- (IBAction)toggleCommandLineServer:(id)sender;
{
    [[NSUserDefaults standardUserDefaults] setBool:([sender state] == NSOnState) forKey:TLMSetCommandLineServerPreferenceKey];
    [self _syncCommandLineServerOption];
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

- (BOOL)_canConnectToDefaultFTPServer
{
    NSURL *defaultServerURL = [[TLMEnvironment currentEnvironment] defaultServerURL];
    
    CFReadStreamRef stream = CFReadStreamCreateWithFTPURL(NULL, (CFURLRef)defaultServerURL);
    if (NULL == stream)
        return NO;
    
    if (CFReadStreamOpen(stream) == FALSE) {
        CFRelease(stream);
        return NO;
    }
    
    CFStreamStatus status;
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    bool keepWaiting;
    do {
        
        status = CFReadStreamGetStatus(stream);
        
        if (kCFStreamStatusOpen != status && kCFStreamStatusError != status) {
            keepWaiting = false;
        }
        // absolute timeout check; set error to bail out after this loop
        else if (CFAbsoluteTimeGetCurrent() > start + URL_TIMEOUT) {
            TLMLog(__func__, @"Unable to connect to %@ after %.0f seconds", [defaultServerURL absoluteString], URL_TIMEOUT);
            status = kCFStreamStatusError;
            keepWaiting = false;
        }
        else {
            // block in default runloop mode (typically never hits this path)
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, TRUE);
            keepWaiting = true;
        }
        
    } while (keepWaiting);
    
    // if unable to read anything, close the stream and return NO
    if (kCFStreamStatusError == status) {
        CFReadStreamClose(stream);
        CFRelease(stream);
        return NO;
    }
    
    // read all data from the directory listing into a mutable data
    NSMutableData *data = [NSMutableData data];
    keepWaiting = true;
    start = CFAbsoluteTimeGetCurrent();
    do {
        
        if (CFReadStreamHasBytesAvailable(stream)) {
            CFIndex len;
            uint8_t buffer[4096];
            while ((len = CFReadStreamRead(stream, buffer, sizeof(buffer))) > 0) {
                [data appendBytes:buffer length:len];
            }
            if (len <= 0) keepWaiting = false;
        }
        // absolute timeout check
        else if (CFAbsoluteTimeGetCurrent() > start + URL_TIMEOUT) {
            TLMLog(__func__, @"Unable to read data from %@ after %.0f seconds", [defaultServerURL absoluteString], URL_TIMEOUT);
            keepWaiting = false;
        }
        else {
            // block in default runloop mode to avoid a beachball, since we have a progress indicator
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, TRUE);
        }
        
    } while (keepWaiting);
    
    
    CFReadStreamClose(stream);
    CFRelease(stream);
    stream = NULL;
    
    // now parse the stream and see if we have something that makes sense...
    NSMutableArray *files = [NSMutableArray array];
    ssize_t offset = 0, remainingLength = [data length];
    const uint8_t *listingPtr = [data bytes];
    do {
        
        // each call parses one line
        CFDictionaryRef listing;
        CFIndex len = CFFTPCreateParsedResourceListing(NULL, listingPtr + offset, remainingLength, &listing);
        if (len > 0) {
            NSString *name = (id)CFDictionaryGetValue(listing, kCFFTPResourceName);
            if (name) [files addObject:name];
            CFRelease(listing);
        }
        offset += len;
        remainingLength -= len;
        
    } while (remainingLength > 0);
    
    TLMLog(__func__, @"%@ has %lu files", [defaultServerURL absoluteString], (long)[files count]);
    return ([files count] > 0);
}

- (NSString *)_downloadRunLoopMode
{
    return [NSString stringWithFormat:@"TLMPreferenceControllerRunLoopMode <%p>", self];
}

- (BOOL)_canConnectToDefaultServer
{
    NSURL *defaultServerURL = [[TLMEnvironment currentEnvironment] defaultServerURL];
    
    // this is really a case of formatter failure...
    if (nil == defaultServerURL)
        return NO;
    
    NSString *URLString = [defaultServerURL absoluteString];
    
    TLMLog(__func__, @"Checking for a connection to %@%C", URLString, 0x2026);
    TLMLogServerSync();
    
    // CFNetDiagnostic crashes with nil URL
    NSParameterAssert(defaultServerURL);
    
    // see if we have a network connection
    CFNetDiagnosticRef diagnostic = CFNetDiagnosticCreateWithURL(NULL, (CFURLRef)defaultServerURL);
    [(id)diagnostic autorelease];
    if (kCFNetDiagnosticConnectionDown == CFNetDiagnosticCopyNetworkStatusPassively(diagnostic, NULL)) {
        TLMLog(__func__, @"net diagnostic reports the connection is down");
        return NO;
    }
    
    // An ftp server doesn't return data for a directory listing via NSURLConnection, so use CFFTP
    if ([[defaultServerURL scheme] isEqualToString:@"ftp"])
        return [self _canConnectToDefaultFTPServer];
    
    NSURLRequest *request = [NSURLRequest requestWithURL:defaultServerURL 
                                             cachePolicy:NSURLRequestReloadIgnoringCacheData 
                                         timeoutInterval:URL_TIMEOUT];
    
    // NSURLConnection synchronous download blocks the panel timer, so the countdown gets stuck
    TLMDownload *download = [[TLMDownload new] autorelease];
    [download downloadRequest:request inMode:[self _downloadRunLoopMode]];
    
    while ([download isFinished] == NO) {
        NSDate *next = [[NSDate alloc] initWithTimeIntervalSinceNow:0.5];
        [[NSRunLoop currentRunLoop] runMode:[self _downloadRunLoopMode] beforeDate:next];
        [next release];
    }
    
    NSError *error;
    const BOOL failed = [download failed:&error];
    
    if (failed)
        TLMLog(__func__, @"error from loading %@: %@", URLString, error);
    
    return (failed == NO);
}

- (void)_updateProgressField:(NSTimer *)timer
{
    NSNumber *start = [timer userInfo];
    CFTimeInterval delta = CFAbsoluteTimeGetCurrent() - [start doubleValue];
    delta = MAX(URL_TIMEOUT - delta, 0);
    [_progressField setStringValue:[NSString stringWithFormat:NSLocalizedString(@"%.0f seconds remaining.", @"keep short"), delta]];
    [_progressPanel display];
}

- (IBAction)changeServerURL:(id)sender
{        
    // save the old value, then set new value in prefs, so -defaultServerURL can be used in _canConnectToDefaultServer
    NSString *oldValue = [[[[NSUserDefaults standardUserDefaults] objectForKey:TLMFullServerURLPreferenceKey] copy] autorelease];
    NSString *serverURLString = [[sender cell] stringValue];
    [[NSUserDefaults standardUserDefaults] setObject:serverURLString forKey:TLMFullServerURLPreferenceKey];
    
    if ([[NSURL URLWithString:serverURLString] isEqual:[NSURL URLWithString:[[NSUserDefaults standardUserDefaults] objectForKey:TLMTLCriticalRepository]]])
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:TLMShouldListTLCritical];
    
    // only display the dialog if the user has manually typed something in the text field
    if (_hasPendingServerEdit) {
        
        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.5 
                                                          target:self 
                                                        selector:@selector(_updateProgressField:) 
                                                        userInfo:[NSNumber numberWithDouble:CFAbsoluteTimeGetCurrent()] 
                                                         repeats:YES];
        [[NSRunLoop currentRunLoop] addTimer:timer forMode:[self _downloadRunLoopMode]];
        // fire manually to get the initial status message
        [timer fire];
        [NSApp beginSheet:_progressPanel modalForWindow:[self window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
        [_progressIndicator startAnimation:nil];
        
        /*
         It's not immediately obvious how to compose the URL, since each mirror has a different path.
         Do a quick check if this isn't one of the URLs from the bundled plist.
         */
        if ([self _canConnectToDefaultServer] == NO) {
            
            [NSApp endSheet:_progressPanel];
            [_progressPanel orderOut:nil];
            [timer invalidate];
            
            NSAlert *alert = [[NSAlert new] autorelease];
            [alert setMessageText:NSLocalizedString(@"Unable to connect to server.", @"alert title")];
            [alert setInformativeText:NSLocalizedString(@"Either a network connection could not be established, or the specified URL is incorrect.  Would you like to keep this URL, or revert to the previous one?", @"alert message text")];
            [alert addButtonWithTitle:NSLocalizedString(@"Revert", @"")];
            [alert addButtonWithTitle:NSLocalizedString(@"Keep", @"")];
            
            // don't run as a sheet, since this may need to block a window close
            NSInteger rv = [alert runModal];
            
            if (NSAlertFirstButtonReturn == rv) {
                [[NSUserDefaults standardUserDefaults] setObject:oldValue forKey:TLMFullServerURLPreferenceKey];
                [[sender cell] setStringValue:oldValue];
            }
        }
        else {
            [NSApp endSheet:_progressPanel];
            [_progressPanel orderOut:nil];
            [timer invalidate];
        }
        
        // reset since it's either accepted or reverted at this point
        _hasPendingServerEdit = NO;
    }
        
    // reset the pref if things have changed
    if ([oldValue isEqualToString:[[NSUserDefaults standardUserDefaults] objectForKey:TLMFullServerURLPreferenceKey]] == NO) {
        
        // always reset these, so we have a known state
        [TLMEnvironment updateEnvironment];
        
        [self _syncCommandLineServerOption];
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:TLMDisableVersionMismatchWarningKey];
        
        /*
         Allow changes to the combo box list to persist in the session, but not across launches 
         since dealing with incompatible repos is not practical.
         */
        if ([_servers containsObject:serverURLString] == NO) {
            NSMutableArray *servers = [_servers mutableCopy];
            [servers insertObject:serverURLString atIndex:0];
            [_servers release];
            _servers = [servers copy];
            [servers release];
            [_serverComboBox reloadData];
        }
    }
}

- (NSString *)windowNibName { return @"Preferences"; }

#pragma mark Server combo box datasource

- (NSInteger)numberOfItemsInComboBox:(NSComboBox *)aComboBox;
{
    return [_servers count];
}

- (id)comboBox:(NSComboBox *)aComboBox objectValueForItemAtIndex:(NSInteger)idx;
{
    return [_servers objectAtIndex:idx];
}

- (NSUInteger)comboBox:(NSComboBox *)aComboBox indexOfItemWithStringValue:(NSString *)string;
{
    NSUInteger i = 0;
    for (NSString *value in _servers) {
        if ([string isEqualToString:value])
            return i;
        i++;
    }
    return NSNotFound;
}

# pragma mark Input validation

- (BOOL)control:(NSControl *)control didFailToFormatString:(NSString *)string errorDescription:(NSString *)error
{
    NSAlert *alert = [NSAlert alertWithMessageText:error 
                                     defaultButton:NSLocalizedString(@"Edit", @"button title") 
                                   alternateButton:NSLocalizedString(@"Ignore", @"button title") 
                                       otherButton:nil 
                         informativeTextWithFormat:NSLocalizedString(@"Choose \"Edit\" to fix the value, or \"Ignore\" to use the invalid URL.", @"alert message text, Edit and Ignore are button titles")];
    NSInteger rv = [alert runModal];
    
    // return YES to accept as-is, NO to edit again
    return NSAlertDefaultReturn != rv;
}

- (BOOL)control:(NSControl *)control textShouldBeginEditing:(NSText *)fieldEditor
{
    _hasPendingServerEdit = YES;
    return YES;
}

// make sure to end editing on close (should only block if _hasPendingServerEdit is true)
- (BOOL)windowShouldClose:(id)sender;
{
    return [[self window] makeFirstResponder:nil] && 0 == _pendingOptionChangeCount;
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
