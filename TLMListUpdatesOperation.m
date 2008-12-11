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
#import "TLMOutputParser.h"
#import "TLMPreferenceController.h"

@interface TLMListUpdatesOperation()
@property (readwrite, copy) NSURL *updateURL;
@end


@implementation TLMListUpdatesOperation

@synthesize updateURL = _updateURL;

- (id)init
{
    NSString *location = [[[TLMPreferenceController sharedPreferenceController] serverURL] absoluteString];
    NSArray *options = [NSArray arrayWithObjects:@"--location", location, @"update", @"--list", nil];
    NSString *cmd = [[TLMPreferenceController sharedPreferenceController] tlmgrAbsolutePath];
    return [self initWithCommand:cmd options:options];
}

- (void)dealloc
{
    [_updateURL release];
    [_packages release];
    [super dealloc];
}

- (void)_parseResults
{
    NSParameterAssert([self isFinished]);
    NSParameterAssert(nil == _packages);
    
    NSData *output = [self outputData];        
    if ([output length]) {
        NSMutableArray *packages = [NSMutableArray new];
        NSString *outputString = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
        if (nil == outputString)
            outputString = [[NSString alloc] initWithData:output encoding:NSMacOSRomanStringEncoding];
        
        NSMutableArray *lines = [[[outputString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] mutableCopy] autorelease];
        [outputString release];
        
        // tlmgr: installation location http://mirror.hmc.edu/ctan/systems/texlive/tlnet/2008
        
        NSString *installPrefix = @"tlmgr: installation location ";
        if ([lines count] && [[lines objectAtIndex:0] hasPrefix:installPrefix]) {
            NSString *urlString = [[lines objectAtIndex:0] stringByReplacingOccurrencesOfString:installPrefix withString:@""];
            [self setUpdateURL:[NSURL URLWithString:urlString]];
            [lines removeObjectAtIndex:0];
        }
        
        NSCharacterSet *nonWhitespace = [[NSCharacterSet whitespaceCharacterSet] invertedSet];
        for (NSString *line in lines) {
            if ([line rangeOfCharacterFromSet:nonWhitespace].length)
                [packages addObject:[TLMOutputParser packageWithOutputLine:line]];
        }
        
        _packages = [packages copy];
        [packages release];
    }
}

- (NSArray *)packages
{
    if (nil == _packages && [self isFinished])
        [self _parseResults];
    return _packages;
}

@end
