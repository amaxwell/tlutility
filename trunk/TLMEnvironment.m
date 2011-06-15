//
//  TLMEnvironment.m
//  TeX Live Manager
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

- (NSURL *)_installDirectory;
- (void)_resetVersions;
+ (NSMutableArray *)_systemPaths;
- (void)_displayFallbackServerAlert;
- (TLMDatabaseYear)_texliveYear:(NSString **)versionStr isDevelopmentVersion:(BOOL *)isDev tlmgrVersion:(NSInteger *)tlmgrVersion;
- (NSString *)_backupDirOption;

@end

@interface TLMEnvironment ()

@property (readwrite, copy) NSURL *legacyRepositoryURL;
@property (readwrite, copy) NSURL *installDirectory;
@property (readwrite, copy) NSNumber *recursiveRootCheckRequired;

@end

#define TLMGR_CMD     @"tlmgr"
#define TEXDOC_CMD    @"texdoc"
#define KPSEWHICH_CMD @"kpsewhich"
#define TEXDIST_PATH  @"/Library/TeX"

static NSString *_permissionCheckLock = @"permissionCheckLockString";
static NSMutableDictionary *_environments = nil;

@implementation TLMEnvironment

@synthesize legacyRepositoryURL = _legacyRepositoryURL;
@synthesize installDirectory = _installDirectory;
@synthesize recursiveRootCheckRequired = _recursiveRootRequired;

+ (void)initialize
{
    if (nil == _environments)
        _environments = [NSMutableDictionary new];
}

/*
 TODO:
 
 Compute state at -init and store it.  This will be an immutable object, where a given TL
 distro has path, version, and permissions associated with it.  In that case, we only have
 one-time cost in computing variables.
 
 If user changes path to tlmgr or changes TeX Dist prefs, we just set or create a new
 environment, which is also immutable.  The only problematic bit, then, is dealing with
 server URL versions, but at least the local db version will be the same (year) per-instance
 since you can't upgrade TL major versions.
 
 Have to make sure I don't allow users to change any options that I cache, but I think
 keeping ivars of any tlmgr options is fair game, since someone who is mucking about in the
 Terminal with tlmgr option while running TLU deserves whatever he gets.
 
 */

+ (TLMEnvironment *)currentEnvironment;
{
    TLMEnvironment *env = nil;
    @synchronized(_environments) {
        // should be SELFAUTOPARENT
        NSString *path = [[NSUserDefaults standardUserDefaults] objectForKey:TLMTexBinPathPreferenceKey];
        env = [_environments objectForKey:path];
        if (nil == env) {
            env = [self new];
            [_environments setObject:env forKey:path];
            [env release];
        }
    }
    return env;
}

- (id)init
{
    self = [super init];
    if (self) {
        
        _versions.repositoryYear = TLMDatabaseUnknownYear;
        _versions.installedYear = TLMDatabaseUnknownYear;
        _versions.tlmgrVersion = -1;
        _versions.isDevelopment = NO;
        
        _installDirectory = [[self _installDirectory] retain];
        
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
    [_recursiveRootRequired release];
    [_legacyRepositoryURL release];
    [_installDirectory release];
    [super dealloc];
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
        [self setInstallDirectory:[self _installDirectory]];
        [self setRecursiveRootCheckRequired:nil];
    }    
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
            [(TLMEnvironment *)context _resetVersions];
            break;
        }
    }
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


- (TLMDatabaseYear)_texliveYear:(NSString **)versionStr isDevelopmentVersion:(BOOL *)isDev tlmgrVersion:(NSInteger *)tlmgrVersion
{
    // always run the check and log the result
    TLMTask *tlmgrTask = [[TLMTask new] autorelease];
    [tlmgrTask setLaunchPath:[[TLMEnvironment currentEnvironment] tlmgrAbsolutePath]];
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
    if (versionStr)
        *versionStr = versionString;
    
    TLMLog(__func__, @"Looks like you're using TeX Live %d", texliveYear);
    
    return texliveYear;
}

+ (void)updateEnvironment
{
    [self updatePathEnvironment];
    [[self currentEnvironment] _resetVersions];
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

- (NSURL *)_installDirectory
{
    NSURL *installDirectory = nil;
    // kpsewhich -var-value=SELFAUTOPARENT
    NSString *kpsewhichPath = [self kpsewhichAbsolutePath];
    NSFileManager *fm = [[NSFileManager new] autorelease];
    if ([fm isExecutableFileAtPath:kpsewhichPath]) {
        TLMTask *task = [TLMTask new];
        [task setLaunchPath:kpsewhichPath];
        [task setArguments:[NSArray arrayWithObject:@"-var-value=SELFAUTOPARENT"]];
        [task launch];
        [task waitUntilExit];
        if ([task terminationStatus] == 0 && [task outputString]) {
            NSString *str = [[task outputString] stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
            installDirectory = [NSURL fileURLWithPath:str isDirectory:YES];
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
    BOOL rootRequired = NO;
    @synchronized(_permissionCheckLock) {
        if (nil == _recursiveRootRequired) {
            
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
                        rootRequired = YES;
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
            _recursiveRootRequired = [[NSNumber alloc] initWithBool:rootRequired];
            TLMLog(__func__, @"Recursive check completed in %.1f seconds.  Root privileges %@ required.", CFAbsoluteTimeGetCurrent() - start, rootRequired ? @"are" : @"not");
        }
        rootRequired = [_recursiveRootRequired boolValue];
    }
    [pool release];
    
    return rootRequired;
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
