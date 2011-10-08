//
//  TLMEnvironment.m
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 06/14/11.
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

#import "TLMEnvironment.h"
#import "TLMAppController.h"
#import "TLMPreferenceController.h"
#import "TLMTask.h"
#import "TLMLogServer.h"
#import <pthread.h>

static void __TLMTeXDistChanged(ConstFSEventStreamRef strm, void *context, size_t numEvents, void *eventPaths, const FSEventStreamEventFlags eventFlags[], const FSEventStreamEventId eventIds[]);

@interface TLMEnvironment (Private)

+ (void)updatePathEnvironment;

+ (NSMutableArray *)_systemPaths;
- (void)_displayFallbackServerAlert;
+ (BOOL)_getInstalledYear:(TLMDatabaseYear *)installedYear isDevelopmentVersion:(BOOL *)isDev tlmgrVersion:(NSInteger *)tlmgrVersion;
- (NSString *)_backupDirOption;
- (void)_checkForRootPrivileges;

@end

@interface TLMEnvironment ()

@property (readwrite, copy) NSURL *legacyRepositoryURL;
@property (readwrite, copy) NSString *installDirectory;

@end

#define TLMGR_CMD     @"tlmgr"
#define TEXDOC_CMD    @"texdoc"
#define KPSEWHICH_CMD @"kpsewhich"
#define TEXDIST_PATH  @"/Library/TeX"

#define PERMISSION_CHECK_IN_PROGRESS 1
#define PERMISSION_CHECK_DONE        0

static NSMutableDictionary *_environments = nil;
static NSString            *_currentEnvironmentKey = nil;

@implementation TLMEnvironment

@synthesize legacyRepositoryURL = _legacyRepositoryURL;
@synthesize installDirectory = _installDirectory;

+ (void)initialize
{
    if (nil == _environments)
        _environments = [NSMutableDictionary new];
}

+ (NSString *)_installDirectoryFromCurrentDefaults
{
    NSString *installDirectory = nil;
    // kpsewhich -var-value=SELFAUTOPARENT
    NSString *texbinPath = [[NSUserDefaults standardUserDefaults] objectForKey:TLMTexBinPathPreferenceKey];
    NSString *kpsewhichPath = [[texbinPath stringByAppendingPathComponent:KPSEWHICH_CMD] stringByStandardizingPath];
    if ([[[NSFileManager new] autorelease] isExecutableFileAtPath:kpsewhichPath]) {
        TLMTask *task = [TLMTask new];
        [task setLaunchPath:kpsewhichPath];
        [task setArguments:[NSArray arrayWithObject:@"-var-value=SELFAUTOPARENT"]];
        [task launch];
        [task waitUntilExit];
        if ([task terminationStatus] == 0 && [task outputString]) {
            installDirectory = [[task outputString] stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        }
        else {
            TLMLog(__func__, @"kpsewhich returned an error: %@", [task errorString]);
        }
        [task release];
    }
    else {
        TLMLog(__func__, @"no kpsewhich executable at %@", kpsewhichPath);
    }
    return installDirectory;
}

+ (void)updateEnvironment
{
    @synchronized(_environments) {
        
        NSString *installDir = [self _installDirectoryFromCurrentDefaults];
        if (nil == installDir) {
            TLMLog(__func__, @"No install directory from current defaults; this is very disturbing, and lots of things are going to fail.  You probably need to fix the tlmgr path in preferences.");
        }
        else if ([installDir isEqualToString:_currentEnvironmentKey] == NO) {
            [_currentEnvironmentKey autorelease];
            _currentEnvironmentKey = [installDir copy];
            
            TLMEnvironment *env = [_environments objectForKey:_currentEnvironmentKey];
            if (nil == env) {
                TLMLog(__func__, @"Setting up a new environment for %@%C", installDir, 0x2026);
                [self updatePathEnvironment];
                env = [[self alloc] initWithInstallDirectory:_currentEnvironmentKey];
                [_environments setObject:env forKey:_currentEnvironmentKey];
                [env release];
            }
            else {
                TLMLog(__func__, @"Using cached environment for %@", installDir);
            }

        }
        else {
            TLMLog(__func__, @"Nothing to update for %@", installDir);
        }

    }
}    

+ (TLMEnvironment *)currentEnvironment;
{
    TLMEnvironment *env = nil;
    @synchronized(_environments) {
        env = [_environments objectForKey:_currentEnvironmentKey];
        // okay to call +updateEnvironment inside recursive mutex
        if (nil == env) {
            [self updateEnvironment];
            env = [_environments objectForKey:_currentEnvironmentKey];
        }
        // return a dummy environment in case the user screwed up the path and we failed to get a key
        if (nil == env)
            env = [[self new] autorelease];
    }
    return env;
}

+ (BOOL)isValidTexbinPath:(NSString *)absolutePath;
{
    // for NSFileManager; this is a UI validation method
    NSParameterAssert([NSThread isMainThread]); 
    
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir;
    if ([fm fileExistsAtPath:absolutePath isDirectory:&isDir] && isDir) {
        // check for executable paths here, or bad things happen when we try and set up the environment
        if ([fm isExecutableFileAtPath:[absolutePath stringByAppendingPathComponent:TLMGR_CMD]] == NO)
            return NO;
        if ([fm isExecutableFileAtPath:[absolutePath stringByAppendingPathComponent:KPSEWHICH_CMD]] == NO)
            return NO;
        return YES;
    }
    return NO;
}

- (id)initWithInstallDirectory:(NSString *)absolutePath
{
    NSParameterAssert(absolutePath);
    self = [super init];
    if (self) {
        
        _installDirectory = [absolutePath copy];
        [TLMEnvironment _getInstalledYear:&_installedYear isDevelopmentVersion:&_tlmgrVersion.isDevelopment tlmgrVersion:&_tlmgrVersion.revision];

        if ([[[NSFileManager new] autorelease] fileExistsAtPath:TEXDIST_PATH]) {
            FSEventStreamContext ctxt = { 0, [self class], CFRetain, CFRelease, CFCopyDescription };
            CFArrayRef paths = (CFArrayRef)[NSArray arrayWithObject:TEXDIST_PATH];
            FSEventStreamCreateFlags flags = kFSEventStreamCreateFlagUseCFTypes|kFSEventStreamCreateFlagNoDefer;
            _fseventStream = FSEventStreamCreate(NULL, __TLMTeXDistChanged, &ctxt, paths, kFSEventStreamEventIdSinceNow, 0.1, flags);
            if (_fseventStream) {
                FSEventStreamScheduleWithRunLoop(_fseventStream, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
                FSEventStreamStart(_fseventStream);
            }
        }
        
        // spin off a thread to check this lazily, in case a recursive check is required
        _rootRequiredLock = [[NSConditionLock alloc] initWithCondition:PERMISSION_CHECK_IN_PROGRESS];
        [NSThread detachNewThreadSelector:@selector(_checkForRootPrivileges) toTarget:self withObject:nil];
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
    [_rootRequiredLock release];
    [_legacyRepositoryURL release];
    [_installDirectory release];
    [super dealloc];
}

/*
 Try to account for a user changing the TeX Distribution pref pane.  The effect is
 substantially the same as changing the texbin preference (path to tlmgr), insofar
 as we get a new location for each path accessor and the version changes.
 */
static void __TLMTeXDistChanged(ConstFSEventStreamRef strm, void *context, size_t numEvents, void *eventPaths, const FSEventStreamEventFlags eventFlags[], const FSEventStreamEventId eventIds[])
{
    for (NSUInteger i = 0; i < numEvents; i++) {
        if (eventFlags[i] == kFSEventStreamEventFlagNone) {
            TLMLog(__func__, @"TeX distribution path changed");
            [(Class)context updateEnvironment];
            break;
        }
    }
}

+ (BOOL)_getInstalledYear:(TLMDatabaseYear *)installedYear isDevelopmentVersion:(BOOL *)isDev tlmgrVersion:(NSInteger *)tlmgrVersion
{

    // called from -init, so can't use current environment
    NSString *texbinPath = [[NSUserDefaults standardUserDefaults] objectForKey:TLMTexBinPathPreferenceKey];
    
    // always run the check and log the result
    TLMTask *tlmgrTask = [[TLMTask new] autorelease];
    [tlmgrTask setLaunchPath:[[texbinPath stringByAppendingPathComponent:TLMGR_CMD] stringByStandardizingPath]];
    [tlmgrTask setArguments:[NSArray arrayWithObject:@"--version"]];
    [tlmgrTask launch];
    [tlmgrTask waitUntilExit];
    
    NSString *versionString = [tlmgrTask terminationStatus] ? nil : [tlmgrTask outputString];
    
    // !!! this happens periodically, and I don't yet know why...
    if (nil == versionString) {
        TLMLog(__func__, @"Failed to read version string: %@, ret = %d", [tlmgrTask errorString], [tlmgrTask terminationStatus]);
        return NO;
    }
    
    versionString = [versionString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray *versionLines = [versionString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSInteger texliveYear = 0;
    if (isDev) *isDev = NO;
    
    if ([versionLines count]) {
        
        /*
         Using an svn version of tlmgr:
         $ tlmgr --version
         tlmgr revision unknown ($Date$)
         tlmgr using installation: /usr/local/texlive/2011
         TeX Live (http://tug.org/texlive) version 2011
         
         $ tlmgr --version
         tlmgr revision 14230 (2009-07-11 14:56:31 +0200)
         tlmgr using installation: /usr/local/texlive/2009
         TeX Live (http://tug.org/texlive) version 2009-dev
         
         $ tlmgr --version
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
                if ([scanner scanInteger:tlmgrVersion] == NO)
                    *tlmgrVersion = -1;
            }
        }
    }
    if (installedYear)
        *installedYear = texliveYear;
    
    TLMLog(__func__, @"Looks like you're using TeX Live %d", texliveYear);
    
    return YES;
}

+ (NSMutableArray *)_systemPaths
{
    // return nil on failure: http://code.google.com/p/mactlmgr/issues/detail?id=55
    NSString *str = [NSString stringWithContentsOfFile:@"/etc/paths" encoding:NSUTF8StringEncoding error:NULL];
    NSMutableArray *paths = [NSMutableArray array];
    // one path per line, according to man page for path_helper(8)
    for (NSString *path in [str componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        
        // trim and check for empty string, in case of empty/trailing line
        path = [path stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([path isEqualToString:@""] == NO)
            [paths addObject:path];
    }
    return [paths count] ? paths : nil;
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
        
        // look for path, something possibly TeX related like TEXINPUTS/BIBINPUTS, or one of the proxy-related variables
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"(SELF contains[cd] 'PATH') OR "
                                  @"(SELF contains[cd] 'TEX') OR "
                                  @"(SELF contains 'INPUTS') OR "
                                  @"(SELF contains[cd] '_proxy') OR "
                                  @"(SELF contains 'WGETRC')"];
        NSArray *keys = [[env allKeys] filteredArrayUsingPredicate:predicate];
        if ([keys count]) {
            TLMLog(__func__, @"*** WARNING *** ~/.MacOSX/environment.plist alters critical variables; ignoring PATH if present in %@", keys);
        }
        else {
            // log anyway, since it's a huge PITA to diagnose a screwed up environment
            TLMLog(__func__, @"Found ~/.MacOSX/environment.plist%Cdidn't look too evil.", 0x2026);
        }
        TLMLog(__func__, @"~/.MacOSX/environment.plist = %@", env);
    }
    
    // get the base path from /etc
    NSMutableArray *systemPaths = [self _systemPaths];
    
    // could abort here, but try the default on 10.5+
    if (nil == systemPaths) {
        systemPaths = [NSMutableArray arrayWithObjects:@"/usr/bin", @"/bin", @"/usr/sbin", @"/sbin", @"/usr/local/bin", nil];
        TLMLog(__func__, @"*** ERROR *** Unable to read /etc/paths.");
    }
    NSParameterAssert([systemPaths count]);
    
    NSParameterAssert([[NSUserDefaults standardUserDefaults] objectForKey:TLMTexBinPathPreferenceKey]);
    [systemPaths addObject:[[NSUserDefaults standardUserDefaults] objectForKey:TLMTexBinPathPreferenceKey]];
    NSString *newPath = [systemPaths componentsJoinedByString:@":"];
    NSParameterAssert(newPath);
    
    setenv("PATH", [newPath saneFileSystemRepresentation], 1);
    TLMLog(__func__, @"Using PATH = \"%@\"", systemPaths);
}

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

- (void)_displayFallbackServerAlertForRepositoryYear:(NSNumber *)repositoryYear
{
    NSParameterAssert([NSThread isMainThread]);
    /*
     Formerly logged that the URL was okay, but that was only correct for the transition from TL 2008 to 2009.
     However, tlmgr itself will perform that check and log if it fails, so logging that it's okay was just
     confusing pretest users.
     */
    TLMDatabaseYear remoteVersion = [repositoryYear integerValue];
    
    NSAlert *alert = [[NSAlert new] autorelease];
    BOOL allowSuppression;
    if (_installedYear == 2008) {
        [alert setMessageText:NSLocalizedString(@"TeX Live 2008 is not supported", @"")];
        [alert setInformativeText:NSLocalizedString(@"This version of TeX Live Utility will not work correctly with TeX Live 2008.  You need to download TeX Live Utility version 0.74 or earlier, or upgrade to a newer TeX Live.  I recommend the latter.", @"")];
        // non-functional, so no point in hiding this alert
        allowSuppression = NO;
    }
    else if (remoteVersion > _installedYear) {
        [alert setMessageText:NSLocalizedString(@"Mirror URL has a newer TeX Live version", @"")];
        [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Your TeX Live version is %d, but your default mirror URL appears to be for TeX Live %d.  You need to manually upgrade to a newer version of TeX Live, as there will be no further updates for your version.", @"two integer specifiers"), _installedYear, remoteVersion]];
        // nag users into upgrading, to keep them from using ftp.tug.org willy-nilly
        allowSuppression = NO;
    }
    else {
        [alert setMessageText:NSLocalizedString(@"Mirror URL has an older TeX Live version", @"")];
        [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Your TeX Live version is %d, but your default mirror URL appears to be for TeX Live %d.  You need to choose an appropriate mirror.", @"two integer specifiers"), _installedYear, remoteVersion]];
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

- (BOOL)_getValidServerURL:(NSURL **)outURL repositoryYear:(TLMDatabaseYear *)outYear
{        
    NSParameterAssert(_installedYear != TLMDatabaseUnknownYear);
    NSParameterAssert(outURL);
    NSParameterAssert(outYear);
    
    /*
     Always recompute this, because if we're using the multiplexer, it's going to redirect to
     some other URL.  Eventually we'll get a few of them cached in the TLMDatabase, but this
     is a slowdown if you use mirror.ctan.org.
     */
    TLMDatabase *db = [TLMDatabase databaseForMirrorURL:[self defaultServerURL]];
    const TLMDatabaseYear repositoryYear = [db texliveYear];
    NSURL *validURL = [db mirrorURL];
        
    if ([db failed]) {
        
        // not correct to show an error sheet here, since this may not be the main thread
        validURL = nil;
    }
    else if (repositoryYear == TLMDatabaseUnknownYear) {
        
        // handled as a separate condition so we can log it for sure
        TLMLog(__func__, @"Failed to determine the TeX Live version of the repository, so we'll just try the default server");
        validURL = [self defaultServerURL];
    }
    else if ([db isOfficial] == NO) {
        
        // no fallback URL for unofficial repos, so just warn and let the user deal with it
        TLMLog(__func__, @"This appears to be a 3rd party TeX Live repository");
        if (repositoryYear != _installedYear)
            TLMLog(__func__, @"*** WARNING *** This repository is for TeX Live %d, but you are using TeX Live %d", repositoryYear, _installedYear);
    }
    else if (repositoryYear != _installedYear) {
        
        // this fallback is only for official repos
        NSParameterAssert([db isOfficial]);
                
        if ([self legacyRepositoryURL] == nil) {
            NSString *plistPath = [[NSBundle mainBundle] pathForResource:@"DefaultMirrors" ofType:@"plist"];
            NSDictionary *mirrorsByYear = nil;
            if (plistPath)
                mirrorsByYear = [NSDictionary dictionaryWithContentsOfFile:plistPath];
            NSString *location = [mirrorsByYear objectForKey:[[NSNumber numberWithInt:_installedYear] stringValue]];
            if (location) {
                TLMLog(__func__, @"Version mismatch detected.  Trying to fall back to %@", location);
                [self setLegacyRepositoryURL:[NSURL URLWithString:location]];
            }
            else {
                TLMLog(__func__, @"Version mismatch detected, but no fallback URL was found.");
                // !!! return a nil URL; this is a stale server, and we might want to retry
            }
        }
        
        validURL = [self legacyRepositoryURL];
    }
    else {
        
        // official db of the correct year; removed this branch, but users wanted the message back
        CFTimeZoneRef tz = CFTimeZoneCopyDefault();
        CFGregorianDate currentDate = CFAbsoluteTimeGetGregorianDate(CFAbsoluteTimeGetCurrent(), tz);
        CFRelease(tz);
        TLMDatabaseYear age = currentDate.year - repositoryYear;
        NSString *ageString = age == 0 ? @"a young TeX Live" : @"a mature TeX Live";
        
        TLMLog(__func__, @"Mirror version appears to be %d; %@", repositoryYear, ageString);
    }
        
    *outURL = validURL;
    *outYear = repositoryYear;
    return [db failed];
}

- (NSURL *)validServerURL
{
    // will be nil on failure; always initialized
    NSURL *validURL;
    TLMDatabaseYear repositoryYear;
    
    // false return value signifies TLMDatabase failure (usually a network problem)
    BOOL dbFailed = [self _getValidServerURL:&validURL repositoryYear:&repositoryYear];

    /*
     This is a special case for the multiplexer, which can return a stale server; retry
     when have a nil URL but not due to a network issue.  This should mean that we were
     not able to find a legacy repository, so likely it's an old server.  This happens
     frequently around the time of a new TL release.
     */
    if (nil == validURL && [[self defaultServerURL] isMultiplexer] && NO == dbFailed) {
        int tryCount = 2;
        const int maxTries = 5;
        while (nil == validURL && tryCount <= maxTries) {
            TLMLog(__func__, @"Stale mirror returned from multiplexer.  Requesting another mirror (attempt %d of %d).", tryCount, maxTries);
            (void) [self _getValidServerURL:&validURL repositoryYear:&repositoryYear];
            tryCount++;
        }
    }
    
    // Moved this check out of _getValidServer:repositoryYear: to avoid issues in the loop above
    if (nil == validURL && NO == dbFailed) {
        [self performSelectorOnMainThread:@selector(_displayFallbackServerAlertForRepositoryYear:) 
                               withObject:[NSNumber numberWithInteger:repositoryYear] 
                            waitUntilDone:NO];
    }
    
    return validURL;
}

- (NSString *)_backupDirOption
{
    // kpsewhich -var-value=SELFAUTOPARENT
    NSString *tlmgrPath = [self tlmgrAbsolutePath];
    NSString *backupDir = nil;
    if ([[[NSFileManager new] autorelease] isExecutableFileAtPath:tlmgrPath]) {
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
        backupDir = [[self installDirectory] stringByAppendingPathComponent:backupDir];
    return backupDir ? [NSURL fileURLWithPath:backupDir] : nil;
}

- (BOOL)installRequiresRootPrivileges
{
    /*
     Normally should succeed immediately, after the check thread is
     spun off at init time.  The lock is only to account for the race
     window between the time init returns and the time this method is
     first called.  Normally there should be no contention for this
     resource, so the lock overhead is negligible.
     */
    [_rootRequiredLock lockWhenCondition:PERMISSION_CHECK_DONE];
    BOOL ret = _rootRequired;
    [_rootRequiredLock unlock];
    return ret;
}

- (void)_checkForRootPrivileges;
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    [_rootRequiredLock lockWhenCondition:PERMISSION_CHECK_IN_PROGRESS];
    
    NSString *path = [self installDirectory];
    NSParameterAssert(path);
    
    NSFileManager *fm = [[NSFileManager new] autorelease];
    
    /*
     In older versions, this method considered TLMUseRootHomePreferenceKey and the top level dir.
     This could result in requiring root privileges even if the user had write permission to the
     tree, which caused root-owned files to also be created in the tree.  Consequently, we need
     to do a deep directory traversal for the first check; this takes < 3 seconds on my Mac Pro
     with TL 2010.
     
     By doing this once, I assume that the situation won't change during the lifetime of this 
     process.  I think that's reasonable, so will wait to hear otherwise before monitoring it 
     with FSEventStream or similar madness.
     */
   
    // check for writable top-level directory, before doing any traversal
    if ([fm isWritableFileAtPath:path]) {
        TLMLog(__func__, @"Recursive check of installation privileges. This will happen once per launch, and may be slow if %@ is on a network filesystem%C", path, 0x2026);
        TLMLogServerSync();
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        
        NSDirectoryEnumerator *dirEnum = [fm enumeratorAtPath:path];
        for (NSString *subpath in dirEnum) {
            
            // okay if this doesn't get released on the break; it'll be caught by the top-level pool
            NSAutoreleasePool *innerPool = [NSAutoreleasePool new];
            subpath = [path stringByAppendingPathComponent:subpath];
            if ([fm fileExistsAtPath:subpath]) {
                if ([fm isWritableFileAtPath:subpath] == NO) {
                    _rootRequired = YES;
                    [innerPool release];
                    break;
                }
            }
            else {
                // I have a bad symlink at /usr/local/texlive/2010/texmf/doc/man/man; this is MacTeX-specific
                TLMLog(__func__, @"%@ does not exist; ignoring permissions", subpath);
            }
            [innerPool release];
        }
        TLMLog(__func__, @"Recursive check completed in %.1f seconds.  Root privileges %@ required.", CFAbsoluteTimeGetCurrent() - start, _rootRequired ? @"are" : @"not");
    }
    else {
        TLMLog(__func__, @"Root permission required for installation at %@", path);
        _rootRequired = YES;
    }

    [_rootRequiredLock unlockWithCondition:PERMISSION_CHECK_DONE];
    [pool release];    
}

- (BOOL)autoInstall { return [[NSUserDefaults standardUserDefaults] boolForKey:TLMAutoInstallPreferenceKey]; }

- (BOOL)autoRemove { return [[NSUserDefaults standardUserDefaults] boolForKey:TLMAutoRemovePreferenceKey]; }

- (TLMDatabaseYear)texliveYear
{
    return _installedYear;
}

- (BOOL)tlmgrSupportsPersistentDownloads;
{
    return (_tlmgrVersion.revision >= 16424);
}

- (BOOL)tlmgrSupportsDumpTlpdb
{
    return (_tlmgrVersion.revision >= 22912);
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

@end
