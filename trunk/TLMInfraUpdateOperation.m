//
//  TLMInfraUpdateOperation.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/16/08.
/*
 This software is Copyright (c) 2008
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
    [_download release];
    [_updateDirectory release];
    [_scriptPath release];
    [_location release];
    [super dealloc];
}

- (void)download:(NSURLDownload *)download didReceiveResponse:(NSURLResponse *)response;
{
    _expectedLength = [response expectedContentLength];
}

- (void)download:(NSURLDownload *)download didReceiveDataOfLength:(NSUInteger)length
{
    _receivedLength += length;
    if (NSURLResponseUnknownLength != _expectedLength) {
        
        if ((CGFloat)(_receivedLength - _lastLoggedLength) / _expectedLength >= 0.20) {
            CGFloat pct = (CGFloat)_receivedLength / _expectedLength * 100;
            _lastLoggedLength = _receivedLength;
            TLMLog(@"TLMInfraUpdateOperation", @"Received %.0f%% of %lld bytes...", pct, _expectedLength);
        }
    }
}

- (void)download:(NSURLDownload *)download didFailWithError:(NSError *)error
{
    [self setFailed:YES];
    // should already be NO, but make sure...
    _downloadComplete = NO;
    TLMLog(@"TLMInfraUpdateOperation", @"Download failed: %@", error);
}

- (void)downloadDidFinish:(NSURLDownload *)download
{
    _downloadComplete = YES;
    TLMLog(@"TLMInfraUpdateOperation", @"Download of %lld bytes complete", _receivedLength);
}

- (BOOL)_downloadUpdateScript
{
    NSURL *base = _location;
    NSString *path = [[NSUserDefaults standardUserDefaults] objectForKey:TLMInfraPathPreferenceKey];
    CFURLRef fullURL = CFURLCreateCopyAppendingPathComponent(CFGetAllocator(base), (CFURLRef)base, (CFStringRef)path, FALSE);
    NSURL *scriptURL = [(id)fullURL autorelease];
    
    NSURLRequest *request = [NSURLRequest requestWithURL:scriptURL cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60.0];
    
    NSParameterAssert(nil == _download);
    _download = [[NSURLDownload alloc] initWithRequest:request delegate:self];
    [_download setDestination:_scriptPath allowOverwrite:YES];
    
    TLMLog(@"TLMInfraUpdateOperation", @"Downloading URL: %@", scriptURL);

    bool keepGoing = true;

    // functionally the same as +[NSURLConnection sendSynchronousRequest:returningResponse:error:], but allows user cancellation
    do {
        
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, TRUE);
        
        // check user cancellation
        if ([self isCancelled]) {
            [_download cancel];
            keepGoing = false;
        }
        // download failure
        else if ([self failed]) {
            keepGoing = false;
        }
        else if (_downloadComplete) {
            keepGoing = false;
        }
        
    } while (keepGoing);

    // set rwxr-xr-x
    if (_downloadComplete && chmod([_scriptPath fileSystemRepresentation], S_IRWXU | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH)) {
        const char *s = strerror(errno);
        TLMLog(@"TLMInfraUpdateOperation", @"Failed to set script permissions: %s", s);
    }
    
    return _downloadComplete;
}

- (void)main
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    // don't run if the user cancelled during download
    if ([self _downloadUpdateScript] && NO == [self isCancelled])
        [super main];
   
    NSFileManager *fm = [NSFileManager new];
    NSError *error;
    if ([fm removeItemAtPath:_updateDirectory error:&error])
        TLMLog(@"TLMInfraUpdateOperation", @"Removed temp directory \"%@\"", _updateDirectory);
    else
        TLMLog(@"TLMInfraUpdateOperation", @"Failed to remove temp directory \"%@\": %@", _updateDirectory, error);
    [fm release];
    
    [pool release];
}

@end
