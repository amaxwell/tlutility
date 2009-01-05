//
//  TLMInfoOperation.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/7/08.
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

#import "TLMInfoOperation.h"
#import "TLMPreferenceController.h"
#import "TLMLogServer.h"
#import "BDSKTask.h"

@interface TLMInfoOperation()
@property (readwrite, copy) NSArray *documentationURLs;
@end

@implementation TLMInfoOperation

@synthesize packageName = _packageName;
@synthesize documentationURLs = _documentationURLs;

- (id)initWithPackageName:(NSString *)packageName
{
    NSParameterAssert(packageName);
    NSString *location = [[[TLMPreferenceController sharedPreferenceController] defaultServerURL] absoluteString];
    NSArray *options = [NSArray arrayWithObjects:@"--location", location, @"show", packageName, nil];
    NSString *cmd = [[TLMPreferenceController sharedPreferenceController] tlmgrAbsolutePath];
    self = [self initWithCommand:cmd options:options];
    if (self) {
        _packageName = [packageName copy];
    }
    return self;
}

- (void)dealloc
{
    [_packageName release];
    [_documentationURLs release];
    [super dealloc];
}

- (NSString *)infoString
{
    NSData *output = [self outputData];  
    NSString *infoString = nil;
    if ([output length]) {
        infoString = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
        if (nil == infoString)
            infoString = [[NSString alloc] initWithData:output encoding:NSMacOSRomanStringEncoding];
    }
    return [infoString autorelease];
}

- (void)main
{
    [super main];
    
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    NSString *cmd = [[TLMPreferenceController sharedPreferenceController] texdocAbsolutePath];
    
    // !!! bail out early if the file doesn't exist
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:cmd] == NO) {
        TLMLog(__func__, @"%@ does not exist or is not executable", cmd);
        [pool release];
        return;
    }
    
    BDSKTask *task = [[BDSKTask new] autorelease];
    [task setLaunchPath:cmd];
    [task setArguments:[NSArray arrayWithObjects:@"-l", @"-I", [self packageName], nil]];
    
    // output won't fill the pipe's buffer
    [task setStandardOutput:[NSPipe pipe]];
    [task setStandardError:[NSPipe pipe]];
    [task launch];
    [task waitUntilExit];
        
    if ([task terminationStatus] == 0) {
        NSFileHandle *fh = [[task standardOutput] fileHandleForReading];
        NSData *outputData = [fh readDataToEndOfFile];
        NSString *outputString = nil;
        if ([outputData length])
            outputString = [[[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding] autorelease];
        if (outputString) {
            NSArray *docPaths = [outputString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
            NSMutableArray *docURLs = [NSMutableArray array];
            for (NSString *docPath in docPaths) {
                // avoid empty lines...
                docPath = [docPath stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                NSURL *docURL = [docPath isEqualToString:@""] ? nil : [NSURL fileURLWithPath:docPath];
                if (docURL) [docURLs addObject:docURL];
            }
            if ([docURLs count])
                [self setDocumentationURLs:docURLs];
        }
    }
    
    // read stderr
    NSFileHandle *fh = [[task standardError] fileHandleForReading];
    NSData *errorData = [fh readDataToEndOfFile];
    NSString *errorString = nil;
    if ([errorData length])
        errorString = [[[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding] autorelease];
    if (errorString)
        TLMLog(__func__, @"%@", [errorString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);
    
    if ([[self documentationURLs] count] == 0)
        TLMLog(__func__, @"Unable to find documentation for %@", [self packageName]);

    [pool release];
}

@end
