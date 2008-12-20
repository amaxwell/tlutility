//
//  TLMListUpdatesOperation.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/7/08.
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

#import "TLMListUpdatesOperation.h"
#import "TLMOutputParser2.h"
#import "TLMPreferenceController.h"
#import "TLMLogServer.h"
#import "BDSKTask.h"

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
    BDSKTask *task = [[BDSKTask new] autorelease];
    
    // in either case, the output won't fill the pipe's buffer (see above)
    [task setStandardError:[NSPipe pipe]];
    [task setLaunchPath:cmd];
    [task setArguments:options];
    [task launch];
    [task waitUntilExit];
    
    NSInteger ret = [task terminationStatus];
    if (0 == ret) TLMLog(@"TLMListUpdatesOperation", @"Unexpected successful termination from test for tlmgr2");
    
    NSFileHandle *fh = [[task standardError] fileHandleForReading];
    NSData *outputData = [fh readDataToEndOfFile];
    NSString *outputString = nil;
    if ([outputData length])
        outputString = [[[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding] autorelease];
    
    BOOL hasMachineReadable = YES;
    
    // Karl's suggested test.  Safe to assume this error message won't change for the original tlmgr.
    if ([outputString hasPrefix:@"Unknown option:"])
        hasMachineReadable = NO;
    else if (nil == outputString || [outputString rangeOfString:@"unknown action"].length == 0) {
        // allow upstream to change this, but warn of any such changes
        TLMLog(@"TLMListUpdatesOperation", @"Unexpected output from test for tlmgr2: \"%@\"", outputString);
    }
    
    if (NO == hasMachineReadable)
        TLMLog(@"TLMListUpdatesOperation", @"tlmgr does not support --machine-readable; ad-hoc parsing will be used");
    
    return hasMachineReadable;
}

- (id)init
{
    NSString *location = [[[TLMPreferenceController sharedPreferenceController] defaultServerURL] absoluteString];
    NSMutableArray *options = [NSMutableArray arrayWithObjects:@"--location", location, @"update", @"--list", nil];
    _parseSelector = @selector(_parseResults);
    if ([[self class] _useMachineReadableParser]) {
        [options insertObject:@"--machine-readable" atIndex:0];
        _parseSelector = @selector(_parseResults2);
    }
    NSString *cmd = [[TLMPreferenceController sharedPreferenceController] tlmgrAbsolutePath];
    return [self initWithCommand:cmd options:options];
}

- (void)dealloc
{
    [_updateURL release];
    [_packages release];
    [super dealloc];
}

- (void)_parseResultsWithClass:(Class)parserClass URLPrefix:(NSString *)installPrefix
{
    NSParameterAssert(parserClass);
    NSParameterAssert(installPrefix);
    
    NSData *output = [self outputData];        
    if ([output length]) {
        NSMutableArray *packages = [NSMutableArray new];
        NSString *outputString = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];        
        NSMutableArray *lines = [[[outputString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] mutableCopy] autorelease];
        [outputString release];
        
        // version 1: "tlmgr: installation location http://mirror.hmc.edu/ctan/systems/texlive/tlnet/2008"
        // version 2: "installation-url http://mirror.hmc.edu/ctan/systems/texlive/tlnet/2008"
        if ([lines count] && [[lines objectAtIndex:0] hasPrefix:installPrefix]) {
            TLMLog(@"TLMListUpdatesOperation", @"%@", [lines objectAtIndex:0]);
            NSString *urlString = [[lines objectAtIndex:0] stringByReplacingOccurrencesOfString:installPrefix withString:@""];
            [self setUpdateURL:[NSURL URLWithString:urlString]];
            [lines removeObjectAtIndex:0];
        }
        else if ([lines count]) {
            TLMLog(@"TLMListUpdatesOperation", @"Expected prefix \"%@\" but actual line was:\n%@", installPrefix, [lines objectAtIndex:0]);
        }
        
        NSCharacterSet *nonWhitespace = [[NSCharacterSet whitespaceCharacterSet] invertedSet];
        for (NSString *line in lines) {
            if ([line rangeOfCharacterFromSet:nonWhitespace].length)
                [packages addObject:[parserClass packageWithOutputLine:line]];
        }
        
        _packages = [packages copy];
        [packages release];
    }
    else {
        TLMLog(@"TLMListUpdatesOperation", @"No data read from standard output stream.");
    }
}

- (void)_parseResults2
{
    NSParameterAssert([self isFinished]);
    NSParameterAssert(nil == _packages);
    [self _parseResultsWithClass:[TLMOutputParser2 self] URLPrefix:@"location-url "];
}

- (void)_parseResults
{
    NSParameterAssert([self isFinished]);
    NSParameterAssert(nil == _packages);
    [self _parseResultsWithClass:[TLMOutputParser self] URLPrefix:@"tlmgr: installation location "];
}

- (NSArray *)packages
{
    // return nil for cancelled operations (prevents logging error messages)
    if (nil == _packages && [self isFinished] && NO == [self isCancelled])
        [self performSelector:_parseSelector];
    return _packages;
}

@end
