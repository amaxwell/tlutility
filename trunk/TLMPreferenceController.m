//
//  TLMPreferenceController.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/08/08.
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

#import "TLMPreferenceController.h"
#import "TLMURLFormatter.h"
#import "TLMAppController.h"
#import "TLMLogServer.h"
#import "TLMTask.h"
#import "TLMDownload.h"

NSString * const TLMTexBinPathPreferenceKey = @"TLMTexBinPathPreferenceKey";       /* /usr/texbin                 */
NSString * const TLMUseRootHomePreferenceKey = @"TLMUseRootHomePreferenceKey";     /* YES                         */
NSString * const TLMInfraPathPreferenceKey = @"TLMInfraPathPreferenceKey";         /* update-tlmgr-latest.sh      */
NSString * const TLMUseSyslogPreferenceKey = @"TLMUseSyslogPreferenceKey";         /* NO                          */
NSString * const TLMFullServerURLPreferenceKey = @"TLMFullServerURLPreferenceKey"; /* composed URL                */
NSString * const TLMDisableVersionMismatchWarningKey = @"TLMDisableVersionMismatchWarningKey"; /* NO              */
NSString * const TLMAutoInstallPreferenceKey = @"TLMAutoInstallPreferenceKey";     /* YES (2009 only)             */
NSString * const TLMAutoRemovePreferenceKey = @"TLMAutoRemovePreferenceKey";       /* YES (2009 only)             */
NSString * const TLMSetCommandLineServerPreferenceKey = @"TLMSetCommandLineServerPreferenceKey"; /* NO            */

#define TLMGR_CMD @"tlmgr"
#define TEXDOC_CMD @"texdoc"
#define KPSEWHICH_CMD @"kpsewhich"
#define URL_TIMEOUT 30.0

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

+ (TLMPreferenceController *)sharedPreferenceController;
{
    static id sharedInstance = nil;
    if (nil == sharedInstance)
        sharedInstance = [self new];
    return sharedInstance;
}

- (id)init
{
    return [self initWithWindowNibName:[self windowNibName]];
}

- (id)initWithWindowNibName:(NSString *)name
{
    self = [super initWithWindowNibName:name];
    if (self) {
        // current server from prefs seems to be added automatically when setting stringValue
        NSString *plistPath = [[NSBundle mainBundle] pathForResource:@"DefaultMirrors" ofType:@"plist"];
        NSDictionary *mirrorsByYear = nil;
        if (plistPath)
            mirrorsByYear = [NSDictionary dictionaryWithContentsOfFile:plistPath];
        _servers = [[mirrorsByYear objectForKey:@"tlnet"] copy];
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

- (void)awakeFromNib
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *texbinPath = [defaults objectForKey:TLMTexBinPathPreferenceKey];
    [_texbinPathControl setURL:[NSURL fileURLWithPath:texbinPath]];    
    // only display the hostname part
    [_serverComboBox setStringValue:[defaults objectForKey:TLMFullServerURLPreferenceKey]];
    [_serverComboBox setFormatter:[[TLMURLFormatter new] autorelease]];
    [_serverComboBox setDelegate:self];
    [_serverComboBox setDataSource:self];
    [self updateUI];
}

- (IBAction)toggleUseRootHome:(id)sender;
{
    [[NSUserDefaults standardUserDefaults] setBool:([sender state] == NSOnState) forKey:TLMUseRootHomePreferenceKey];
}

- (void)_syncCommandLineServerOption
{
    // tlmgr --machine-readable option location
    // tlmgr option location http://foo.bar.com/tlnet
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:TLMSetCommandLineServerPreferenceKey]) {
        
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
    [TLMAppController updatePathEnvironment];
    
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:TLMDisableVersionMismatchWarningKey];
    [[NSApp delegate] checkVersionConsistency];
    [self updateUI];
}

- (void)openPanelDidEnd:(NSOpenPanel*)panel returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    [panel orderOut:self];
    
    if (NSOKButton == returnCode) {
        [self updateTeXBinPathWithURL:[panel URL]];
    }
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
    [openPanel beginSheetForDirectory:@"/usr" file:nil 
                       modalForWindow:[self window] modalDelegate:self 
                       didEndSelector:@selector(openPanelDidEnd:returnCode:contextInfo:) contextInfo:NULL];
}

- (BOOL)_canConnectToDefaultFTPServer
{
    CFReadStreamRef stream = CFReadStreamCreateWithFTPURL(NULL, (CFURLRef)[self defaultServerURL]);
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
            TLMLog(__func__, @"Unable to connect to %@ after %.0f seconds", [[self defaultServerURL] absoluteString], URL_TIMEOUT);
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
            TLMLog(__func__, @"Unable to read data from %@ after %.0f seconds", [[self defaultServerURL] absoluteString], URL_TIMEOUT);
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
    
    TLMLog(__func__, @"%@ has %lu files", [[self defaultServerURL] absoluteString], (long)[files count]);
    return ([files count] > 0);
}

- (NSString *)_downloadRunLoopMode
{
    return [NSString stringWithFormat:@"TLMPreferenceControllerRunLoopMode <%p>", self];
}

- (BOOL)_canConnectToDefaultServer
{
    // this is really a case of formatter failure...
    if (nil == [self defaultServerURL])
        return NO;
    
    NSString *URLString = [[self defaultServerURL] absoluteString];
    
    TLMLog(__func__, @"Checking for a connection to %@%C", URLString, 0x2026);
    
    // CFNetDiagnostic crashes with nil URL
    NSParameterAssert([self defaultServerURL]);
    
    // see if we have a network connection
    CFNetDiagnosticRef diagnostic = CFNetDiagnosticCreateWithURL(NULL, (CFURLRef)[self defaultServerURL]);
    [(id)diagnostic autorelease];
    if (kCFNetDiagnosticConnectionDown == CFNetDiagnosticCopyNetworkStatusPassively(diagnostic, NULL)) {
        TLMLog(__func__, @"net diagnostic reports the connection is down");
        return NO;
    }
    
    // An ftp server doesn't return data for a directory listing via NSURLConnection, so use CFFTP
    if ([[[self defaultServerURL] scheme] isEqualToString:@"ftp"])
        return [self _canConnectToDefaultFTPServer];
    
    NSURLRequest *request = [NSURLRequest requestWithURL:[self defaultServerURL] 
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
        [self _syncCommandLineServerOption];
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:TLMDisableVersionMismatchWarningKey];
        [[NSApp delegate] checkVersionConsistency];    
    }
}

- (NSString *)windowNibName { return @"Preferences"; }

- (NSURL *)defaultServerURL
{
    return [NSURL URLWithString:[[NSUserDefaults standardUserDefaults] objectForKey:TLMFullServerURLPreferenceKey]];
}

- (NSString *)tlmgrAbsolutePath
{
    NSString *texbinPath = [[NSUserDefaults standardUserDefaults] objectForKey:TLMTexBinPathPreferenceKey];
    return [[texbinPath stringByAppendingPathComponent:TLMGR_CMD] stringByStandardizingPath];
}

- (NSString *)texdocAbsolutePath
{
    NSString *texbinPath = [[NSUserDefaults standardUserDefaults] objectForKey:TLMTexBinPathPreferenceKey];
    return [[texbinPath stringByAppendingPathComponent:TEXDOC_CMD] stringByStandardizingPath];
}

- (NSString *)kpsewhichAbsolutePath
{
    NSString *texbinPath = [[NSUserDefaults standardUserDefaults] objectForKey:TLMTexBinPathPreferenceKey];
    return [[texbinPath stringByAppendingPathComponent:KPSEWHICH_CMD] stringByStandardizingPath];
}

- (NSURL *)installDirectory
{    
    // kpsewhich -var-value=SELFAUTOPARENT
    NSString *kpsewhichPath = [self kpsewhichAbsolutePath];
    NSURL *serverURL = nil;
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:kpsewhichPath]) {
        TLMTask *task = [TLMTask new];
        [task setLaunchPath:kpsewhichPath];
        [task setArguments:[NSArray arrayWithObject:@"-var-value=SELFAUTOPARENT"]];
        [task launch];
        [task waitUntilExit];
        if ([task terminationStatus] == 0 && [task outputString]) {
            NSString *str = [[task outputString] stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
            serverURL = [NSURL fileURLWithPath:str isDirectory:YES];
        }
        else {
            TLMLog(__func__, @"kpsewhich returned an error: %@", [task errorString]);
        }
        [task release];
    }
    else {
        TLMLog(__func__, @"no kpsewhich executable at %@", kpsewhichPath);
    }
    return serverURL;
}

- (BOOL)installRequiresRootPrivileges
{
    NSString *path = [[self installDirectory] path];
    
    // will fail regardless...
    if (nil == path)
        return NO;
    
    if ([NSThread isMainThread])
        return [[NSFileManager defaultManager] isWritableFileAtPath:path];
    
    NSFileManager *fm = [NSFileManager new];
    BOOL ret = [fm isWritableFileAtPath:path];
    [fm release];
    return ret;
}

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

- (BOOL)autoInstall { return [[NSUserDefaults standardUserDefaults] boolForKey:TLMAutoInstallPreferenceKey]; }

- (BOOL)autoRemove { return [[NSUserDefaults standardUserDefaults] boolForKey:TLMAutoRemovePreferenceKey]; }

@end
