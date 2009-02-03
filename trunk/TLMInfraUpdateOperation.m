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

#import <CommonCrypto/CommonDigest.h>
#import <unistd.h>
#import <sys/mman.h>
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
        
        // download the sha256 file to this path
        NSString *hashFilename = [[NSUserDefaults standardUserDefaults] objectForKey:TLMInfraPathPreferenceKey];
        hashFilename = [hashFilename stringByAppendingPathExtension:@"sha256"];
        _hashPath = [[updateDirectory stringByAppendingPathComponent:hashFilename] copy];
    }
    return self;
}

- (void)dealloc
{
    [_download release];
    [_updateDirectory release];
    [_scriptPath release];
    [_hashPath release];
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
    if (NSURLResponseUnknownLength != _expectedLength)
        TLMLog(__func__, @"Will download %lld bytes%C", _expectedLength, 0x2026);
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

- (BOOL)download:(NSURLDownload *)download shouldDecodeSourceDataOfMIMEType:(NSString *)encodingType;
{
    return NO;
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

- (void)_synchronouslyDownloadURL:(NSURL *)aURL toPath:(NSString *)absolutePath
{
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
    NSString *path = [[NSUserDefaults standardUserDefaults] objectForKey:TLMInfraPathPreferenceKey];
    CFURLRef fullURL = CFURLCreateCopyAppendingPathComponent(CFGetAllocator(_location), (CFURLRef)_location, (CFStringRef)path, FALSE);
    NSURL *scriptURL = [(id)fullURL autorelease];
    
    [self _synchronouslyDownloadURL:scriptURL toPath:_scriptPath];

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

- (BOOL)_downloadAndCheckHash
{
    NSParameterAssert([self failed] == NO && [self isCancelled] == NO);
    
    // remote URL is the same as the file we just downloaded, but with .sha256 appended
    NSString *path = [[NSUserDefaults standardUserDefaults] objectForKey:TLMInfraPathPreferenceKey];
    path = [path stringByAppendingPathExtension:@"sha256"];
    CFURLRef fullURL = CFURLCreateCopyAppendingPathComponent(CFGetAllocator(_location), (CFURLRef)_location, (CFStringRef)path, FALSE);
    NSURL *hashURL = [(id)fullURL autorelease];
    
    [self _synchronouslyDownloadURL:hashURL toPath:_hashPath];
    
    BOOL isOkay = NO;
    if (_downloadComplete) {
        
        const char *path = [_scriptPath fileSystemRepresentation];
        
        // guaranteed to be able to open the file here
        int fd = open(path, O_RDONLY);
        
        int status;
        struct stat sb;
        status = fstat(fd, &sb);
        if (status) {
            perror(path);
            close(fd);
            return NO;
        }
        
        (void)fcntl(fd, F_NOCACHE, 1);
        
        char *buffer = mmap(0, sb.st_size, PROT_READ, MAP_SHARED, fd, 0);
        close(fd);    
        if (buffer == (void *)-1) {
            perror("failed to mmap file");
            TLMLog(__func__, @"Failed to memory map %@", _scriptPath);
            return NO;
        }
        
        // digest the entire file at once
        unsigned char digest[CC_SHA256_DIGEST_LENGTH] = { '\0' };
        (void) CC_SHA256(buffer, sb.st_size, digest);
        munmap(buffer, sb.st_size);
                
        // the downloaded digest is a hex string, so convert to hex for comparison
        NSMutableString *scriptHashHexString = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH];
        for (unsigned i = 0; i < CC_SHA256_DIGEST_LENGTH; i++)
            [scriptHashHexString appendFormat:@"%02x", digest[i]];
        
        // compare as data so it's clear that we need byte equality
        NSParameterAssert([scriptHashHexString canBeConvertedToEncoding:NSASCIIStringEncoding]);
        NSData *scriptHash = [scriptHashHexString dataUsingEncoding:NSASCIIStringEncoding];
        NSData *checkHash = [NSData dataWithContentsOfFile:_hashPath options:NSUncachedRead error:NULL];

        // downloaded hash has a description string appended
        if ([checkHash length] >= [scriptHash length])
            isOkay = [[checkHash subdataWithRange:NSMakeRange(0, [scriptHash length])] isEqualToData:scriptHash];
        if (isOkay)
            TLMLog(__func__, @"SHA256 signature looks okay");
        else
            TLMLog(__func__, @"*** ERROR *** SHA256 signature does not match");
    }
    else {
        TLMLog(__func__, @"Unable to download SHA256 signature from %@", hashURL);
    }
    return isOkay;
}

- (void)main
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    // don't run if the user cancelled during download or something failed
    if ([self _downloadUpdateScript] && NO == [self isCancelled] && NO == [self failed] && [self _downloadAndCheckHash])
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
