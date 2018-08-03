//
//  TLMEnvironment.m
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 06/14/11.
/*
 This software is Copyright (c) 2008-2016
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
#import "TLMOptionOperation.h"
#import "TLMReadWriteOperationQueue.h"
#import "TLMTask.h"
#import "TLMLogServer.h"
#import "TLMSizeFormatter.h"
#import "TLMProxyManager.h"
#import "TLMMainWindowController.h"
#import <pthread.h>
#import <sys/stat.h>

NSString * const TLMDefaultRepositoryChangedNotification = @"TLMDefaultRepositoryChangedNotification";

static void __TLMTeXDistChanged(ConstFSEventStreamRef strm, void *context, size_t numEvents, void *eventPaths, const FSEventStreamEventFlags eventFlags[], const FSEventStreamEventId eventIds[]);

@interface TLMEnvironment (Private)

+ (void)updatePathEnvironment;

+ (void)_ensureSaneEnvironment;
+ (BOOL)_checkSystemPythonMajorVersion:(NSInteger *)major minorVersion:(NSInteger *)minor;
+ (void)_checkProcessUmask;
+ (void)_logEnvironment;

+ (NSMutableArray *)_systemPaths;
- (void)_displayFallbackServerAlert;
- (void)_checkForRootPrivileges;

@end

@interface TLMEnvironment ()

@property (readwrite, copy) NSURL *legacyRepositoryURL;
@property (readwrite, copy) NSString *installDirectory;

@end

#define TLMGR_CMD     @"tlmgr"
#define TEXDOC_CMD    @"texdoc"
#define KPSEWHICH_CMD @"kpsewhich"
#define UPDMAP_CMD    @"updmap"
#define GPG_CMD       @"gpg"
#define TEXDIST_PATH  @"/Library/TeX"

#define PERMISSION_CHECK_IN_PROGRESS 1
#define PERMISSION_CHECK_DONE        0

static NSMutableDictionary *_environments = nil;
static NSString            *_currentEnvironmentKey = nil;
static bool                 _didShowElCapitanPathAlert = false;
static bool                 _didShowBadTexbinPathAlert = false;

@implementation TLMEnvironment

@synthesize legacyRepositoryURL = _legacyRepositoryURL;
@synthesize installDirectory = _installDirectory;

+ (void)initialize
{
    if (nil == _environments)
        _environments = [NSMutableDictionary new];
    
    // we'll just assume umask, python, and hardware are invariant for the life of the program
    static bool oneTimeChecksDone = false;
    if (false == oneTimeChecksDone) {
        
        NSDictionary *infoPlist = [[NSBundle mainBundle] infoDictionary];
        NSProcessInfo *pInfo = [NSProcessInfo processInfo];
        NSFormatter *memsizeFormatter = [[TLMSizeFormatter new] autorelease];
        NSString *memsize = [memsizeFormatter stringForObjectValue:[NSNumber numberWithUnsignedLongLong:[pInfo physicalMemory]]];
        TLMLog(__func__, @"Welcome to %@ %@, running under Mac OS X %@ with %lu/%lu processors active and %@ physical memory.", [infoPlist objectForKey:(id)kCFBundleNameKey], [infoPlist objectForKey:(id)kCFBundleVersionKey], [pInfo operatingSystemVersionString], (unsigned long)[pInfo activeProcessorCount], (unsigned long)[pInfo processorCount], memsize);
        
        [self _checkProcessUmask];
        [self _ensureSaneEnvironment];
        
        /*
         Call before anything uses tlmgr. Note that because of the
         Yosemite environment variable workarounds, this could now
         trigger a call to +[TLMEnvironment updateEnvironment].
         */
        [[TLMProxyManager sharedManager] updateProxyEnvironmentForURL:nil];

    }
    
}

+ (void)_updatePathAlert:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    // if the user chooses to keep the bad path or edit manually, we end up showing the alert again
    _didShowElCapitanPathAlert = true;
    
    switch (returnCode) {
        case NSAlertFirstButtonReturn:
            [[NSUserDefaults standardUserDefaults] setObject:@"/Library/TeX/texbin" forKey:TLMTexBinPathPreferenceKey];
            [[(TLMAppController *)[NSApp delegate] mainWindowController] refreshUpdatedPackageList];
            break;
        case NSAlertSecondButtonReturn:
            [[TLMPreferenceController sharedPreferenceController] showWindow:nil];
            break;
        default:
            TLMLog(__func__, @"User has a bad path and chose to follow it.");
            break;
    }
}

+ (NSString *)_installDirectoryFromCurrentDefaults
{
    NSString *installDirectory = nil;
    NSString *texbinPath = [[NSUserDefaults standardUserDefaults] objectForKey:TLMTexBinPathPreferenceKey];
    
    NSString *libdir = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSLocalDomainMask, YES) lastObject];
    
    // see if we have TL 2015
    NSString *newCmdPath = [NSString pathWithComponents:[NSArray arrayWithObjects:libdir, @"TeX", @"texbin", @"tlmgr", nil]];
    
    // we are on El Cap or later, have the original mactex default, and have installed mactex 2015
    if (floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_10_Max &&
        [texbinPath isEqualToString:@"/usr/texbin"] &&
        [[NSFileManager defaultManager] isExecutableFileAtPath:newCmdPath] &&
        false == _didShowElCapitanPathAlert) {
        
        // shown here, so it's early enough to be the first alert and avoid OS X ignoring a second sheet
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"TeX installation not found.", @"alert sheet title")];
        [alert setInformativeText:NSLocalizedString(@"Your preferences need to be adjusted for new Apple requirements. Would you like to change your TeX Programs location from /usr/texbin to /Library/TeX/texbin or set it manually?", @"alert message text")];
        [alert addButtonWithTitle:NSLocalizedString(@"Change", @"alert button title")];
        [alert addButtonWithTitle:NSLocalizedString(@"Manually", @"alert button title")];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"alert button title")];
        [alert beginSheetModalForWindow:[(NSWindowController *)[(TLMAppController *)[NSApp delegate] mainWindowController] window]
                          modalDelegate:self
                         didEndSelector:@selector(_updatePathAlert:returnCode:contextInfo:)
                            contextInfo:NULL];
    }
    else {
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
    }
    return installDirectory;
}

/*
 This is a disgusting hack to allow us to fix a local database path once at startup,
 because of some snafu with TL 2017 where it makes the tlpdb read-only. I could move
 the authorized operation stuff in here and check for it every time we get a new
 environment, but I frankly don't want to. There might be a better place to do the
 fix than in TLMMainWindowController, but it has to be early, and in a method that
 doesn't return an object since it's asynchronous. This means that I can't do it from
 +currentEnvironment, as far as I can see.
 */
+ (NSString *)localDatabasePath;
{
    return [[[NSURL databaseURLForTLNetURL:[NSURL fileURLWithPath:[self _installDirectoryFromCurrentDefaults]]] tlm_normalizedURL] path];
}

+ (BOOL)localDatabaseIsReadable;
{
    NSFileManager *fm = [[NSFileManager new] autorelease];
    return [fm isReadableFileAtPath:[self localDatabasePath]];
}

+ (void)_updatePathAlert2:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    _didShowBadTexbinPathAlert = true;
    switch (returnCode) {
        case NSAlertFirstButtonReturn:
            [[TLMPreferenceController sharedPreferenceController] showWindow:nil];
            break;
        default:
            TLMLog(__func__, @"User has a bad path and chose to follow it.");
            break;
    }
}

+ (void)updateEnvironment
{
    @synchronized(_environments) {
        
        NSString *installDir = [self _installDirectoryFromCurrentDefaults];
        if (nil == installDir) {

            /*
             Shown here, so it's early enough to be the first alert and avoid OS X ignoring a second sheet.
             We need a static variable since a bunch of stuff (including prefs window?) calls the
             environment, and we can end up with the same sheet repeating over and over.
             */
            if (false == _didShowBadTexbinPathAlert) {
                TLMLog(__func__, @"No install directory from current defaults; this is very disturbing, and lots of things are going to fail.  You probably need to fix the tlmgr path in preferences.");
                NSAlert *alert = [[NSAlert new] autorelease];
                [alert setMessageText:NSLocalizedString(@"TeX installation not found.", @"alert sheet title")];
                [alert setInformativeText:NSLocalizedString(@"If you have installed TeX Live, you need to tell TeX Live Utility where to find TeX programs. For MacTeX 2015 and later, you should use /Library/TeX/texbin. Change settings now?", @"alert message text")];
                [alert addButtonWithTitle:NSLocalizedString(@"Change", @"alert button title")];
                [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"alert button title")];
                [alert setShowsHelp:YES];
                [alert setHelpAnchor:@"preferences"];
                [alert beginSheetModalForWindow:[(NSWindowController *)[(TLMAppController *)[NSApp delegate] mainWindowController] window]
                                  modalDelegate:self
                                 didEndSelector:@selector(_updatePathAlert2:returnCode:contextInfo:)
                                    contextInfo:NULL];
            }
        }
        else if ([installDir isEqualToString:_currentEnvironmentKey] == NO) {
            [_currentEnvironmentKey autorelease];
            _currentEnvironmentKey = [installDir copy];
            
            TLMEnvironment *env = [_environments objectForKey:_currentEnvironmentKey];
            if (nil == env) {
                TLMLog(__func__, @"Setting up a new environment for %@%C", installDir, TLM_ELLIPSIS);
                [self updatePathEnvironment];
                env = [[self alloc] initWithInstallDirectory:_currentEnvironmentKey];
                [_environments setObject:env forKey:_currentEnvironmentKey];
                [env release];
                [self _logEnvironment];

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
        TLMDatabase *db = [TLMDatabase databaseForMirrorURL:[NSURL fileURLWithPath:_installDirectory]];
        _installedYear = db ? [db texliveYear] : TLMDatabaseUnknownYear;
        if (TLMDatabaseUnknownYear == _installedYear)
            TLMLog(__func__, @"Failed to determine local TeX Live version information.  This is a very bad sign.");
        else
            TLMLog(__func__, @"Looks like you're using TeX Live %lu", (long)_installedYear);

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
        /*
         FSEvent is apparently buggy on (at least) 10.8, as I'm now getting 
         nonzero flags. This is obviously bullshit, since I'm not passing
         kFSEventStreamCreateFlagFileEvents when creating the stream. We also
         seem to get multiple calls here for a single event.
         */
        TLMLog(__func__, @"Change notice with flags %0#x. Assuming broken Apple FSEvents code, updating environment anyway.", (unsigned int)eventFlags[i]);
        [(Class)context updateEnvironment];
        break;
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

static void __TLMTestAndClearEnvironmentVariable(const char *name)
{
    const char *value = getenv(name);
    if (NULL != value) {
        static bool didWarn = false;
        if (false == didWarn)
            TLMLog(__func__, @"*** WARNING *** \nModified environment variables are not supported by TeX Live Utility, and most users have no business setting them.  This means you!");
        didWarn = true;
        TLMLog(__func__, @"Clearing environment variable %s=%s", name, value);
        unsetenv(name);
    }
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
            TLMLog(__func__, @"Found ~/.MacOSX/environment.plist%Cdidn't look too evil.", TLM_ELLIPSIS);
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
    /*
     17 Nov 2014: user ended up with /usr/local/bin prepended to his PATH somehow,
     and also had an ancient and/or broken Python version in /usr/local/bin. Since
     we shouldn't need /usr/local/bin in the PATH, let's just remove it.
     */
    [systemPaths removeObject:@"/usr/local/bin"];
    
    // prepend TL to PATH in case of macports or fink TL
    [systemPaths insertObject:[[NSUserDefaults standardUserDefaults] objectForKey:TLMTexBinPathPreferenceKey] atIndex:0];
    NSString *newPath = [systemPaths componentsJoinedByString:@":"];
    NSParameterAssert(newPath);
    
    setenv("PATH", [newPath saneFileSystemRepresentation], 1);
    TLMLog(__func__, @"Using PATH = \"%@\"", systemPaths);
    
    /*
     This depends on the PATH, so ensure that it's checked after PATH is cleaned up.
     I first added this in +initialize, but it didn't pick up problems when the user
     had an old Python in /usr/local/bin (and /usr/local/bin was first in PATH).
     */
    NSInteger major, minor;
    if ([self _checkSystemPythonMajorVersion:&major minorVersion:&minor] && (major != 2 || minor < 6)) {
        // https://code.google.com/p/mactlmgr/issues/detail?id=103
        TLMLog(__func__, @"*** WARNING *** Unsupported python version. Attempting to work around.");
        // lowest common denominator of Python that we support
        // NB: Yosemite symlinks Python 2.5 -> Python 2.6
        setenv("VERSIONER_PYTHON_VERSION", "2.6", 1);
        // check again; just log, since there's no point in trying more than one fallback version
        [self _checkSystemPythonMajorVersion:&major minorVersion:&minor];
    }
}

+ (void)_ensureSaneEnvironment;
{

    /*
     Config.guess uses a really stupid test for 64 bit, and invokes the compiler
     stub on 10.9, prompting the user to install dev tools. Setting this envvar
     bypasses that test, so config.guess reports that we are
     i386-apple-darwin12.5.0 vs. x86_64-apple-darwin12.5.0
     for a Mac Pro running 10.8.
     */
    setenv("CC_FOR_BUILD", "no_compiler_found", 1);
    
    /*
     I have a user on Lion who removed his environment.plist file, yet still has some bizarre
     paths for various environment variables, including TEXINPUTS.  I suspect this is set from
     launchd.conf or similar.  Sadly, users are finding and documenting this:
     
     http://stackoverflow.com/questions/603785/environment-variables-in-mac-os-x/4567308#4567308
     
     The man page on 10.6.8 sez $HOME/.launchd.conf is unsupported, so I expect this will only
     be a problem on 10.7 and later systems, especially if/when environment.plist is phased out.
     
     Damn Apple for documenting this online and not updating the manual page as of 10.8.5.
     Apparently they decided to use /etc/launchd-user.conf.
     
     http://support.apple.com/kb/HT2202?viewlocale=en_US&locale=en_US
     
     Thanks to a user who set umask to 077 (WTF?) and at least pointed to this KB article as
     the source of his…inspiration.
     
     */
    
    NSArray *launchdConfigPaths = [NSArray arrayWithObjects:@"~/.launchd.conf", @"/etc/launchd.conf", @"/etc/launchd-user.conf", nil];
    for (NSString *launchdConfigPath in launchdConfigPaths) {
        NSString *launchdConfig = [NSString stringWithContentsOfFile:[launchdConfigPath stringByStandardizingPath] encoding:NSUTF8StringEncoding error:NULL];
        
        // used to check for setenv, but umask doesn't require that
        if (launchdConfig) {
            TLMLog(__func__, @"*** WARNING *** User has %@ file", launchdConfigPath);
            TLMLog(__func__, @"%@ = (\n%@\n)", launchdConfigPath, launchdConfig);
        }
    }
    
    /*
     Here's a concrete case where setting environment variables for all GUI applications
     led to problems for TLU.
     
     http://tug.org/pipermail/tex-live/2012-June/031800.html
     
     BIBINPUTS=.:/DropBox/Bibliography//:
     BSTINPUTS=.//:/Users/xxx/Library/texmf//:/Users/xxx/Documents/Figures//:/opt/local/share/texmf//:
     TEXINPUTS=.//:/Users/xxx/Library/texmf//:/Users/xxx/Documents/Figures//:/opt/local/share/texmf//:
     
     When a user tries to set paper size in TLU, I run
     
     $ tlmgr pdftex paper --list
     
     to see what the user's default paper size is, and allow changing
     it to other values in the list.  Apparently this invokes
     
     kpsewhich --progname=pdftex --format="tex" pdftexconfig.tex
     
     at some point, and it ended up walking the entire filesystem in this case
     due to the leading .//: in his TEXINPUTS variable.  The user was
     overriding these vars in shell config files, so did not experience the
     problem with tlmgr on the command line.  Aargh!
     
     Discussion with Karl on mactex list on 27 June 2012 confirms that
     setting a clean environment should be safe, so that may be an option in
     future.  Recall that the proxy envvars must be preserved, though!
     In the meantime, TEXCONFIG and TEXMFCONFIG are also potential problems,
     so we'll clear those.
     
     */
    __TLMTestAndClearEnvironmentVariable("TEXINPUTS");
    __TLMTestAndClearEnvironmentVariable("TEXCONFIG");
    __TLMTestAndClearEnvironmentVariable("TEXMFCONFIG");

    // probably irrelevant, but the user having problems was setting them
    __TLMTestAndClearEnvironmentVariable("BIBINPUTS");
    __TLMTestAndClearEnvironmentVariable("BSTINPUTS");
    __TLMTestAndClearEnvironmentVariable("MFINPUTS");
    
    /*
     See email from Justin to mactex on 2 Oct 2012.
     Passing -E as first arg to /usr/bin/python should
     take care of the problem, as it ignores all PYTHON*
     vars.  However, I think it's useful to have an obnoxious
     warning message to reinforce the idea that setting envvars
     can cause problems for GUI programs.
     */
    __TLMTestAndClearEnvironmentVariable("PYTHONHOME");
    __TLMTestAndClearEnvironmentVariable("PYTHONPATH");
    
}

+ (BOOL)_checkSystemPythonMajorVersion:(NSInteger *)major minorVersion:(NSInteger *)minor;
{
    NSString *versionCheckPath = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"python_version.py"];
    
    TLMTask *versionCheckTask = [[TLMTask new] autorelease];
    [versionCheckTask setLaunchPath:versionCheckPath];
    [versionCheckTask launch];
    [versionCheckTask waitUntilExit];
    BOOL ret = NO;
    
    if ([versionCheckTask terminationStatus] == EXIT_SUCCESS) {
        if ([versionCheckTask outputString]) {
            NSArray *lines = [[versionCheckTask outputString] componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
            if ([lines count] >= 4) {
                TLMLog(__func__, @"Using python at '%@'", [lines objectAtIndex:0]);
                TLMLog(__func__, @"Python version is %@\n%@", [lines objectAtIndex:1], [lines objectAtIndex:2]);
                NSString *version = [lines objectAtIndex:3];
                NSScanner *scanner = [NSScanner scannerWithString:version];
                if ([scanner scanInteger:major] && [scanner scanInteger:minor])
                    return YES;
            }
            //TLMLog(__func__, @"%@", [versionCheckTask outputString]);
        }
        
        // !!! NSAlert here?
        if ([versionCheckTask errorString])
            TLMLog(__func__, @"%@", [versionCheckTask errorString]);
    }
    else {
        // should never happen, so not bothering with NSAlert
        TLMLog(__func__, @"*** ERROR *** Unable to run a Python task: %@", [versionCheckTask errorString]);
    }
    return ret;
}

+ (void)_checkProcessUmask
{
    const mode_t currentMask = umask(0);
    (void) umask(currentMask);
    
    // don't reset umask; that's the user or sysadmin's prerogative
    const mode_t defaultMask = (S_IRWXU | S_IRWXG | S_IRWXO) & ~S_IRWXU & ~S_IRGRP & ~S_IROTH & ~S_IXGRP & ~S_IXOTH;
    
    NSString *umaskString = [NSString stringWithFormat:@"%03o", currentMask];
    NSString *defaultMaskString = [NSString stringWithFormat:@"%03o", defaultMask];
    
    TLMLog(__func__, @"Process umask = %@", umaskString);
    
    if (defaultMask != currentMask)
        TLMLog(__func__, @"*** WARNING *** You have altered the system's umask from %@ to %@. If you have made it more restrictive, installing updates with TeX Live Utility may cause TeX Live to become unusable.", defaultMaskString, umaskString);
    
    // check for g=rx, o=rx permissions
    if ((currentMask & S_IROTH) != 0 || (currentMask & S_IRGRP) != 0 || (currentMask & S_IXGRP) != 0 || (currentMask & S_IXOTH) != 0) {
        // allow suppression on this, since it may be installed with user ownership, not root
        if ([[NSUserDefaults standardUserDefaults] boolForKey:TLMDisableUmaskWarningKey] == NO) {
            NSAlert *alert = [[NSAlert new] autorelease];
            [alert setShowsSuppressionButton:YES];
            [alert setMessageText:NSLocalizedString(@"You have altered the system's umask", @"alert title")];
            [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"The normal umask is %@ and yours is set to %@. This more restrictive umask may cause permission problems with TeX Live.", @"alert text, two string format specifiers"), defaultMaskString, umaskString]];
            [alert runModal];
            if ([[alert suppressionButton] state] == NSOnState)
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:TLMDisableUmaskWarningKey];
        }
    }
}

+ (void)_logEnvironment;
{
    // Even though we now have a sane PATH, log the environment in case something is screwy.
    TLMTask *envTask = [[TLMTask  new] autorelease];
    [envTask setLaunchPath:@"/usr/bin/env"];
    [envTask launch];
    [envTask waitUntilExit];
    if ([envTask outputString]) {
        NSString *output = [[envTask outputString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSArray *lines = [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        lines = [lines sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
        TLMLog(__func__, @"Current environment from /usr/bin/env:\n%@", [lines componentsJoinedByString:@"\n"]);
    }
    else {
        TLMLog(__func__, @"*** ERROR *** No output from /usr/bin/env");
    }
}

- (NSURL *)defaultServerURL
{
    return [[NSURL URLWithString:[[NSUserDefaults standardUserDefaults] objectForKey:TLMFullServerURLPreferenceKey]] tlm_normalizedURL];
}

#define UPGRADE_TAG 'UPGR'

- (void)versionWarningDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    if ([alert showsSuppressionButton] && [[alert suppressionButton] state] == NSOnState)
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:TLMDisableVersionMismatchWarningKey];
    
    // point users to main MacTeX, as users get confused by the main TeX Live page
    if (UPGRADE_TAG == returnCode) {
        NSURL *aURL = [NSURL URLWithString:@"http://tug.org/mactex/"];
        [[NSWorkspace sharedWorkspace] openURL:aURL];
    }
    [self release];
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
    else if (TLMDatabaseUnknownYear == _installedYear) {
        [alert setMessageText:NSLocalizedString(@"Unable to determine your TeX Live version", @"alert title")];
        [alert setInformativeText:NSLocalizedString(@"Please quit and relaunch TeX Live Utility.  If this problem occurs again, please submit a bug report using the link on the Help menu.", @"alert message")];
        allowSuppression = NO;
    }
    else if (remoteVersion > _installedYear) {
        [alert setMessageText:NSLocalizedString(@"Repository URL has a newer TeX Live version", @"")];
#if DEBUG
#warning change wording if MacTeX installed
#endif
        [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Your TeX Live version is %lu, but your default repository URL appears to be for TeX Live %lu.  You need to manually upgrade to a newer version of TeX Live, as there will be no further updates for your version.", @"two integer specifiers"), _installedYear, remoteVersion]];
        // nag users into upgrading, to keep them from using ftp.tug.org willy-nilly
        allowSuppression = NO;
        [alert addButtonWithTitle:NSLocalizedString(@"Ignore", @"button title")];
        [alert addButtonWithTitle:NSLocalizedString(@"Upgrade", @"button title")];
        [[[alert buttons] lastObject] setTag:UPGRADE_TAG];
        [alert setShowsHelp:YES];
        // !!! Doesn't seem to work; error sez "Help Viewer cannot open this content."  Furrfu.
        [alert setHelpAnchor:@"installation"];
    }
    else {
        [alert setMessageText:NSLocalizedString(@"Repository URL has an older TeX Live version", @"")];
        [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Your TeX Live version is %lu, but your default repository URL appears to be for TeX Live %lu.  You need to choose an appropriate repository.", @"two integer specifiers"), _installedYear, remoteVersion]];
        // may come up during pretest
        allowSuppression = YES;
    }
    
    
    if (NO == allowSuppression || [[NSUserDefaults standardUserDefaults] boolForKey:TLMDisableVersionMismatchWarningKey] == NO) {
                
        if (allowSuppression)
            [alert setShowsSuppressionButton:YES];
        
        // always show on the main window
        // ended up messaging a zombie TLMEnvironment when I had an alert due to a bad /usr/texbin path
        [alert beginSheetModalForWindow:[(NSWindowController *)[(TLMAppController *)[NSApp delegate] mainWindowController] window]
                          modalDelegate:[self retain]
                         didEndSelector:@selector(versionWarningDidEnd:returnCode:contextInfo:) 
                            contextInfo:NULL];            
    }
}

- (BOOL)_getValidServerURL:(NSURL **)outURL repositoryYear:(TLMDatabaseYear *)outYear fromURL:(NSURL *)fromURL
{        
    NSParameterAssert(_installedYear != TLMDatabaseUnknownYear);
    NSParameterAssert(outURL);
    NSParameterAssert(outYear);
    
    /*
     Always recompute this, because if we're using the multiplexer, it's going to redirect to
     some other URL.  Eventually we'll get a few of them cached in the TLMDatabase, but this
     is a slowdown if you use mirror.ctan.org.
     */
    TLMDatabase *db = [TLMDatabase databaseForMirrorURL:fromURL];
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
            TLMLog(__func__, @"*** WARNING *** This repository is for TeX Live %lu, but you are using TeX Live %lu", (unsigned long)repositoryYear, (unsigned long)_installedYear);
    }
    else if (repositoryYear != _installedYear) {
        
        // this fallback is only for official repos
        NSParameterAssert([db isOfficial]);
                
        if ([self legacyRepositoryURL] == nil) {
            NSString *plistPath = [[NSBundle mainBundle] pathForResource:@"DefaultMirrors" ofType:@"plist"];
            NSDictionary *mirrorsByYear = nil;
            if (plistPath)
                mirrorsByYear = [[NSDictionary dictionaryWithContentsOfFile:plistPath] objectForKey:@"LegacyMirrors"];
            NSString *location = [mirrorsByYear objectForKey:[[NSNumber numberWithInteger:_installedYear] stringValue]];
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
        
        TLMLog(__func__, @"Repository version appears to be %lu; %@", (unsigned long)repositoryYear, ageString);
    }
        
    *outURL = validURL;
    *outYear = repositoryYear;
    return [db failed];
}

- (NSURL *)validServerURLFromURL:(NSURL *)fromURL
{
    // will be nil on failure; always initialized
    NSURL *validURL;
    TLMDatabaseYear repositoryYear;
    
    // use the mirror from prefs if we're not checking a specific one for redirects
    if (nil == fromURL)
        fromURL = [self defaultServerURL];
    
    // false return value signifies TLMDatabase failure (usually a network problem)
    BOOL dbFailed = [self _getValidServerURL:&validURL repositoryYear:&repositoryYear fromURL:fromURL];

    /*
     This is a special case for the multiplexer, which can return a stale server; retry
     when have a nil URL but not due to a network issue.  This should mean that we were
     not able to find a legacy repository, so likely it's an old server.  This happens
     frequently around the time of a new TL release.
     
     I've also been seeing this periodically with a URL returned by the multiplexer,
     where the destination is down.  In that case, we also want to retry.  In fact, the
     only case where we don't want to retry is when the network is down or the multiplexer
     itself is down.
     */
    if (nil == validURL && [fromURL isMultiplexer]) {
        int tryCount = 2;
        const int maxTries = 5;
        while (nil == validURL && tryCount <= maxTries) {
            if (dbFailed) {
                TLMLog(__func__, @"Failed to load database; requesting another repository from the multiplexer (attempt %d of %d).", tryCount, maxTries);
            }
            else {
                TLMLog(__func__, @"Stale repository returned from multiplexer.  Requesting another repository (attempt %d of %d).", tryCount, maxTries);
            }

            dbFailed = [self _getValidServerURL:&validURL repositoryYear:&repositoryYear fromURL:fromURL];
            tryCount++;
        }
    }
    
    // Moved this check out of _getValidServer:repositoryYear: to avoid issues in the loop above
    if ((nil == validURL || repositoryYear != _installedYear) && NO == dbFailed) {
        [self performSelectorOnMainThread:@selector(_displayFallbackServerAlertForRepositoryYear:) 
                               withObject:[NSNumber numberWithInteger:repositoryYear] 
                            waitUntilDone:NO];
    }
    
    return validURL;
}

- (NSURL *)backupDirectory
{
    NSString *backupDir = [TLMOptionOperation stringValueOfOption:@"backupdir"];
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
        TLMLog(__func__, @"Recursive check of installation privileges. This will happen once per launch, and may be slow if %@ is on a network filesystem%C", path, TLM_ELLIPSIS);
        TLMLogServerSync();
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        
        NSDirectoryEnumerator *dirEnum = [fm enumeratorAtPath:path];
        for (NSString *subpath in dirEnum) {
            
            // okay if this doesn't get released on the break; it'll be caught by the top-level pool
            NSAutoreleasePool *innerPool = [NSAutoreleasePool new];
            subpath = [path stringByAppendingPathComponent:subpath];
            if ([fm fileExistsAtPath:subpath]) {
                if ([fm isWritableFileAtPath:subpath] == NO) {
                    TLMLog(__func__, @"*** WARNING *** mixed permissions found.  Install directory %@ is writeable by this user, but child directory %@ is not writeable.", path, subpath);
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

- (NSString *)updmapAbsolutePath
{
    NSString *texbinPath = [[NSUserDefaults standardUserDefaults] objectForKey:TLMTexBinPathPreferenceKey];
    return [[texbinPath stringByAppendingPathComponent:UPDMAP_CMD] stringByStandardizingPath];
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

- (NSString *)gpgAbsolutePath
{
    NSString *texbinPath = [[NSUserDefaults standardUserDefaults] objectForKey:TLMTexBinPathPreferenceKey];
    return [[texbinPath stringByAppendingPathComponent:GPG_CMD] stringByStandardizingPath];
}

#pragma mark Default URL

+ (NSURL *)_currentTeXLiveLocationOption
{
    NSString *location = [TLMOptionOperation stringValueOfOption:@"location"];
    // remove trailing slashes before comparison, although this is a directory
    while ([location hasSuffix:@"/"])
        location = [location substringToIndex:([location length] - 1)];
    return location ? [NSURL URLWithString:location] : nil;
}

+ (void)_handleLocationOperationFinished:(NSNotification *)aNote
{
    TLMOptionOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    
    NSString *location = [[self _currentTeXLiveLocationOption] absoluteString];
    if (nil == location)
        location = NSLocalizedString(@"Error reading location from TeX Live", @"");
    
    if ([op failed] || [op isCancelled]) {
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"The location in the TeX Live database was not changed", @"")];
        [alert setInformativeText:[NSString stringWithFormat:@"%@ %@", NSLocalizedString(@"The current location is:", @""), location]];
        (void) [alert runModal];
    }
    else {
        TLMLog(__func__, @"Finished setting command line server location:\n\tlocation = %@", location);
    }
}   

+ (void)_syncCommandLineServerOption
{
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
        [[TLMReadWriteOperationQueue defaultQueue] addOperation:op];
        [op release];
    }
}

+ (void)setDefaultRepository:(NSURL *)absoluteURL
{
    [[NSUserDefaults standardUserDefaults] setObject:[absoluteURL absoluteString] forKey:TLMFullServerURLPreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:TLMDefaultRepositoryChangedNotification object:self];
    
    NSAlert *alert = [[NSAlert new] autorelease];
    [alert setMessageText:NSLocalizedString(@"Change command-line default?", @"alert title")];
    [alert setInformativeText:NSLocalizedString(@"Would you like to use this as the default value for the command-line tlmgr tool as well?", @"alert text")];
    [alert addButtonWithTitle:NSLocalizedString(@"Yes", @"button title")];
    [alert addButtonWithTitle:NSLocalizedString(@"No", @"button title")];
    switch([alert runModal]) {
        case NSAlertFirstButtonReturn:
            [self _syncCommandLineServerOption];
            break;
        default:
            break;
    }
}

@end
