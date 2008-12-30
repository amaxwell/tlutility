//
//  TLMInfraUpdateOperation.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/16/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "TLMInfraUpdateOperation.h"
#import "TLMLogServer.h"
#import "TLMPreferenceController.h"

#import <sys/types.h>
#import <sys/stat.h>

@implementation TLMInfraUpdateOperation


- (id)initWithLocation:(NSURL *)location;
{
    self = [super initWithPackageNames:nil location:location];
    if (self) {
        
        NSString *tempDir = NSTemporaryDirectory();
        if (nil == tempDir)
            tempDir = @"/tmp";
        
        const char *tmpPath;
        tmpPath = [[tempDir stringByAppendingPathComponent:@"TLMInfraUpdateOperation.XXXXXX"] fileSystemRepresentation];
        
        // mkstemp needs a writable string
        char *tempName = strdup(tmpPath);
        
        // use mkdtemp to avoid race conditions
        tempName = mkdtemp(tempName);
        if (NULL == tempName) {
            TLMLog(@"TLMInfraUpdateOperation", @"Failed to create temp directory %s", tempName);
            [self release];
            return nil;
        }
        
        // create a subdirectory that we can remove entirely
        _updateDirectory = (NSString *)CFStringCreateWithFileSystemRepresentation(CFAllocatorGetDefault(), tempName);
        free(tempName);
        
        _location = [location copy];
        NSString *scriptPath = [[NSUserDefaults standardUserDefaults] objectForKey:TLMInfraPathPreferenceKey];
        _scriptPath = [[_updateDirectory stringByAppendingPathComponent:scriptPath] copy];
        NSString *useRoot = ([[NSUserDefaults standardUserDefaults] boolForKey:TLMUseRootHomePreferenceKey]) ? @"y" : @"n";
        // note that --nox11 is required to avoid spawning an xterm on some systems
        NSMutableArray *options = [NSMutableArray arrayWithObjects:useRoot, _scriptPath, @"--nox11", nil];
        [self setOptions:options];
    }
    return self;
}

- (void)dealloc
{
    [_updateDirectory release];
    [_scriptPath release];
    [_location release];
    [super dealloc];
}

- (BOOL)_downloadUpdateScript
{
    NSURL *base = _location;
    NSString *path = [[NSUserDefaults standardUserDefaults] objectForKey:TLMInfraPathPreferenceKey];
    CFURLRef fullURL = CFURLCreateCopyAppendingPathComponent(CFGetAllocator(base), (CFURLRef)base, (CFStringRef)path, FALSE);
    NSURL *scriptURL = [(id)fullURL autorelease];
    
    NSURLResponse *response;
    NSURLRequest *request = [NSURLRequest requestWithURL:scriptURL];
    NSError *error;
    TLMLog(@"TLMInfraUpdateOperation", @"Downloading URL: %@", scriptURL);
    NSData *scriptData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    BOOL success = NO;
    if (nil != scriptData) {
        TLMLog(@"TLMInfraUpdateOperation", @"Downloaded %lu bytes", (unsigned long)[scriptData length]);
        if (NO == [scriptData writeToFile:_scriptPath options:0 error:&error])
            TLMLog(@"TLMInfraUpdateOperation", @"%@", error);
        else
            success = YES;
    }
    else {
        TLMLog(@"TLMInfraUpdateOperation", @"%@", error);
    }
    
    // set rwxr-xr-x
    if (chmod([_scriptPath fileSystemRepresentation], S_IRWXU | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH))
        TLMLog(@"TLMInfraUpdateOperation", @"Failed to set script permissions: %s", strerror(errno));
    
    return success;
}

- (void)main
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    if ([self _downloadUpdateScript])
        [super main];
   
    NSFileManager *fm = [NSFileManager new];
    if (NO == [fm removeItemAtPath:_updateDirectory error:NULL])
        TLMLog(@"TLMInfraUpdateOperation", @"Failed to delete directory \"%@\"", _updateDirectory);
    [fm release];
    
    [pool release];
}

@end
