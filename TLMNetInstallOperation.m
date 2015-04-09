//
//  TLMNetInstallOperation.m
//  TeX Live Utility
//
//  Created by Adam Maxwell on 09/20/09.
/*
 This software is Copyright (c) 2009-2015
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

#import "TLMNetInstallOperation.h"
#import "TLMPreferenceController.h"
#import "TLMLogServer.h"
#import "TLMTask.h"

#import <sys/stat.h>

@implementation TLMNetInstallOperation

@synthesize updateURL = _location;

static NSString *__TLMGetTemporaryDirectory()
{
    NSString *tempDir = NSTemporaryDirectory();
    if (nil == tempDir)
        tempDir = @"/tmp";
    
    const char *tmpPath = [[tempDir stringByAppendingPathComponent:@"TLMNetInstallOperation.XXXXXX"] saneFileSystemRepresentation];
    
    // mkstemp needs a writable string
    char *tempName = strdup(tmpPath);
    
#ifndef __clang_analyzer__
    // use mkdtemp to avoid race conditions
    tempName = mkdtemp(tempName);
    assert(tempName);
#endif
    // create a subdirectory that we can remove entirely
    NSString *updateDirectory = (NSString *)CFStringCreateWithFileSystemRepresentation(CFAllocatorGetDefault(), tempName);
    free(tempName);
    
    return [updateDirectory autorelease];
}

- (id)initWithProfile:(NSString *)profile location:(NSURL *)location;
{
    NSParameterAssert(profile);
    NSParameterAssert(location);
    NSString *updateDirectory = __TLMGetTemporaryDirectory();
    NSParameterAssert(updateDirectory);
    
    NSString *scriptPath = @"install-tl";
    scriptPath = [updateDirectory stringByAppendingPathComponent:scriptPath];
    NSString *profilePath = @"tlm.profile";
    profilePath = [updateDirectory stringByAppendingPathComponent:profilePath];
    if ([profile writeToFile:profilePath atomically:NO encoding:NSUTF8StringEncoding error:NULL] == NO) {
        [super dealloc];
        return nil;
    }

    NSArray *options = [NSArray arrayWithObjects:@"-profile", profilePath, @"-repository", [location absoluteString], nil];
    self = [super initWithCommand:scriptPath options:options];
    if (self) {
        _location = [location copy];
        _updateDirectory = [updateDirectory copy];
        _scriptPath = [scriptPath copy];
        
        // download install-tl-unx.tar.gz and unpack, then run install-tl
    }
    return self;
}

- (void)dealloc
{
    [_scriptPath release];
    [_location release];
    [_updateDirectory release];
    [super dealloc];
}

- (NSURLRequest *)download:(NSURLDownload *)download willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response;
{
    long long len = [response expectedContentLength];
    TLMLog(__func__, @"Download redirected to %@, expecting %lld bytes.", [request URL], len);
    return request;
}

- (void)download:(NSURLDownload *)download didReceiveResponse:(NSURLResponse *)response;
{
    _expectedLength = [response expectedContentLength];    
    if (NSURLResponseUnknownLength != _expectedLength)
        TLMLog(__func__, @"Will download %lld bytes%C", _expectedLength, TLM_ELLIPSIS);
}

- (void)download:(NSURLDownload *)download didReceiveDataOfLength:(NSUInteger)length
{
    _receivedLength += length;
    if (NSURLResponseUnknownLength != _expectedLength) {
        if ((CGFloat)(_receivedLength - _lastLoggedLength) / _expectedLength >= 0.20) {
            CGFloat pct = (CGFloat)_receivedLength / _expectedLength * 100;
            _lastLoggedLength = _receivedLength;
            TLMLog(__func__, @"Received %.0f%% of %lld bytes%C", pct, _expectedLength, TLM_ELLIPSIS);
        }
    }
}

- (BOOL)download:(NSURLDownload *)download shouldDecodeSourceDataOfMIMEType:(NSString *)encodingType;
{
    return NO;
}

- (void)download:(NSURLDownload *)download didFailWithError:(NSError *)error
{
    [self setFailed:YES];
    // should already be NO, but make sure...
    _downloadComplete = NO;
    TLMLog(__func__, @"Download failed: %@\nFailed URL was: %@", error, [[download request] URL]);
}

- (void)downloadDidFinish:(NSURLDownload *)download
{
    _downloadComplete = YES;
    TLMLog(__func__, @"Download of %lld bytes complete", _receivedLength);
}

- (void)_synchronouslyDownloadURL:(NSURL *)aURL toPath:(NSString *)absolutePath
{
    /*
     Apple's URL caching seems to be screwed up badly, since I regularly get a mismatched hash and script, but
     a quit/relaunch seems to "fix" the problem.  We'll try this for a while and see how it goes...
     */
    [[NSURLCache sharedURLCache] performSelectorOnMainThread:@selector(removeAllCachedResponses) withObject:nil waitUntilDone:YES modes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
    
    NSURLRequest *request = [NSURLRequest requestWithURL:aURL cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60.0];
    
    // previous download must be finished
    NSParameterAssert(nil == _download);
    
    // reset all state for this download
    _downloadComplete = NO;
    _receivedLength = 0;
    _lastLoggedLength = 0;
    _expectedLength = 0;
    
    _download = [[NSURLDownload alloc] initWithRequest:request delegate:self];
    [_download setDestination:absolutePath allowOverwrite:YES];
    
    TLMLog(__func__, @"Downloading URL: %@", aURL);
    
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
    
    [_download release];
    _download = nil;
}

- (BOOL)_downloadUpdateScript
{
    NSString *path = [[NSUserDefaults standardUserDefaults] objectForKey:TLMNetInstallerPathPreferenceKey];
    NSURL *scriptURL = [_location tlm_URLByAppendingPathComponent:path];
    
    [self _synchronouslyDownloadURL:scriptURL toPath:[_updateDirectory stringByAppendingPathComponent:path]];
    
    // set rwxr-xr-x
    if (_downloadComplete) {
        
        TLMTask *untarTask = [[TLMTask new] autorelease];
        [untarTask setCurrentDirectoryPath:_updateDirectory];
        [untarTask setLaunchPath:@"/usr/bin/tar"];
        
        /*
         By default, this will untar into a directory with the date appended; e.g., install-tl-20091213
         and the script lives one level below that.  Instead of listing the directory or the first path
         in the tarball, just strip the first component.
         */
        [untarTask setArguments:[NSArray arrayWithObjects:@"-zxvf", path, @"--strip-components", @"1", nil]];
        [untarTask launch];
        [untarTask waitUntilExit];
        
        TLMLog(__func__, @"stdout: %@", [untarTask outputString]);
        TLMLog(__func__, @"stderr: %@", [untarTask errorString]);
        
        _downloadComplete = (0 == [untarTask terminationStatus]);
    }
        
    if (_downloadComplete) {
        
        const char *fs_path = [_scriptPath saneFileSystemRepresentation];
        if (chmod(fs_path, S_IRUSR | S_IXUSR)) {
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
                TLMLog(__func__, @"First line of downloaded file is: \"%s\"%Cgood!", firstLine, TLM_ELLIPSIS);
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
    
    [pool release];
}

@end
