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
#import "TLMDatabasePackage.h"
#import "TLMPackageNode.h"
#import "TLMEnvironment.h"

#define TLPDB_PATH      CFSTR("tlpkg/texlive.tlpdb")
#define MIN_DATA_LENGTH 2048
#define URL_TIMEOUT     30

#define LOCAL_DB_KEY    @"local tlpdb"

const TLMDatabaseYear TLMDatabaseUnknownYear = -1;
NSString * const TLMDatabaseVersionCheckComplete = @"TLMDatabaseVersionCheckComplete";

@interface TLMDatabase ()
@property (readwrite, retain) NSMutableData *tlpdbData;
@property (readwrite, copy) NSURL *tlpdbURL;
@property (readwrite, copy) NSURL *actualDatabaseURL;
@end

@implementation TLMDatabase

@synthesize packages = _packages;
@synthesize loadDate = _loadDate;
@synthesize mirrorURL = _mirrorURL;

@synthesize failed = _failed;
@synthesize isOfficial = _isOfficial;
@synthesize tlpdbData = _tlpdbData;
@synthesize tlpdbURL = _tlpdbURL;
@synthesize actualDatabaseURL = _actualDatabaseURL;

static NSMutableDictionary *_databases = nil;

+ (void)initialize
{
    if (nil == _databases)
        _databases = [NSMutableDictionary new];
}

+ (TLMDatabase *)_databaseForKey:(id)aKey
{
    TLMDatabase *db = [_databases objectForKey:(aKey ? aKey : LOCAL_DB_KEY)];
    if (nil == db) {
        db = [TLMDatabase new];
        [db setMirrorURL:aKey];
        [_databases setObject:db forKey:(aKey ? aKey : LOCAL_DB_KEY)];
        [db release];
    }
    return db;
}

+ (NSArray *)packagesByMergingLocalWithMirror:(NSURL *)aURL;
{
    TLMDatabase *mirror = [self databaseForURL:aURL];
    
    // was asserting this, but that's not going to work well with offline mode
    if ([[mirror packages] count] == 0)
        TLMLog(__func__, @"No packages loaded for mirror %@", mirror);
    
    TLMDatabase *local = [self localDatabase];
    NSAssert([[local packages] count], @"No packages in local database");
    
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
    return [self _databaseForKey:nil];
}

+ (TLMDatabase *)databaseForURL:(NSURL *)aURL;
{
    return [self _databaseForKey:aURL];
}

// CFURL is pretty stupid about equality.  Among other things, it considers a double slash directory separator significant.
static NSURL *__TLMNormalizedURL(NSURL *aURL)
{
    if (nil == aURL) return nil;
    NSMutableString *str = [[aURL absoluteString] mutableCopy];
    NSRange startRange = [str rangeOfString:@"//"];
    NSUInteger start = NSMaxRange(startRange);
    if (startRange.length && [str replaceOccurrencesOfString:@"//" withString:@"/" options:NSLiteralSearch range:NSMakeRange(start, [str length] - start)])
        aURL = [NSURL URLWithString:str];
    [str release];
    return aURL;
}

+ (TLMDatabaseVersion)versionForMirrorURL:(NSURL *)aURL;
{
#warning get rid of this struct
    TLMDatabaseVersion version =  { TLMDatabaseUnknownYear, false, [[aURL retain] autorelease] };
#warning locking
    @synchronized(_databases) {
        
        if (nil == aURL)
            aURL = [[TLMEnvironment currentEnvironment] defaultServerURL];
        
        NSParameterAssert(aURL != nil);
        CFAllocatorRef alloc = CFGetAllocator((CFURLRef)aURL);
        
        // cache under the full tlpdb URL
        NSURL *tlpdbURL = [(id)CFURLCreateCopyAppendingPathComponent(alloc, (CFURLRef)aURL, TLPDB_PATH, FALSE) autorelease];
        tlpdbURL = __TLMNormalizedURL(tlpdbURL);
        TLMDatabase *db = [_databases objectForKey:tlpdbURL];
        if (nil == db) {
            db = [[TLMDatabase alloc] init];
            [db setTlpdbURL:tlpdbURL];
            [db setMirrorURL:aURL];
            [_databases setObject:db forKey:tlpdbURL];
            [db autorelease];
        }
        
        // force a download if necessary
        version.year = [db texliveYear];
        version.isOfficial = [db isOfficial];
        
        // now see if we redirected at some point...we don't want to return the tlpdb path
        NSURL *actualURL = __TLMNormalizedURL([db actualDatabaseURL]);
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
        if ([db actualDatabaseURL] && [[db actualDatabaseURL] isEqual:tlpdbURL] == NO) {    
            /*
             This sucks.  Add a duplicate value for URLs that redirect, since the Utah
             pretest mirror is listed as http://www.math.utah.edu/pub/texlive/tlpretest/
             but ends up getting redirected to http://ftp.math.utah.edu:80/pub//texlive/tlpretest
             so I had to ask it for the tlpdb each time.  Need to see if this works with
             other hosts that redirect.
             
             The main thing to avoid is caching anything for the multiplexer, since there
             is no guarantee that the hosts it returns are consistent from one request to
             the next.
             */
            [_databases setObject:db forKey:[db actualDatabaseURL]];
            if ([[[tlpdbURL host] lowercaseString] isEqualToString:@"mirror.ctan.org"])
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

#pragma mark Instance methods

- (id)init
{
    self = [super init];
    if (self) {
        _year = TLMDatabaseUnknownYear;
        _isOfficial = YES;
    }
    return self;
}

- (void)dealloc
{
    [_packages release];
    [_loadDate release];
    [_mirrorURL release];
    [_tlpdbURL release];
    [_tlpdbData release];
    [_actualDatabaseURL release];
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

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    _failed = YES;
    TLMLog(__func__, @"Failed to download tlpdb for version check %@ : %@", (_actualDatabaseURL ? _actualDatabaseURL : _tlpdbURL), error);
}

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response;
{
    // response is nil if we are not processing a redirect
    if (response) {
        TLMLog(__func__, @"redirected request to %@", [__TLMNormalizedURL([request URL]) absoluteString]);
        TLMLogServerSync();
        [self setActualDatabaseURL:__TLMNormalizedURL([request URL])];
    }
    return request;
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data;
{
    [[self tlpdbData] appendData:data];
}

- (void)_downloadDatabaseHead
{
    NSParameterAssert(_tlpdbURL);
    
    // retry a download if _failed was previously set
    if ([[self tlpdbData] length] == 0) {
        
        [self setTlpdbData:[NSMutableData data]];
        
        NSURLRequest *request = [NSURLRequest requestWithURL:_tlpdbURL cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:URL_TIMEOUT];
        _failed = NO;
        TLMLog(__func__, @"Checking the repository version.  Please be patient.");
        TLMLog(__func__, @"Downloading at least %d bytes of tlpdb for a version check%C", MIN_DATA_LENGTH, 0x2026);
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
            
        } while ([[self tlpdbData] length] < MIN_DATA_LENGTH);
        TLMLog(__func__, @"Downloaded %lu bytes of tlpdb for version check", (unsigned long)[[self tlpdbData] length]);
        [connection cancel];
        [connection release];
    }
}

static NSString *__TLMTemporaryFile()
{
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    NSString *absolutePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[(id)CFUUIDCreateString(NULL, uuid) autorelease]];
    if (uuid) CFRelease(uuid);
    return absolutePath;
}

- (TLMDatabaseYear)texliveYear;
{
    // !!! early return if it's already copmuted
    if (TLMDatabaseUnknownYear != _year)
        return _year;

    if ([[self packages] count] == 0)
        [self _downloadDatabaseHead];

    if (NO == [self failed] && [[self tlpdbData] length] >= MIN_DATA_LENGTH) {
        
        NSString *tlpdbPath = __TLMTemporaryFile();
        [[self tlpdbData] writeToFile:tlpdbPath atomically:NO];
        
        NSString *plistPath = __TLMTemporaryFile();
        
        BDSKTask *parseTask = [[BDSKTask new] autorelease];
        [parseTask setLaunchPath:[[NSBundle mainBundle] pathForAuxiliaryExecutable:@"parse_tlpdb.py"]];
        [parseTask setArguments:[NSArray arrayWithObjects:@"-o", plistPath, @"-f", @"plist", tlpdbPath, nil]];
        [parseTask launch];
        [parseTask waitUntilExit];

        if ([parseTask terminationStatus] == EXIT_SUCCESS)
            [self reloadDatabaseFromPath:plistPath];
        
        unlink([plistPath saneFileSystemRepresentation]);
        unlink([tlpdbPath saneFileSystemRepresentation]);
        
        [self setTlpdbData:nil];

    }
    
    for (NSString *depend in [[self packageNamed:@"00texlive.config"] depends]) {
        
        if ([depend hasPrefix:@"release/"]) {
            NSScanner *scanner = [NSScanner scannerWithString:depend];
            if ([scanner scanString:@"release/" intoString:NULL] == NO)
                TLMLog(__func__, @"Unexpected syntax for depend line: %@", depend);
            if ([scanner scanInt:&_year] == NO)
                TLMLog(__func__, @"Unable to determine year from depend line: %@", depend);
            if ([scanner isAtEnd] == NO) {
                _isOfficial = NO;
                TLMLog(__func__, @"This looks like an unofficial repository");
            }
            break;
        }
    }    
    return _year;
}

@end
