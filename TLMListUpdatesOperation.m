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
#import "TLMOutputParser2.h"
#import "TLMPreferenceController.h"
#import "TLMLogServer.h"
#import "TLMTask.h"

@interface TLMListUpdatesOperation()
@property (readwrite, copy) NSURL *updateURL;
@end


@implementation TLMListUpdatesOperation

@synthesize updateURL = _updateURL;

+ (BOOL)_useMachineReadableParser
{
    /*
     froude:tmp amaxwell$ tlmgr --machine-readable >/dev/null
     Unknown option: machine-readable
     Usage:
     tlmgr [*option*]... *action* [*option*]... [*operand*]...
     
     froude:tmp amaxwell$ tlmgr2 --machine-readable >/dev/null
     /usr/texbin/tlmgr2: missing action; try --help if you need it.
     froude:tmp amaxwell$ 
     */
    NSArray *options = [NSArray arrayWithObject:@"--machine-readable"];
    NSString *cmd = [[TLMPreferenceController sharedPreferenceController] tlmgrAbsolutePath];
    TLMTask *task = [[TLMTask new] autorelease];
    [task setLaunchPath:cmd];
    [task setArguments:options];
    [task launch];
    [task waitUntilExit];
    
    NSInteger ret = [task terminationStatus];
    if (0 == ret) TLMLog(__func__, @"Unexpected successful termination from test for tlmgr2");

    NSString *errorString = [task errorString];
    BOOL hasMachineReadable = YES;
    
    // Karl's suggested test.  Safe to assume this error message won't change for the original tlmgr.
    if ([errorString hasPrefix:@"Unknown option:"])
        hasMachineReadable = NO;
    else if (nil == errorString || [errorString rangeOfString:@"unknown action"].length == 0) {
        // allow upstream to change this, but warn of any such changes
        TLMLog(__func__, @"Unexpected output from test for tlmgr2: \"%@\"", errorString);
        TLMLog(__func__, @"Assuming tlmgr2 and proceeding, but please report failures to the developer");
    }
    
    if (NO == hasMachineReadable)
        TLMLog(__func__, @"tlmgr does not support --machine-readable yet; ad-hoc parsing will be used");
    
    return hasMachineReadable;
}

- (id)init
{
    NSAssert(0, @"Invalid initializer.  Location parameter is required.");
    return [self initWithLocation:nil];
}

- (id)initWithLocation:(NSURL *)location
{
    NSParameterAssert([location absoluteString]);
    NSMutableArray *options = [NSMutableArray arrayWithObjects:@"--location", [location absoluteString], @"update", @"--list", nil];
    NSString *cmd = [[TLMPreferenceController sharedPreferenceController] tlmgrAbsolutePath];
    SEL parseSelector = @selector(_parseLines:);
    if ([[self class] _useMachineReadableParser]) {
        [options insertObject:@"--machine-readable" atIndex:0];
        parseSelector = @selector(_parseLines2:);
    }  
    self = [self initWithCommand:cmd options:options];
    if (self) {
        _parseSelector = parseSelector;
    }
    return self;
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

- (void)_parseLines2:(NSArray *)lines
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

    [self _parsePackageLines:packageLines withClass:[TLMOutputParser2 self]];
}

- (void)_parseLines:(NSArray *)lines
{
    NSParameterAssert([self isFinished]);
    NSParameterAssert(nil == _packages);
    
    NSMutableArray *packageLines = [[lines mutableCopy] autorelease];
    
    /*
     version 1: 
     tlmgr: installation location http://mirror.hmc.edu/ctan/systems/texlive/tlnet/2008
    */
    NSString *installPrefix = @"tlmgr: installation location ";
    if ([packageLines count] && [[packageLines objectAtIndex:0] hasPrefix:installPrefix]) {
        NSString *urlString = [[packageLines objectAtIndex:0] stringByReplacingOccurrencesOfString:installPrefix withString:@""];
        TLMLog(__func__, @"Using mirror at %@", urlString);
        [self setUpdateURL:[NSURL URLWithString:urlString]];
        [packageLines removeObjectAtIndex:0];
    }
    else if ([packageLines count]) {
        TLMLog(__func__, @"Expected prefix \"%@\" but actual line was:\n%@", installPrefix, [packageLines objectAtIndex:0]);
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
            [self performSelector:_parseSelector withObject:lines];
        }   
        else {
            TLMLog(__func__, @"No data read from standard output stream.");
        }
    }
    return _packages;
}

@end
