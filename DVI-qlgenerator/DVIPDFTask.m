//
//  DVIPDFTask.m
//  DVI
//
//  Created by Adam Maxwell on 02/03/09.
/*
 This software is Copyright (c) 2009
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


#import "DVIPDFTask.h"
#import "BDSKTask.h"

#define DEFAULT_PATH @"/usr/texbin/dvipdfmx"
#define PREF_KEY "DvipdfmxPathKey"

static NSString *__CopyDviPDFmxPathForBundleID(CFStringRef bundleIdentifier)
{
    NSString *path = (NSString *)CFPreferencesCopyAppValue(CFSTR(PREF_KEY), bundleIdentifier);
    if (nil == path) path = [DEFAULT_PATH copy];
    return (NSString *)path;
}

static NSString *__CreateTemporaryFile()
{
    NSString *tempDir = NSTemporaryDirectory();
    if (nil == tempDir)
        tempDir = @"/tmp";
    
    const char *tmpPath = [[tempDir stringByAppendingPathComponent:@"DVIPDFTask.XXXXXX"] fileSystemRepresentation];
    
    // mktemp needs a writable string
    char *tempName = strdup(tmpPath);
    
    tempName = mktemp(tempName);
    assert(tempName);
    
    NSString *tempFile = (NSString *)CFStringCreateWithFileSystemRepresentation(CFAllocatorGetDefault(), tempName);
    free(tempName);

    return tempFile;
}    

CFDataRef DVICreatePDFDataFromFile(CFURLRef fileURL, bool allPages, CFBundleRef generatorBundle)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];    
    NSFileManager *fm = [NSFileManager new];
    NSData *output = nil;
    
    NSString *dviPDFmxPath = __CopyDviPDFmxPathForBundleID(CFBundleGetIdentifier(generatorBundle));
    
    if ([fm isExecutableFileAtPath:dviPDFmxPath]) {
        
        BDSKTask *task = [BDSKTask new];
        [task setLaunchPath:dviPDFmxPath];
        [task setStandardError:[NSFileHandle fileHandleWithNullDevice]];
        [task setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
        
        NSString *outputPath = __CreateTemporaryFile();
        NSMutableArray *args = [[NSMutableArray alloc] initWithObjects:@"-o", outputPath, @"-q", nil];
        if (false == allPages) {
            [args addObject:@"-s"];
            [args addObject:@"1-1"];
        }
        [args addObject:[(NSURL *)fileURL path]];
        
        [task setArguments:args];
        [args release];
        
        int status;
        
        @try {
            [task launch];
            [task waitUntilExit];
            status = [task terminationStatus];
        }
        @catch(id exception) {
            status = -1;
        }
        [task release];
        
        if (0 == status)
            output = [[NSData alloc] initWithContentsOfFile:outputPath options:NSUncachedRead error:NULL];

        [fm removeItemAtPath:outputPath error:NULL];
        [outputPath release];
    }
    
    [dviPDFmxPath release];
    
    [fm release];
    [pool release];
    
    return (CFDataRef)output;
}
