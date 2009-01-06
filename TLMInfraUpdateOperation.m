//
//  TLMInfraUpdateOperation.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/16/08.
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

#import "TLMInfraUpdateOperation.h"
#import "TLMLogServer.h"
#import "TLMPreferenceController.h"

#import <sys/stat.h>

@implementation TLMInfraUpdateOperation

static NSString *__TLMGetTemporaryDirectory()
{
    NSString *tempDir = NSTemporaryDirectory();
    if (nil == tempDir)
        tempDir = @"/tmp";
    
    const char *tmpPath = [[tempDir stringByAppendingPathComponent:@"TLMInfraUpdateOperation.XXXXXX"] fileSystemRepresentation];
    
    // mkstemp needs a writable string
    char *tempName = strdup(tmpPath);
    
    // use mkdtemp to avoid race conditions
    tempName = mkdtemp(tempName);
    assert(tempName);
    
    // create a subdirectory that we can remove entirely
    NSString *updateDirectory = (NSString *)CFStringCreateWithFileSystemRepresentation(CFAllocatorGetDefault(), tempName);
    free(tempName);
    
    return [updateDirectory autorelease];
}

- (id)initWithLocation:(NSURL *)location;
{
    NSParameterAssert(location);

    NSString *updateDirectory = __TLMGetTemporaryDirectory();
    NSParameterAssert(updateDirectory);
    
    NSString *scriptPath = [[NSUserDefaults standardUserDefaults] objectForKey:TLMInfraPathPreferenceKey];
    scriptPath = [updateDirectory stringByAppendingPathComponent:scriptPath];
    
    // note that --nox11 is required to avoid spawning an xterm on some systems
    self = [self initWithCommand:scriptPath options:[NSArray arrayWithObject:@"--nox11"]];
    if (self) {        
        _location = [location copy];
        _scriptPath = [scriptPath copy];        
        _updateDirectory = [updateDirectory copy];
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

- (NSURLRequest *)download:(NSURLDownload *)download willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response;
{
    /*
     !!! Why is http://ctan.binkerton.com/systems/texlive/tlnet/2008/update-tlmgr-latest.sh redirecting to this stupid window that displays the script in a frame?
     http://ctan.binkerton.com/ctan.readme.php?filename=systems/texlive/tlnet/2008/update-tlmgr-latest.sh
     
     The Purdue mirror also redirects, but it allows downloading the script...so canceling here isn't correct.
     
    */
    long long len = [response expectedContentLength];
    TLMLog(__func__, @"Download redirected to %@, expecting %lld bytes.", [request URL], len);
    return request;
}

- (void)download:(NSURLDownload *)download didReceiveResponse:(NSURLResponse *)response;
{
    _expectedLength = [response expectedContentLength];
    
    // running random crap as root is really not a good idea...
    if (NSURLResponseUnknownLength != _expectedLength && _expectedLength < 1024 * 1024) {
        TLMLog(__func__, @"Unexpected download size %lld bytes", _expectedLength);
        TLMLog(__func__, @"*** Cancelling download due to a potential security problem. ***\nDownload should be at least 1 megabyte, so this may be a defective mirror.\nTry another mirror and notify the developer.");
        _downloadComplete = NO;
        [download cancel];
        [self setFailed:YES];
    }
    else {
        TLMLog(__func__, @"Will download %lld bytes%C", _expectedLength, 0x2026);
    }
}

- (void)download:(NSURLDownload *)download didReceiveDataOfLength:(NSUInteger)length
{
    _receivedLength += length;
    if (NSURLResponseUnknownLength != _expectedLength) {
        if ((CGFloat)(_receivedLength - _lastLoggedLength) / _expectedLength >= 0.20) {
            CGFloat pct = (CGFloat)_receivedLength / _expectedLength * 100;
            _lastLoggedLength = _receivedLength;
            TLMLog(__func__, @"Received %.0f%% of %lld bytes%C", pct, _expectedLength, 0x2026);
        }
    }
}

- (void)download:(NSURLDownload *)download didFailWithError:(NSError *)error
{
    [self setFailed:YES];
    // should already be NO, but make sure...
    _downloadComplete = NO;
    TLMLog(__func__, @"Download failed: %@", error);
}

- (void)downloadDidFinish:(NSURLDownload *)download
{
    _downloadComplete = YES;
    TLMLog(__func__, @"Download of %lld bytes complete", _receivedLength);
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
    
    TLMLog(__func__, @"Downloading URL: %@", scriptURL);

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
    if (_downloadComplete) {
        
        const char *fs_path = [_scriptPath fileSystemRepresentation];
        if (chmod(fs_path, S_IRWXU | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH)) {
            const char *s = strerror(errno);
            TLMLog(__func__, @"Failed to set script permissions: %s", s);
            [self setFailed:YES];
        }
        else {
            
            // another check to make sure we don't end up running random crap as root
            
            // if we get here, we're guaranteed that the file exists, is readable, and has length > 1024 * 1024
            FILE *strm = fopen(fs_path, "r");
            size_t len;
            char *firstLine = fgetln(strm, &len);
            if (firstLine) firstLine[(len - 1)] = '\0';

            if (firstLine && strncmp(firstLine, "#!", 2) != 0) {
                TLMLog(__func__, @"*** ERROR *** Downloaded file does not start with #!");
                TLMLog(__func__, @"*** ERROR *** First line is: \"%s\"", firstLine);
                [self setFailed:YES];
            }      
            else if (firstLine) {
                TLMLog(__func__, @"First line of downloaded file is: \"%s\"%Cgood!", firstLine, 0x2026);
            }
            
            fclose(strm);
        }
    }    
    
    return _downloadComplete;
}

- (void)main
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    // don't run if the user cancelled during download or something failed
    if ([self _downloadUpdateScript] && NO == [self isCancelled] && NO == [self failed])
        [super main];
   
    NSFileManager *fm = [NSFileManager new];
    NSError *error;
    if ([fm removeItemAtPath:_updateDirectory error:&error])
        TLMLog(__func__, @"Removed temp directory \"%@\"", _updateDirectory);
    else
        TLMLog(__func__, @"Failed to remove temp directory \"%@\": %@", _updateDirectory, error);
    [fm release];
    
    [self finished];
    [pool release];
}

@end
