//
//  TLMBackupListOperation.m
//  TeX Live Manager
//
//  Created by Adam R. Maxwell on 10/14/10.
/*
 This software is Copyright (c) 2010-2011
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

#import "TLMBackupListOperation.h"
#import "TLMPreferenceController.h"
#import "TLMOutputParser.h"
#import "TLMLogServer.h"

@implementation TLMBackupListOperation

@synthesize backupNodes = _backupNodes;

- (id)init
{
    NSString *tlmgrPath = [[TLMPreferenceController sharedPreferenceController] tlmgrAbsolutePath];
    return [self initWithCommand:tlmgrPath options:[NSArray arrayWithObject:@"restore"]];
}

- (void)dealloc
{
    [_backupNodes release];
    [super dealloc];
}

- (NSArray *)backupNodes
{
    // return nil for cancelled or failed operations (prevents logging error messages)
    if (nil == _backupNodes && [self isFinished] && NO == [self isCancelled] && NO == [self failed]) {
        if ([[self outputData] length]) {
            NSString *outputString = [[NSString alloc] initWithData:[self outputData] encoding:NSUTF8StringEncoding];        
            NSArray *lines = [outputString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
            if ([lines count] > 1) {
                lines = [lines subarrayWithRange:NSMakeRange(1, [lines count] - 1)];
                _backupNodes = [[TLMOutputParser backupNodesWithListLines:lines] copy];
            }
            [outputString release];
        }   
        else {
            TLMLog(__func__, @"No data read from standard output stream.");
        }
    }
    return _backupNodes;
}

@end
