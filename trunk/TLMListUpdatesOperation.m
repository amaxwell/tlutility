//
//  TLMListUpdatesOperation.m
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

#import "TLMListUpdatesOperation.h"
#import "TLMOutputParser.h"
#import "TLMPreferenceController.h"
#import "TLMLogServer.h"
#import "TLMTask.h"

@interface TLMListUpdatesOperation()
@property (readwrite, copy) NSURL *updateURL;
@end


@implementation TLMListUpdatesOperation

@synthesize updateURL = _updateURL;

- (id)initWithLocation:(NSURL *)location
{
    NSParameterAssert([location absoluteString]);
    NSArray *options = [NSArray arrayWithObjects:@"--machine-readable", @"--location", [location absoluteString], @"update", @"--list", nil];
    NSString *cmd = [[TLMPreferenceController sharedPreferenceController] tlmgrAbsolutePath];
    return [self initWithCommand:cmd options:options];
}

- (void)dealloc
{
    [_updateURL release];
    [_packages release];
    [super dealloc];
}

- (void)_parsePackageLines:(NSArray *)lines withClass:(Class)parserClass
{
    NSParameterAssert(parserClass);
    NSParameterAssert(lines);
            
    NSMutableArray *packages = [NSMutableArray new];
    NSCharacterSet *nonWhitespace = [[NSCharacterSet whitespaceCharacterSet] invertedSet];
    for (NSString *line in lines) {
        if ([line rangeOfCharacterFromSet:nonWhitespace].length)
            [packages addObject:[parserClass packageWithUpdateLine:line]];
    }
    _packages = [packages copy];
    [packages release];

}

static NSUInteger __TLMIndexOfStringWithPrefix(NSArray *array, NSString *prefix)
{
    for (NSUInteger i = 0; i < [array count]; i++) {
        if ([[array objectAtIndex:i] hasPrefix:prefix])
            return i;
    }
    return NSNotFound;
}

static NSDictionary *__TLMHeaderDictionaryWithLines(NSArray *headerLines)
{
    NSMutableDictionary *header = [NSMutableDictionary dictionary];
    for (NSString *line in headerLines) {
        NSArray *keyValue = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([keyValue count] > 1)
            [header setObject:[keyValue objectAtIndex:1] forKey:[keyValue objectAtIndex:0]];
    }
    return header;
}

- (void)_parseLines:(NSArray *)lines
{
    NSParameterAssert([self isFinished]);
    NSParameterAssert(nil == _packages);
        
    NSMutableArray *packageLines = [[lines mutableCopy] autorelease];

    /*
     version 2: 
     location-url	http://mirror.hmc.edu/ctan/systems/texlive/tlnet/2008
     total-bytes	216042383
     end-of-header
    */
    NSUInteger headerStopIndex = __TLMIndexOfStringWithPrefix(packageLines, @"end-of-header");
    NSDictionary *header = nil;
    if (NSNotFound != headerStopIndex) {
        header = __TLMHeaderDictionaryWithLines([packageLines subarrayWithRange:NSMakeRange(0, headerStopIndex)]);
        [packageLines removeObjectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, headerStopIndex + 1)]];
        TLMLog(__func__, @"header = %@", header);
    }
    else {
        // saw this happen once (tlmgr returned an error)
        TLMLog(__func__, @"*** ERROR *** header not found in output:\n%@", lines);
        packageLines = nil;
    }

    if ([header objectForKey:@"location-url"])
        [self setUpdateURL:[NSURL URLWithString:[header objectForKey:@"location-url"]]];
    
    // should be the last line in the output, so iterate in reverse order
    NSUInteger outputStopIndex = [packageLines count];
    while (outputStopIndex--) {
        
        // this marker is currently only on the updates code path, and we don't want to pass it to the parser
        if ([[packageLines objectAtIndex:outputStopIndex] hasPrefix:@"end-of-updates"]) {
            [packageLines removeObjectAtIndex:outputStopIndex];
            TLMLog(__func__, @"Found end-of-updates line");
            break;
        }
    }

    [self _parsePackageLines:packageLines withClass:[TLMOutputParser self]];
}

- (NSArray *)packages
{
    // return nil for cancelled or failed operations (prevents logging error messages)
    if (nil == _packages && [self isFinished] && NO == [self isCancelled] && NO == [self failed]) {
        if ([[self outputData] length]) {
            NSString *outputString = [[NSString alloc] initWithData:[self outputData] encoding:NSUTF8StringEncoding];        
            NSArray *lines = [outputString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
            [outputString release];
            [self _parseLines:lines];
        }   
        else {
            TLMLog(__func__, @"No data read from standard output stream.");
        }
    }
    return _packages;
}

@end
