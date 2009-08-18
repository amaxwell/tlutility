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
#import "TLMTask.h"

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

static float __TLMTexdocVersion()
{
    NSString *cmd = [[TLMPreferenceController sharedPreferenceController] texdocAbsolutePath];
    TLMTask *task = [[TLMTask new] autorelease];
    [task setLaunchPath:cmd];
    
    /*
     NB: 0.4 uses -v for --version.  Unfortunately, 0.42 uses -v for --verbose and has no short 
     option for version, so we'll use the lowest common denominator.
     */
    [task setArguments:[NSArray arrayWithObject:@"--version"]];
    [task launch];
    [task waitUntilExit];
    
    /*
     0.4 output: "texdoc version: 0.4"
     0.42 output: "texdoc 0.42"
     svn output: "texdoc 0.42+ svn r45"
     */    
    NSString *versionString = [task terminationStatus] == EXIT_SUCCESS ? [task outputString] : nil;
    
    NSScanner *scanner = nil;
    if (versionString)
        scanner = [NSScanner scannerWithString:versionString];
        
    // return something invalid on failure
    float version = -1.0;
    if ([scanner scanUpToCharactersFromSet:[NSCharacterSet decimalDigitCharacterSet] intoString:NULL])
        [scanner scanFloat:&version];
    
    return version;
}

static NSArray * __TLMURLsFromTexdocOutput(NSString *outputString)
{
    float version = __TLMTexdocVersion();
    NSMutableArray *docURLs = [NSMutableArray array];

    // 0.41 was never released (comparing version > 0.4 may not be true due to floating point error)
    if (version < 0 || version >= 0.41) {
        /*
         froude:tmp amaxwell$ texdoc --version
         texdoc 0.42
         froude:tmp amaxwell$ texdoc -l -I makeindex
         texdoc info: makeindex aliased to base/makeindex
         1 /usr/local/texlive/2008/texmf-dist/doc/makeindex/base/makeindex.pdf
         */
        NSArray *lines = [outputString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        for (NSString *line in lines) {
            NSScanner *scanner = [NSScanner scannerWithString:line];
            if ([scanner scanCharactersFromSet:[NSCharacterSet decimalDigitCharacterSet] intoString:NULL]) {
                NSString *docPath = [scanner isAtEnd] ? nil : [[scanner string] substringFromIndex:[scanner scanLocation]];
                docPath = [docPath stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                NSURL *docURL = nil;
                if (docPath) docURL = [NSURL fileURLWithPath:docPath];
                if (docURL) [docURLs addObject:docURL];
            }
        }
    }
    else {
        /*
         froude:tmp amaxwell$ texdoc --version
         texdoc version: 0.4
         froude:tmp amaxwell$ texdoc -l -I makeindex
         /usr/local/texlive/2008/texmf/doc/man/man1/makeindex.pdf
         /usr/local/texlive/2008/texmf-dist/doc/makeindex/base/makeindex.dvi
         */
        NSArray *docPaths = [outputString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        for (NSString *docPath in docPaths) {
            // avoid empty lines...
            docPath = [docPath stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSURL *docURL = [docPath isEqualToString:@""] ? nil : [NSURL fileURLWithPath:docPath];
            if (docURL) [docURLs addObject:docURL];
        }
    }
    return docURLs;
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
     The full package name for tlmgr contains names like "bin-dvips.universal-darwin", where
     the relevant bit as far as texdoc is concerned is "dvips".
     */
    NSString *packageName = [self packageName];
    
    // see if we have a "bin-" prefix
    NSRange r = [packageName rangeOfString:@"bin-"];
    
    // not clear if collection names are meaningful to texdoc but try anyway...
    if (0 == r.length)
        r = [packageName rangeOfString:@"collection-"];
    
    // remove the prefix
    if (r.length)
        packageName = [packageName substringFromIndex:NSMaxRange(r)];

    // now look for architecture and remove e.g. ".universal-darwin"
    r = [packageName rangeOfString:@"." options:NSBackwardsSearch];
    if (r.length)
        packageName = [packageName substringToIndex:r.location];
    
    sig_t previousSignalMask = signal(SIGPIPE, SIG_IGN);
    
    TLMTask *task = [[TLMTask new] autorelease];
    [task setLaunchPath:cmd];
    [task setArguments:[NSArray arrayWithObjects:@"-l", @"-I", packageName, nil]];
    [task launch];
    
    // Reimplement -[NSTask waitUntilExit] so we can handle -[NSOperation cancel].
    while ([task isRunning] && [self isCancelled] == NO) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, TRUE);
    }
    
    int status = -1;
    if ([self isCancelled]) {
        [task terminate];
    }
    else {
        // not cancelled, but make sure it's really done before calling -terminationStatus
        [task waitUntilExit];
        status = [task terminationStatus];
    }
    
    NSString *errorString = 0 != status ? nil : [task errorString];
    NSString *outputString = 0 != status ? nil : [task outputString];
    
    signal(SIGPIPE, previousSignalMask);
    
    if (outputString) {
        NSArray *docURLs = __TLMURLsFromTexdocOutput(outputString);
        if ([docURLs count])
            [self setDocumentationURLs:docURLs];
    }
    
    // don't bother logging any errors in case of cancellation
    if (errorString && [self isCancelled] == NO)
        TLMLog(__func__, @"%@", [errorString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);
    
    if ([[self documentationURLs] count] == 0 && [self isCancelled] == NO)
        TLMLog(__func__, @"Unable to find documentation for %@", packageName);

    [pool release];
}

@end
