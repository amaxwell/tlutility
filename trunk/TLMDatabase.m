//
//  TLMDatabase.m
//  TeX Live Manager
//
//  Created by Adam R. Maxwell on 09/13/10.
/*
 This software is Copyright (c) 2010-2011
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

#import "TLMDatabase.h"
#import "BDSKTask.h"
#import <regex.h>
#import "TLMLogServer.h"
#import "TLMPreferenceController.h"
#import <Python/Python.h>
#import "TLMDatabasePackage.h"

#define TLPDB_PATH      CFSTR("tlpkg/texlive.tlpdb")
#define MIN_DATA_LENGTH 2048
#define URL_TIMEOUT     30

const TLMDatabaseYear TLMDatabaseUnknownYear = -1;

NSString * const TLMDatabaseVersionCheckComplete = @"TLMDatabaseVersionCheckComplete";

@interface _TLMDatabase : NSObject {
    NSURL           *_tlpdbURL;
    NSMutableData   *_tlpdbData;
    BOOL             _failed;
    NSURL           *_actualURL;
    TLMDatabaseYear  _version;
    BOOL             _isOfficial;
}

- (id)initWithURL:(NSURL *)tlpdbURL;
- (TLMDatabaseYear)versionNumber;
@property (nonatomic, copy) NSURL *actualURL;
@property (readonly) BOOL failed;
@property (readonly) BOOL isOfficial;

@end

@implementation TLMDatabase

@synthesize packages = _packages;
@synthesize mirrorURL = _mirrorURL;
@synthesize loadDate = _loadDate;

static NSMutableDictionary *_databases = nil;

+ (void)initialize
{
    if (nil == _databases) {
        _databases = [NSMutableDictionary new];
        Py_Initialize();
    }
    TLMDatabase *db = [TLMDatabase new];
    [db reloadDatabase];
}

- (void)reloadDatabase;
{    
    NSString *tlmgrPath = [[TLMPreferenceController sharedPreferenceController] tlmgrAbsolutePath];
    BDSKTask *localDumpTask = [[BDSKTask new] autorelease];
    [localDumpTask setLaunchPath:tlmgrPath];
    NSArray *arguments = nil;
    if ([self mirrorURL] != nil)
        arguments = [NSArray arrayWithObjects:@"--repository", [[self mirrorURL] absoluteString], @"dump-tlpdb", @"--remote", nil];
    else
        arguments = [NSArray arrayWithObjects:@"dump-tlpdb", @"--local", nil];
    [localDumpTask setArguments:arguments];

    NSString *tlpdbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tlpdb_test.tlpdb"];
    [[NSData data] writeToFile:tlpdbPath atomically:NO];
    [localDumpTask setStandardOutput:[NSFileHandle fileHandleForWritingAtPath:tlpdbPath]];
    [localDumpTask launch];
    [localDumpTask waitUntilExit];
        
    char *script_path = strdup([[[NSBundle mainBundle] pathForAuxiliaryExecutable:@"parse_tlpdb.py"] saneFileSystemRepresentation]);
    char *bundle_path = strdup([[[NSBundle mainBundle] bundlePath] saneFileSystemRepresentation]);
    char *py_argv[] = { script_path, bundle_path };
    PySys_SetArgv(sizeof(py_argv) / sizeof(char *), py_argv);
    PyRun_SimpleFileExFlags(fopen(script_path, "r"), script_path, true, NULL);
    free(script_path);
    free(bundle_path);
    
    Class Package = NSClassFromString(@"TLMPyDatabasePackage");
    NSArray *packages = [Package packagesFromDatabaseAtPath:tlpdbPath];
    
    fprintf(stderr, "%s\n", [[[packages objectAtIndex:0] description] saneFileSystemRepresentation]);
    fprintf(stderr, "%s\n", [[[packages lastObject] description] saneFileSystemRepresentation]);

//    for (TLMDatabasePackage *pkg in packages)
//        fprintf(stderr, "%s\n", [[pkg name] UTF8String]);

    unlink([tlpdbPath saneFileSystemRepresentation]);
    
    [self setPackages:packages];
    [self setLoadDate:[NSDate date]];
    
}

+ (TLMDatabase *)localDatabase
{
    return nil;
}

+ (TLMDatabase *)databaseForURL:(NSURL *)aURL;
{
    return [_databases objectForKey:aURL];
}

+ (void)addDatabase:(TLMDatabase *)db forURL:(NSURL *)aURL;
{
    NSParameterAssert(db);
    NSParameterAssert(aURL);
    [_databases setObject:db forKey:aURL];
}

- (void)dealloc
{
    [_packages release];
    [_loadDate release];
    [_mirrorURL release];
    [super dealloc];
}

+ (TLMDatabaseVersion)versionForMirrorURL:(NSURL *)aURL;
{
    TLMDatabaseVersion version =  { TLMDatabaseUnknownYear, false, [[aURL retain] autorelease] };
    @synchronized(_databases) {
        
        if (nil == aURL)
            aURL = [[TLMPreferenceController sharedPreferenceController] defaultServerURL];
        
        NSParameterAssert(aURL != nil);
        CFAllocatorRef alloc = CFGetAllocator((CFURLRef)aURL);
        
        // cache under the full tlpdb URL
        NSURL *tlpdbURL = [(id)CFURLCreateCopyAppendingPathComponent(alloc, (CFURLRef)aURL, TLPDB_PATH, FALSE) autorelease];        
        _TLMDatabase *db = [_databases objectForKey:tlpdbURL];
        if (nil == db) {
            db = [[_TLMDatabase alloc] initWithURL:tlpdbURL];
            [_databases setObject:db forKey:tlpdbURL];
            [db autorelease];
        }

        // force a download if necessary
        version.year = [db versionNumber];
        version.isOfficial = [db isOfficial];
        
        // now see if we redirected at some point...we don't want to return the tlpdb path
        NSURL *actualURL = [db actualURL];
        if (actualURL) {
            // delete "tlpkg/texlive.tlpdb"
            CFURLRef tmpURL = CFURLCreateCopyDeletingLastPathComponent(alloc, (CFURLRef)actualURL);
            if (tmpURL) {
                actualURL = [(id)CFURLCreateCopyDeletingLastPathComponent(alloc, tmpURL) autorelease];
                CFRelease(tmpURL);
            }
            version.usedURL = [[actualURL retain] autorelease];
            NSParameterAssert(actualURL != nil);
        }
        
        // if redirected (e.g., from mirror.ctan.org), actualURL is non-nil
        if ([db actualURL] && [[db actualURL] isEqual:tlpdbURL] == NO) {            
            [_databases setObject:db forKey:[db actualURL]];
            // don't cache by the original host
            [_databases removeObjectForKey:tlpdbURL];
        }
        
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:3];
        [userInfo setObject:version.usedURL forKey:@"URL"];
        [userInfo setObject:[NSNumber numberWithShort:version.year] forKey:@"year"];
        NSNotification *note = [NSNotification notificationWithName:TLMDatabaseVersionCheckComplete object:self userInfo:userInfo];
        [[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:note waitUntilDone:NO];
    }
    return version;
}

@end

@implementation _TLMDatabase

@synthesize actualURL = _actualURL;
@synthesize failed = _failed;
@synthesize isOfficial = _isOfficial;

- (id)initWithURL:(NSURL *)tlpdbURL;
{
    NSParameterAssert(tlpdbURL);
    self = [super init];
    if (self) {
        _tlpdbURL = [tlpdbURL copy];
        _tlpdbData = [NSMutableData new];
        _version = TLMDatabaseUnknownYear;
        _isOfficial = YES;
    }
    return self;
}

- (void)dealloc
{
    [_tlpdbURL release];
    [_tlpdbData release];
    [_actualURL release];
    [super dealloc];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    _failed = YES;
    TLMLog(__func__, @"Failed to download tlpdb %@ : %@", (_actualURL ? _actualURL : _tlpdbURL), error);
}

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response;
{
    // response is nil if we are not processing a redirect
    if (response) {
        TLMLog(__func__, @"redirected request to %@", [[request URL] absoluteString]);
        TLMLogServerSync();
        [self setActualURL:[request URL]];
    }
    return request;
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data;
{
    [_tlpdbData appendData:data];
}

- (void)_downloadDatabaseHead
{
    // retry a download if _failed was previously set
    if ([_tlpdbData length] == 0) {
        NSURLRequest *request = [NSURLRequest requestWithURL:_tlpdbURL cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:URL_TIMEOUT];
        _failed = NO;
        TLMLog(__func__, @"Checking the repository version.  Please be patient.");
        TLMLog(__func__, @"Downloading tlpdb%C", 0x2026);
        TLMLogServerSync();

        NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
        
        /*
         Private runloop mode so we beachball if needed (since this is synchronous and likely on the main thread).
         Typical download times under "normal" circumstances are < 1 second on a DSL connection, which is not
         too noticeable.  However, some .edu servers seem to time out for no apparent reason, and that's going
         to seem like a hang on startup.
         */
        NSString *rlmode = @"__TLMDatabaseDownloadRunLoopMode";
        [connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:rlmode];
        [connection start];
        const CFAbsoluteTime stopTime = CFAbsoluteTimeGetCurrent() + URL_TIMEOUT;
        do {
            const SInt32 ret = CFRunLoopRunInMode((CFStringRef)rlmode, 0.3, TRUE);
            
            if (kCFRunLoopRunFinished == ret || kCFRunLoopRunStopped == ret)
                break;
            
            if (CFAbsoluteTimeGetCurrent() >= stopTime)
                break;
            
            if (_failed)
                break;
            
        } while ([_tlpdbData length] < MIN_DATA_LENGTH);
        TLMLog(__func__, @"Downloaded %lu bytes", (unsigned long)[_tlpdbData length]);
        [connection cancel];
        [connection release];
    }
}

- (TLMDatabaseYear)versionNumber;
{
    // !!! early return if it's already copmuted
    if (TLMDatabaseUnknownYear != _version)
        return _version;
    
    [self _downloadDatabaseHead];

    if (NO == [self failed] && [_tlpdbData length] >= MIN_DATA_LENGTH) {
        /*
         name 00texlive.config
         category TLCore
         revision 15388
         shortdesc TeX Live network archive option settings
         longdesc This package contains configuration options for the TeX Live
         longdesc archive If container_split_{doc,src}_files occurs in the depend
         longdesc lines the {doc,src} files are split into separate containers
         longdesc (.tar.xz)  during container build time. Note that this has NO
         longdesc effect on the appearance within the texlive.tlpdb. It is only
         longdesc on container level. The container_format/XXXXX specifies the
         longdesc format, currently allowed is only "xz", which generates .tar.xz
         longdesc files. zip can be supported. release/NNNN specifies the release
         longdesc number as used in the installer.  These values are taken from
         longdesc TeXLive::TLConfig::TLPDBConfigs hash at tlpdb creation time.
         longdesc For information on the 00texlive prefix see
         longdesc 00texlive.installation(.tlpsrc)
         depend container_format/xz
         depend container_split_doc_files/1
         depend container_split_src_files/1
         depend release/2010
         depend revision/19668
         */
        char *tlpdb_str = [_tlpdbData mutableBytes];
        
        // NUL terminate the data, since it's arbitrary
        // FIXME: better to look for a newline and create NSString?
        if (tlpdb_str[[_tlpdbData length] - 1] != '\0')
            [_tlpdbData appendBytes:"\0" length:1];
        
        // !!! early return if there's no texlive.config package
        const char *head_str = "name 00texlive.config";
        if (strncmp(head_str, tlpdb_str, sizeof(head_str)) != 0) {
            TLMLog(__func__, @"No 00texlive.config package present in tlpdb");
            return _version;
        }
        
        regex_t regex;
        regmatch_t match[3];
        
        /*
         May be other characters after the 4 digit year, so ignore those; see e-mail from
         Norbert on 5 Oct 2010.  ConTeXt repo uses depend release/2010-tlcontrib.
         */
        int err = regcomp(&regex, "^depend release\\/([0-9]{4})(.*)$", REG_NEWLINE|REG_EXTENDED);
        if (err) {
            char err_msg[1024] = {'\0'};
            regerror(err, &regex, err_msg, sizeof(err_msg));
            TLMLog(__func__, @"Unable to compile regex: %s", err_msg);
        }
        else if (0 == (err = regexec(&regex, tlpdb_str, 3, match, 0))) {
            size_t matchLength = match[1].rm_eo - match[1].rm_so;
            char *year = NSZoneMalloc(NSDefaultMallocZone(), matchLength + 1);
            memset(year, '\0', matchLength + 1);
            memcpy(year, &tlpdb_str[match[1].rm_so], matchLength);
            _version = strtol(year, NULL, 0);
            NSZoneFree(NSDefaultMallocZone(), year);
            
            if ((match[2].rm_eo - match[2].rm_so) > 0)
                _isOfficial = NO;
            
        }
        else {
            char err_msg[1024] = {'\0'};
            regerror(err, &regex, err_msg, sizeof(err_msg));
            TLMLog(__func__, @"Unable to find year in tlpdb: %s", err_msg);
        }
        regfree(&regex);

    }
    return _version;
}

@end
