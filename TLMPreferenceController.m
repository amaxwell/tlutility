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
#import "TLMAppController.h"
#import "TLMLogServer.h"
#import "TLMTask.h"
#import "TLMDownload.h"
#import "TLMReadWriteOperationQueue.h"
#import "TLMOptionOperation.h"
#import "TLMDatabase.h"

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

#define TLMGR_CMD     @"tlmgr"
#define TEXDOC_CMD    @"texdoc"
#define KPSEWHICH_CMD @"kpsewhich"
#define URL_TIMEOUT   30.0
#define TEXDIST_PATH  @"/Library/TeX"

@interface TLMPreferenceController ()

@property (readwrite, copy) NSURL *legacyRepositoryURL;

@end


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
@synthesize legacyRepositoryURL = _legacyRepositoryURL;

// Do not use directly!  File scope only because pthread_once doesn't take an argument.
static id _sharedInstance = nil;
static void __TLMPrefControllerInit() { _sharedInstance = [TLMPreferenceController new]; }

+ (TLMPreferenceController *)sharedPreferenceController;
{
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    (void) pthread_once(&once, __TLMPrefControllerInit);
    return _sharedInstance;
}

- (void)_resetVersions
{
    @synchronized(self) {
        TLMLog(__func__, @"Resetting cached version info");
        _versions.repositoryYear = TLMDatabaseUnknownYear;
        _versions.installedYear = TLMDatabaseUnknownYear;
        _versions.tlmgrVersion = -1;
        _versions.isDevelopment = NO;
        [self setLegacyRepositoryURL:nil];
    }    
}

static void __TLMTeXDistChanged(ConstFSEventStreamRef strm, void *context, size_t numEvents, void *eventPaths, const FSEventStreamEventFlags eventFlags[], const FSEventStreamEventId eventIds[])
{
    for (NSUInteger i = 0; i < numEvents; i++) {
        if (eventFlags[i] == kFSEventStreamEventFlagNone) {
            TLMLog(__func__, @"TeX distribution path changed");
            [(TLMPreferenceController *)context _resetVersions];
            break;
        }
    }
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
        NSMutableArray *servers = [NSMutableArray arrayWithArray:[mirrorsByYear objectForKey:@"tlnet"]];
        
        // insert TL critical repo if this hidden pref is set
        if ([[NSUserDefaults standardUserDefaults] boolForKey:TLMShouldListTLCritical])
            [servers insertObject:[[NSUserDefaults standardUserDefaults] objectForKey:TLMTLCriticalRepository] atIndex:0];
        
        _servers = [servers copy];
        
        _versions.repositoryYear = TLMDatabaseUnknownYear;
        _versions.installedYear = TLMDatabaseUnknownYear;
        _versions.tlmgrVersion = -1;
        _versions.isDevelopment = NO;
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:TEXDIST_PATH]) {
            FSEventStreamContext ctxt = { 0, self, CFRetain, CFRelease, CFCopyDescription };
            CFArrayRef paths = (CFArrayRef)[NSArray arrayWithObject:TEXDIST_PATH];
            FSEventStreamCreateFlags flags = kFSEventStreamCreateFlagUseCFTypes|kFSEventStreamCreateFlagNoDefer;
            _fseventStream = FSEventStreamCreate(NULL, __TLMTeXDistChanged, &ctxt, paths, kFSEventStreamEventIdSinceNow, 0.1, flags);
            if (_fseventStream) {
                FSEventStreamScheduleWithRunLoop(_fseventStream, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
                FSEventStreamStart(_fseventStream);
            }
        }
        
        // spin off a thread to check this lazily, in case a recursive check is required
        [NSThread detachNewThreadSelector:@selector(installRequiresRootPrivileges) toTarget:self withObject:nil];
    }
    return self;
}

- (void)dealloc
{
    if (_fseventStream) {
        FSEventStreamStop(_fseventStream);
        FSEventStreamUnscheduleFromRunLoop(_fseventStream, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
        FSEventStreamRelease(_fseventStream);
    }
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
    NSURL *serverURL = [self defaultServerURL];
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
    [checkTask setLaunchPath:[self tlmgrAbsolutePath]];
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
    TLMTask *checkTask = [TLMTask launchedTaskWithLaunchPath:[self tlmgrAbsolutePath] arguments:args];
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

    // this is kind of slow, so avoid doing it unless we really have to
    if ([location isEqual:[self defaultServerURL]] == NO) {
        TLMLog(__func__, @"Setting command line server location to %@", [[self defaultServerURL] absoluteString]);
        TLMOptionOperation *op = [[TLMOptionOperation alloc] initWithKey:@"location" value:[[self defaultServerURL] absoluteString]];
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

- (TLMDatabaseYear)_texliveYear:(NSString **)versionStr isDevelopmentVersion:(BOOL *)isDev tlmgrVersion:(NSInteger *)tlmgrVersion
{
    // always run the check and log the result
    TLMTask *tlmgrTask = [[TLMTask new] autorelease];
    [tlmgrTask setLaunchPath:[[TLMPreferenceController sharedPreferenceController] tlmgrAbsolutePath]];
    [tlmgrTask setArguments:[NSArray arrayWithObject:@"--version"]];
    [tlmgrTask launch];
    [tlmgrTask waitUntilExit];
    
    NSString *versionString = [tlmgrTask terminationStatus] ? nil : [tlmgrTask outputString];
    
    // !!! this happens periodically, and I don't yet know why...
    if (nil == versionString)
        TLMLog(__func__, @"Failed to read version string: %@, ret = %d", [tlmgrTask errorString], [tlmgrTask terminationStatus]);
    
    versionString = [versionString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray *versionLines = [versionString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSInteger texliveYear = 0;
    if (isDev) *isDev = NO;
    
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
                
                // allow handling development versions differently (not sure this is stable year-to-year)
                if (isDev && [versionString hasSuffix:@"dev"])
                    *isDev = YES;
                
                NSScanner *scanner = [NSScanner scannerWithString:versionString];
                [scanner setCharactersToBeSkipped:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]];
                [scanner scanInteger:&texliveYear];
            }
            
            if ([versionString hasPrefix:@"tlmgr revision"]) {
                
                NSScanner *scanner = [NSScanner scannerWithString:versionString];
                [scanner setCharactersToBeSkipped:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]];
                [scanner scanInteger:tlmgrVersion];
            }
        }
    }
    if (versionStr)
        *versionStr = versionString;
    
    TLMLog(__func__, @"Looks like you're using TeX Live %d", texliveYear);
    
    return texliveYear;
}

- (void)updateTeXBinPathWithURL:(NSURL *)aURL
{
    [_texbinPathControl setURL:aURL];
    [[NSUserDefaults standardUserDefaults] setObject:[aURL path] forKey:TLMTexBinPathPreferenceKey];
        
    [self _resetVersions];
    
    // update environment, or tlmgr will be non-functional
    [TLMAppController updatePathEnvironment];
    
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
    TLMLogServerSync();
    
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
        [self setLegacyRepositoryURL:nil];
        [self _resetVersions];
        
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

- (NSURL *)defaultServerURL
{
    NSString *location = [[NSUserDefaults standardUserDefaults] objectForKey:TLMFullServerURLPreferenceKey];
    while ([location hasSuffix:@"/"])
        location = [location substringToIndex:([location length] - 1)];
    return [NSURL URLWithString:location];    
}

- (void)versionWarningDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    if ([[alert suppressionButton] state] == NSOnState)
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:TLMDisableVersionMismatchWarningKey];
}

- (void)_displayFallbackServerAlert
{
    /*
     Formerly logged that the URL was okay, but that was only correct for the transition from TL 2008 to 2009.
     However, tlmgr itself will perform that check and log if it fails, so logging that it's okay was just
     confusing pretest users.
     */
    TLMDatabaseYear remoteVersion, localVersion;
    @synchronized(self) {
        remoteVersion = _versions.repositoryYear;
        localVersion = _versions.installedYear;
    }
    
    NSAlert *alert = [[NSAlert new] autorelease];
    BOOL allowSuppression;
    if (localVersion == 2008) {
        [alert setMessageText:NSLocalizedString(@"TeX Live 2008 is not supported", @"")];
        [alert setInformativeText:NSLocalizedString(@"This version of TeX Live Utility will not work correctly with TeX Live 2008.  You need to download TeX Live Utility version 0.74 or earlier, or upgrade to a newer TeX Live.  I recommend the latter.", @"")];
        // non-functional, so no point in hiding this alert
        allowSuppression = NO;
    }
    else if (remoteVersion > localVersion) {
        [alert setMessageText:NSLocalizedString(@"Mirror URL has a newer TeX Live version", @"")];
        [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Your TeX Live version is %d, but your default mirror URL appears to be for TeX Live %d.  You need to manually upgrade to a newer version of TeX Live, as there will be no further updates for your version.", @"two integer specifiers"), localVersion, remoteVersion]];
        // nag users into upgrading, to keep them from using ftp.tug.org willy-nilly
        allowSuppression = NO;
    }
    else {
        [alert setMessageText:NSLocalizedString(@"Mirror URL has an older TeX Live version", @"")];
        [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Your TeX Live version is %d, but your default mirror URL appears to be for TeX Live %d.  You need to choose an appropriate mirror.", @"two integer specifiers"), localVersion, remoteVersion]];
        // may come up during pretest
        allowSuppression = YES;
    }


    if (NO == allowSuppression || [[NSUserDefaults standardUserDefaults] boolForKey:TLMDisableVersionMismatchWarningKey] == NO) {
        
        SEL endSel = NULL;
        
        if (allowSuppression) {
            endSel = @selector(versionWarningDidEnd:returnCode:contextInfo:);
            [alert setShowsSuppressionButton:YES];
        }
        
        // always show on the main window
        [alert beginSheetModalForWindow:[[[NSApp delegate] mainWindowController] window] 
                          modalDelegate:self 
                         didEndSelector:endSel 
                            contextInfo:NULL];            
    }
}

- (NSURL *)validServerURL
{
    NSURL *validURL = nil;
    @synchronized(self) {
        
        /*
         Recomputing installedYear and repositoryYear is expensive.
         */
        if (_versions.installedYear == TLMDatabaseUnknownYear)
            _versions.installedYear = [self _texliveYear:NULL isDevelopmentVersion:&_versions.isDevelopment tlmgrVersion:&_versions.tlmgrVersion];

        /*
         Always recompute this, because if we're using the multiplexer, it's going to redirect to
         some other URL.  Eventually we'll get a few of them cached in the TLMDatabase, but this
         is a slowdown if you use mirror.ctan.org.
         */
        TLMDatabaseVersion version = [TLMDatabase versionForMirrorURL:[self defaultServerURL]];
        _versions.repositoryYear = version.year;
        validURL = version.usedURL;
        
        // handled as a separate condition so we can log it for sure
        if (_versions.repositoryYear == TLMDatabaseUnknownYear) {
            TLMLog(__func__, @"Failed to determine the TeX Live version of the repository, so we'll just use the default");
            validURL = [self defaultServerURL];
            NSParameterAssert(validURL != nil);
        }
        else if (_versions.repositoryYear != _versions.installedYear && version.isOfficial) {
            
            if ([self legacyRepositoryURL] == nil) {
                NSString *plistPath = [[NSBundle mainBundle] pathForResource:@"DefaultMirrors" ofType:@"plist"];
                NSDictionary *mirrorsByYear = nil;
                if (plistPath)
                    mirrorsByYear = [NSDictionary dictionaryWithContentsOfFile:plistPath];
                NSString *location = [mirrorsByYear objectForKey:[[NSNumber numberWithShort:_versions.installedYear] stringValue]];
                if (location) {
                    TLMLog(__func__, @"Version mismatch detected.  Trying to fall back to %@", location);
                    [self setLegacyRepositoryURL:[NSURL URLWithString:location]];
                }
                else {
                    TLMLog(__func__, @"Version mismatch detected, but no fallback URL was found.");
                    // ??? avoid using a nil URL for validURL...is this what I want to do?
                    [self setLegacyRepositoryURL:[self defaultServerURL]];
                }
                
                // async sheet with no user interaction, so no point in waiting...
                [self performSelectorOnMainThread:@selector(_displayFallbackServerAlert) withObject:nil waitUntilDone:NO];
            }
            
            validURL = [self legacyRepositoryURL];
            NSParameterAssert(validURL != nil);
        }
        else {
            TLMLog(__func__, @"Mirror version appears to be %d, a good year for TeX Live", _versions.repositoryYear);
            if (version.isOfficial == false)
                TLMLog(__func__, @"This appears to be a 3rd party TeX Live repository");
        }

        NSParameterAssert(validURL != nil);
    }

    return validURL;
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

- (NSString *)_backupDirOption
{
    // kpsewhich -var-value=SELFAUTOPARENT
    NSString *tlmgrPath = [self tlmgrAbsolutePath];
    NSString *backupDir = nil;
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:tlmgrPath]) {
        TLMTask *task = [TLMTask new];
        [task setLaunchPath:tlmgrPath];
        [task setArguments:[NSArray arrayWithObjects:@"option", @"backupdir", nil]];
        [task launch];
        [task waitUntilExit];
        if ([task terminationStatus] == 0 && [task outputString]) {
            NSString *str = [[task outputString] stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
            NSRange r = [str rangeOfString:@": " options:NSLiteralSearch];
            if (r.length)
                backupDir = [[str substringFromIndex:NSMaxRange(r)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }
        else {
            TLMLog(__func__, @"tlmgr returned an error: %@", [task errorString]);
        }
        [task release];
    }
    else {
        TLMLog(__func__, @"no tlmgr executable at %@", tlmgrPath);
    }
    return backupDir;
}

- (NSURL *)backupDirectory
{
    NSString *backupDir = [self _backupDirOption];
    if ([backupDir isAbsolutePath] == NO)
        backupDir = [[[self installDirectory] path] stringByAppendingPathComponent:backupDir];
    return backupDir ? [NSURL fileURLWithPath:backupDir] : nil;
}

- (BOOL)installRequiresRootPrivileges
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    NSString *path = [[self installDirectory] path];
    
    // things are going to fail regardless...
    if (nil == path) {
        [pool release];
        return NO;
    }
    
    NSFileManager *fm = [[NSFileManager new] autorelease];
    
    // !!! early return; check top level first, which is the common case
    if ([fm isWritableFileAtPath:path] == NO) {
        [pool release];
        return YES;
    }
    
    /*
     In older versions, this method considered TLMUseRootHomePreferenceKey and the top level dir.
     This could result in requiring root privileges even if the user had write permission to the
     tree, which caused root-owned files to also be created in the tree.  Consequently, we need
     to do a deep directory traversal for the first check; this takes < 3 seconds on my Mac Pro
     with TL 2010.
     
     By doing this once, I assume that the situation won't change during the lifetime of this 
     process.  I think that's reasonable, so will wait to hear otherwise before monitoring it 
     with FSEventStream or similar madness.
     
     NB: synchronizing on self here caused contention with -validServerURL, and it took a while
     to figure out why it was beachballing on launch after I threaded this check.
     */
    static NSNumber *recursiveRootRequired = nil;
    @synchronized(recursiveRootRequired) {
        if (nil == recursiveRootRequired) {
            
            TLMLog(__func__, @"Recursive check of installation privileges. This will happen once per launch, and may be slow if %@ is on a network filesystem%C", path, 0x2026);
            TLMLogServerSync();
            CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
            
            NSDirectoryEnumerator *dirEnum = [fm enumeratorAtPath:path];
            BOOL rootRequired = NO;
            for (NSString *subpath in dirEnum) {
                
                // okay if this doesn't get released on the break; it'll be caught by the top-level pool
                NSAutoreleasePool *innerPool = [NSAutoreleasePool new];
                subpath = [path stringByAppendingPathComponent:subpath];
                if ([fm fileExistsAtPath:subpath]) {
                    if ([fm isWritableFileAtPath:subpath] == NO) {
                        rootRequired = YES;
                        break;
                    }
                }
                else {
                    // I have a bad symlink at /usr/local/texlive/2010/texmf/doc/man/man; this is MacTeX-specific
                    TLMLog(__func__, @"%@ does not exist; ignoring permissions", subpath);
                }
                [innerPool release];
            }
            recursiveRootRequired = [[NSNumber alloc] initWithBool:rootRequired];
            TLMLog(__func__, @"Recursive check completed in %.1f seconds.  Root privileges %@ required.", CFAbsoluteTimeGetCurrent() - start, rootRequired ? @"are" : @"not");
        }
    }
    
    [pool release];
    
    return [recursiveRootRequired boolValue];
}

- (BOOL)autoInstall { return [[NSUserDefaults standardUserDefaults] boolForKey:TLMAutoInstallPreferenceKey]; }

- (BOOL)autoRemove { return [[NSUserDefaults standardUserDefaults] boolForKey:TLMAutoRemovePreferenceKey]; }

- (TLMDatabaseYear)texliveYear
{
    return _versions.installedYear;
}

- (BOOL)tlmgrSupportsPersistentDownloads;
{
    return (_versions.tlmgrVersion >= 16424);
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
