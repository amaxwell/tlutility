//
//  TLMDatabase.m
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 09/13/10.
/*
 This software is Copyright (c) 2010-2012
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
#import "TLMTask.h"
#import "TLMLogServer.h"
#import "TLMDatabasePackage.h"
#import "TLMPackageNode.h"
#import "TLMEnvironment.h"
#import <WebKit/WebKit.h>
#import "TLMSizeFormatter.h"

#define MIN_DATA_LENGTH 2048
#define URL_TIMEOUT     30

const TLMDatabaseYear TLMDatabaseUnknownYear = -1;
NSString * const TLMDatabaseVersionCheckComplete = @"TLMDatabaseVersionCheckComplete";

@interface TLMDatabase ()
@property (readwrite, retain) NSMutableData *tlpdbData;
- (void)_fullDownload;
@end

@implementation TLMDatabase

@synthesize packages = _packages;
@synthesize loadDate = _loadDate;
@synthesize mirrorURL = _mirrorURL;

@synthesize failed = _failed;
@synthesize isOfficial = _isOfficial;
@synthesize tlpdbData = _tlpdbData;

static NSMutableSet *_databases = nil;
static NSLock       *_databasesLock = nil;
static double        _dataTimeout = URL_TIMEOUT;
static NSString     *_userAgent = nil;

+ (void)initialize
{
    if (nil == _databases) {
        _databases = [NSMutableSet new];
        _databasesLock = [NSLock new];
        
        // some servers may have a quick URL response, but be terribly slow to return data (indian.cse.msu.edu)
        NSNumber *dataTimeout = [[NSUserDefaults standardUserDefaults] objectForKey:@"TLMDatabaseDownloadTimeout"];
        if (dataTimeout && round([dataTimeout doubleValue]) > 0) {
            _dataTimeout = round([dataTimeout doubleValue]);
            TLMLog(__func__, @"Using custom database download timeout of %.0f seconds", _dataTimeout);
        }
        
        // get a user-agent for the default URL, to avoid hardcoding any framework versions
        WebView *wv = [[WebView alloc] initWithFrame:NSMakeRect(0, 0, 1, 1)];
        _userAgent = [[wv userAgentForURL:[[TLMEnvironment currentEnvironment] defaultServerURL]] copy];
        [wv release];
    }
}

+ (TLMDatabasePackage *)_packageNamed:(NSString *)name inDatabase:(TLMDatabase *)db
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"name == %@", name];
    return [[[db packages] filteredArrayUsingPredicate:predicate] lastObject];
}

+ (NSArray *)packagesByAddingVersionsFromMirror:(NSURL *)aURL toPackages:(NSArray *)packages;
{
    NSParameterAssert(aURL);
    NSParameterAssert(packages);
    
    TLMDatabase *mirror = [self databaseForMirrorURL:aURL];
    [mirror _fullDownload];
    
    // was asserting this, but that's not going to work well with offline mode
    if ([[mirror packages] count] == 0)
        TLMLog(__func__, @"No packages loaded for repository %@", mirror);
    
    TLMDatabase *local = [self localDatabase];
    if ([[local packages] count] == 0)
        TLMLog(__func__, @"*** ERROR *** No packages in local database");
    
    TLMLog(__func__, @"%ld packages in repository database, %ld packages in local database", (unsigned long)[[mirror packages] count], (unsigned long)[[local packages] count]);
    
    NSMutableArray *newPackages = [NSMutableArray arrayWithCapacity:[packages count]];
    
    for (TLMPackage *pkg in packages) {
        
        TLMPackage *newPkg = [pkg copy];
        TLMDatabasePackage *localPkg = [self _packageNamed:[pkg name] inDatabase:local];
        TLMDatabasePackage *remotePkg = [self _packageNamed:[pkg name] inDatabase:mirror];
        [newPkg setLocalCatalogueVersion:[localPkg catalogueVersion]];
        [newPkg setRemoteCatalogueVersion:[remotePkg catalogueVersion]];
        [newPackages addObject:newPkg];
        [newPkg release];
    }
    
    return newPackages;
}

+ (NSArray *)packageNodesByMergingLocalWithMirror:(NSURL *)aURL;
{
    TLMDatabase *mirror = [self databaseForMirrorURL:aURL];
    
    // was asserting this, but that's not going to work well with offline mode
    if ([[mirror packages] count] == 0)
        TLMLog(__func__, @"No packages loaded for repository %@", mirror);
    
    TLMDatabase *local = [self localDatabase];
    if ([[local packages] count] == 0)
        TLMLog(__func__, @"*** ERROR *** No packages in local database");
    
    TLMLog(__func__, @"%ld packages in repository database, %ld packages in local database", (unsigned long)[[mirror packages] count], (unsigned long)[[local packages] count]);
    
    NSSet *localPackageSet = [NSSet setWithArray:[local packages]];
    
    /*
     Treat the mirror as canonical, but add in any local packages we have that are removed
     or do not exist on this mirror.  May need to revisit with unofficial mirror support.
     */
    NSMutableSet *allPackages = [NSMutableSet setWithArray:[mirror packages]];
    [allPackages unionSet:localPackageSet];
    
    NSMutableArray *packageNodes = [NSMutableArray arrayWithCapacity:[allPackages count]];
    NSMutableArray *orphanedNodes = [NSMutableArray array];
    
    // need to sort since we may have merged remote/local packages here
    NSMutableArray *packagesToEnumerate = [NSMutableArray arrayWithArray:[allPackages allObjects]];
    NSSortDescriptor *sort = [[[NSSortDescriptor alloc] initWithKey:@"name" 
                                                          ascending:YES 
                                                           selector:@selector(localizedCaseInsensitiveNumericCompare:)] autorelease];
    [packagesToEnumerate sortUsingDescriptors:[NSArray arrayWithObject:sort]];
    
    // these should be new packages or of the wrong binary architecture
    for (TLMDatabasePackage *pkg in packagesToEnumerate) {
        NSString *name = [pkg name];
        TLMPackageNode *node = [TLMPackageNode new];
        
        // needed for backward compatibility
        [node setFullName:name];
        
        // needed for backward compatibility
        [node setShortDescription:[pkg shortDescription]];
        
        if ([localPackageSet containsObject:pkg])
            [node setInstalled:YES];
        
        NSRange r = [name rangeOfString:@"."];
        
        if (r.length) {
            [node setName:[name substringFromIndex:NSMaxRange(r)]];
            [node setHasParent:YES];
            [node setPackage:pkg];
            TLMPackageNode *last = [packageNodes lastObject];
            if (last && [[node fullName] hasPrefix:[last fullName]]) {
                [last addChild:node];
            }
            else {
                [orphanedNodes addObject:node];
            }
            [node release];
        }
        else {
            [node setName:name];
            [node setPackage:pkg];
            [packageNodes addObject:node];
            [node release];
        }
    }
    
    // deal with orphaned nodes that weren't ordered optimally
    for (TLMPackageNode *node in orphanedNodes) {
        
        TLMPackageNode *parent = nil;
        
        // linear search through all nodes; could sort and use binary search
        for (parent in packageNodes) {
            
            if ([[node fullName] hasPrefix:[parent fullName]]) {
                [parent addChild:node];
                break;
            }
        }
        
        if (nil == parent) {
            // change to full name, add to the flattened list, and log
            [node setName:[node fullName]];
            [packageNodes addObject:node];
            // ignore the special TL nodes and the win32 junk
            if ([[node fullName] hasPrefix:@"00texlive"] == NO && [[node fullName] hasSuffix:@".win32"] == NO)
                TLMLog(__func__, @"Package \"%@\" has no parent", [node fullName]);                        
        }
    }
    
    return packageNodes;
}

+ (TLMDatabase *)localDatabase;
{
    return [self databaseForMirrorURL:[NSURL fileURLWithPath:[[TLMEnvironment currentEnvironment] installDirectory]]];
}

+ (TLMDatabase *)databaseForMirrorURL:(NSURL *)aURL;
{
    NSParameterAssert(aURL);
    
    TLMDatabase *db;
    [_databasesLock lock];
    
    for (db in _databases) {
        // !!! early return
        if ([[db mirrorURL] isEqual:aURL]) {
            [_databasesLock unlock];
            return db;
        }
    }
    db = [TLMDatabase new];
    /*
     Key may be mirror.ctan.org initially if version is being requested, but will get reset
     if downloading the db directly to check version or when loaded from disk.
     */
    [db setMirrorURL:aURL];
    [_databases addObject:db];
    [db release];
    [_databasesLock unlock];
    
    return db;
}

#pragma mark Instance methods

- (id)init
{
    self = [super init];
    if (self) {
        _year = TLMDatabaseUnknownYear;
        _downloadLock = [NSLock new];
        _isOfficial = YES;
    }
    return self;
}

- (void)dealloc
{
    [_packages release];
    [_loadDate release];
    [_mirrorURL release];
    [_tlpdbData release];
    [_downloadLock release];
    [super dealloc];
}

- (void)reloadDatabaseFromPath:(NSString *)absolutePath
{    
    NSArray *packageDictionaries = [[NSDictionary dictionaryWithContentsOfFile:absolutePath] objectForKey:@"packages"];
    NSMutableArray *packages = [NSMutableArray arrayWithCapacity:[packageDictionaries count]];
    for (NSDictionary *pkgDict in packageDictionaries) {
        TLMDatabasePackage *pkg = [[TLMDatabasePackage alloc] initWithDictionary:pkgDict];
        [packages addObject:pkg];
        [pkg release];
    }
    if (packages) {
        [self setPackages:packages];
        [self setLoadDate:[NSDate date]];
    }
}

- (TLMDatabasePackage *)packageNamed:(NSString *)name
{
    for (TLMDatabasePackage *pkg in [self packages]) {
        if ([[pkg name] isEqualToString:name])
            return pkg;
    }
    return nil;
}

#pragma mark Download for version check

- (NSURL *)_tlpdbURL
{
    return [[NSURL databaseURLForTLNetURL:[self mirrorURL]] tlm_normalizedURL];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    NSAssert1([_downloadLock tryLock] == NO, @"acquire lock before calling %s", __func__);
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *httpResponse = (id)response;
        const NSInteger statusCode = [httpResponse statusCode];
        if (statusCode != 200) {
            TLMLog(__func__, @"received status code %lu (%@)", (long)statusCode, [NSHTTPURLResponse localizedStringForStatusCode:statusCode]);
            TLMLog(__func__, @"%@: %@", httpResponse, [httpResponse allHeaderFields]);
        }
    }
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    NSAssert1([_downloadLock tryLock] == NO, @"acquire lock before calling %s", __func__);
    _failed = YES;
    _failureTime = CFAbsoluteTimeGetCurrent();
    TLMLog(__func__, @"Failed to download tlpdb for version check %@ : %@", (_mirrorURL ? _mirrorURL : [self _tlpdbURL]), error);
}

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response;
{
    NSAssert1([_downloadLock tryLock] == NO, @"acquire lock before calling %s", __func__);
    // response is nil if we are not processing a redirect
    if (response) {
        NSURL *actualURL = [[request URL] tlm_normalizedURL];
        TLMLog(__func__, @"redirected request to %@", [actualURL absoluteString]);
        TLMLogServerSync();
        // delete "tlpkg/texlive.tlpdb"
        actualURL = [[actualURL tlm_URLByDeletingLastPathComponent] tlm_URLByDeletingLastPathComponent];
        [self setMirrorURL:actualURL];
        NSParameterAssert(actualURL != nil);
    }
    return request;
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data;
{
    NSAssert1([_downloadLock tryLock] == NO, @"acquire lock before calling %s", __func__);
    [[self tlpdbData] appendData:data];
}

- (void)_downloadDatabaseHead
{
    NSParameterAssert(_mirrorURL);
    NSAssert1([_downloadLock tryLock] == NO, @"acquire lock before calling %s", __func__);
    
    // retry a download if _failed was previously set
    if ([[self tlpdbData] length] == 0) {
        
        [self setTlpdbData:[NSMutableData data]];
        
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[self _tlpdbURL]];
        [request setTimeoutInterval:URL_TIMEOUT];
        // useful for debugging when behind a caching proxy
#if 0
        [request addValue:@"no-cache" forHTTPHeaderField:@"Pragma"];
        [request addValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
#endif
        // for bug #73; that mirror was returning an http 400 with the default user agent set by CFNetwork
        [request addValue:_userAgent ? _userAgent : @"TeX Live Utility" forHTTPHeaderField:@"User-Agent"];

        
        _failed = NO;
        TLMLog(__func__, @"Checking the repository version.  Please be patient.");
        TLMLog(__func__, @"Downloading at least %d bytes of tlpdb for a version check%C", MIN_DATA_LENGTH, TLM_ELLIPSIS);
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
        const CFAbsoluteTime stopTime = CFAbsoluteTimeGetCurrent() + _dataTimeout;
        do {
            const SInt32 ret = CFRunLoopRunInMode((CFStringRef)rlmode, 0.3, TRUE);
            
            if (kCFRunLoopRunFinished == ret || kCFRunLoopRunStopped == ret)
                break;
            
            if (CFAbsoluteTimeGetCurrent() >= stopTime) {
                TLMLog(__func__, @"%@ took more than %.0f seconds to respond.  Cancelling request.", [self _tlpdbURL], _dataTimeout);
                break;
            }
            
            if (_failed)
                break;
            
        } while ([[self tlpdbData] length] < MIN_DATA_LENGTH);
        TLMLog(__func__, @"Downloaded %lu bytes of tlpdb for version check", (unsigned long)[[self tlpdbData] length]);
        // in case of exceeding stopTime
        if ([[self tlpdbData] length] < MIN_DATA_LENGTH) {
            _failed = YES;
            [self setTlpdbData:nil];
            _failureTime = CFAbsoluteTimeGetCurrent();
        }
        [connection cancel];
        [connection release];
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    TLMLog(__func__, @"Finished downloading database");
    _hasFullDownload = YES;
}

static NSString *__TLMTemporaryFile()
{
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    NSString *absolutePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[(id)CFUUIDCreateString(NULL, uuid) autorelease]];
    if (uuid) CFRelease(uuid);
    return absolutePath;
}

- (void)_fullDownload
{
    NSParameterAssert(_mirrorURL);
    [_downloadLock lock];
    
    // !!! early return here
    if (_hasFullDownload) {
        [_downloadLock unlock];
        return;
    }
        
    [self setTlpdbData:[NSMutableData data]];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[self _tlpdbURL]];
    [request setTimeoutInterval:URL_TIMEOUT];
    // useful for debugging when behind a caching proxy
#if 0
    [request addValue:@"no-cache" forHTTPHeaderField:@"Pragma"];
    [request addValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
#endif
    // for bug #73; that mirror was returning an http 400 with the default user agent set by CFNetwork
    [request addValue:_userAgent ? _userAgent : @"TeX Live Utility" forHTTPHeaderField:@"User-Agent"];
    
    
    _failed = NO;
    TLMLog(__func__, @"Downloading remote package database.");
    TLMLogServerSync();
    
    NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
    NSString *rlmode = @"__TLMDatabaseDownloadRunLoopMode";
    [connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:rlmode];
    [connection start];
    const CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
#define FULL_DOWNLOAD_TIMEOUT 60.0
    const CFAbsoluteTime stopTime = startTime + FULL_DOWNLOAD_TIMEOUT;
    do {
        const SInt32 ret = CFRunLoopRunInMode((CFStringRef)rlmode, 0.3, TRUE);
        
        if (kCFRunLoopRunFinished == ret || kCFRunLoopRunStopped == ret)
            break;
        
        if (CFAbsoluteTimeGetCurrent() >= stopTime) {
            TLMLog(__func__, @"%@ took more than %.0f seconds to respond.  Cancelling request.", [self _tlpdbURL], FULL_DOWNLOAD_TIMEOUT);
            break;
        }
        
        if (_failed)
            break;
        
    } while (NO == _hasFullDownload);
    
    NSString *dataSizeString = [[[TLMSizeFormatter new] autorelease] stringForObjectValue:[NSNumber numberWithUnsignedLong:[[self tlpdbData] length]]];
    TLMLog(__func__, @"Downloaded %@ tlpdb for package version display in %.1f seconds.", dataSizeString, CFAbsoluteTimeGetCurrent() - startTime);
    // in case of exceeding stopTime
    if (_hasFullDownload) {
        NSString *tlpdbPath = __TLMTemporaryFile();
        [[self tlpdbData] writeToFile:tlpdbPath atomically:NO];
        
        NSString *plistPath = __TLMTemporaryFile();
        NSString *parserPath = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"parse_tlpdb.py"];
        
        TLMTask *parseTask = [[TLMTask new] autorelease];
        [parseTask setLaunchPath:@"/usr/bin/python"];
        [parseTask setArguments:[NSArray arrayWithObjects:@"-E", parserPath, @"-o", plistPath, @"-f", @"plist", tlpdbPath, nil]];
        [parseTask launch];
        [parseTask waitUntilExit];
        
        if ([parseTask terminationStatus] == EXIT_SUCCESS) {
            [self reloadDatabaseFromPath:plistPath];
        }
        else {
            TLMLog(__func__, @"Parsing the database from this repository failed with the following error: %@", [parseTask errorString]);
            _failed = YES;
            _failureTime = CFAbsoluteTimeGetCurrent();
        }
        
        unlink([plistPath saneFileSystemRepresentation]);
        unlink([tlpdbPath saneFileSystemRepresentation]);
        
        [self setTlpdbData:nil];
    }
    else {
        TLMLog(__func__, @"Failed to download remote package database. Package versions will not be displayed.");
    }
    [connection cancel];
    [connection release];
    [_downloadLock unlock];
}

- (BOOL)isOfficial
{
    // force download if needed
    [self texliveYear];
    return _isOfficial;
}

- (TLMDatabaseYear)texliveYear;
{
    [_downloadLock lock];

    // !!! early return if it's already computed
    if (TLMDatabaseUnknownYear != _year) {
        [_downloadLock unlock];
        return _year;
    }
    
    // check time of previous failure
    if ([self failed]) {
        const CFAbsoluteTime checkInterval = CFAbsoluteTimeGetCurrent() - _failureTime;
        /*
         We usually make 2-3 requests while doing a normal update/listing, and it's not likely the
         server is going to recover in such a short time.  Avoid retrying for a short time.
         */
        if (checkInterval < (URL_TIMEOUT * 3)) {
            // !!! early return: avoid multiple timeouts for successive requests
            TLMLog(__func__, @"Failed to use this repository %.1f seconds ago.  Using that result.", checkInterval);
            [_downloadLock unlock];
            return TLMDatabaseUnknownYear;
        }
        else {
            // log and try again
            TLMLog(__func__, @"Failed to use this repository %.1f seconds ago.  Trying again.", checkInterval);
        }
    }    
    
    if ([[self packages] count] == 0)
        [self _downloadDatabaseHead];

    if (NO == [self failed] && [[self tlpdbData] length] >= MIN_DATA_LENGTH) {
        
        NSString *tlpdbPath = __TLMTemporaryFile();
        [[self tlpdbData] writeToFile:tlpdbPath atomically:NO];
        
        NSString *plistPath = __TLMTemporaryFile();
        NSString *parserPath = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"parse_tlpdb.py"];
        
        TLMTask *parseTask = [[TLMTask new] autorelease];
        [parseTask setLaunchPath:@"/usr/bin/python"];
        [parseTask setArguments:[NSArray arrayWithObjects:@"-E", parserPath, @"-o", plistPath, @"-f", @"plist", tlpdbPath, nil]];
        [parseTask launch];
        [parseTask waitUntilExit];

        if ([parseTask terminationStatus] == EXIT_SUCCESS) {
            [self reloadDatabaseFromPath:plistPath];
        }
        else {
            TLMLog(__func__, @"Parsing the database from this repository failed with the following error: %@", [parseTask errorString]);
            _failed = YES;
            _failureTime = CFAbsoluteTimeGetCurrent();
        }
        
        unlink([plistPath saneFileSystemRepresentation]);
        unlink([tlpdbPath saneFileSystemRepresentation]);
        
        [self setTlpdbData:nil];

    }
    
    // !!! minrelease not currently used, but tlcontrib isn't using it (yet) either
    TLMDatabaseYear release = TLMDatabaseUnknownYear, minrelease = TLMDatabaseUnknownYear;
    
    for (NSString *depend in [[self packageNamed:@"00texlive.config"] depends]) {
        
        // release is the upper limit for which this database applies
        if ([depend hasPrefix:@"release/"]) {
            NSScanner *scanner = [NSScanner scannerWithString:depend];
            [scanner scanString:@"release/" intoString:NULL];
            if ([scanner scanInteger:&release] == NO)
                TLMLog(__func__, @"Unable to determine year from depend line: %@", depend);
            if ([scanner isAtEnd] == NO) {
                _isOfficial = NO;
                TLMLog(__func__, @"This looks like an unofficial repository");
            }
        }
        else if ([depend hasPrefix:@"minrelease/"]) {
            // minrelease is the lower limit for which this database applies
            NSScanner *scanner = [NSScanner scannerWithString:depend];
            [scanner scanString:@"minrelease/" intoString:NULL];
            if ([scanner scanInteger:&minrelease] == NO)
                TLMLog(__func__, @"Unable to determine year from depend line: %@", depend);
        }
    }
    
    if (TLMDatabaseUnknownYear == release) {
        TLMLog(__func__, @"Unable to determine year from 00texlive.config");
        _failed = YES;
        _failureTime = CFAbsoluteTimeGetCurrent();
    }
    
    _year = release;
    
    [_downloadLock unlock];
    
    // !!! temporary hack for mirror controller
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:3];
    [userInfo setObject:[self mirrorURL] forKey:@"URL"];
    // use ivar directly to avoid reentrancy
    [userInfo setObject:[NSNumber numberWithInteger:_year] forKey:@"year"];
    NSNotification *note = [NSNotification notificationWithName:TLMDatabaseVersionCheckComplete object:self userInfo:userInfo];
    [[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:note waitUntilDone:NO];
    
    return _year;
}

@end
