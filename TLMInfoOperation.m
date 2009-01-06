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
    
    /*
     Minor hack to avoid duplicating all the task and pipe code here; this task doesn't depend on network
     operations, so it's not going to block for a long time.  The main oddity is that it's not possible 
     to use the standard NSOperation accessors (e.g. isCancelled/isFinished).
     */
    NSString *packageName = [self packageName];
#warning fixme
    NSRange r = [packageName rangeOfString:@"bin-"];
    if (0 == r.length)
        r = [packageName rangeOfString:@"collection-"];
    if (r.length)
        packageName = [packageName substringFromIndex:NSMaxRange(r)];
    
    TLMOperation *op = [[TLMOperation alloc] initWithCommand:cmd options:[NSArray arrayWithObjects:@"-l", @"-I", packageName, nil]];
    [op main];
    [op autorelease];
    
    TLMLog(__func__, @"Finding documentation for %@%C", packageName, 0x2026);
    
    if ([self isCancelled] == NO && [op failed] == NO) {
        NSData *outputData = [op outputData];
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
    
    if ([op errorMessages])
        TLMLog(__func__, @"%@", [[op errorMessages] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);
    
    if ([[self documentationURLs] count] == 0)
        TLMLog(__func__, @"Unable to find documentation for %@", packageName);

    [pool release];
}

@end
