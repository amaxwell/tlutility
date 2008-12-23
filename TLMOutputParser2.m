//
//  TLMOutputParser2.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/15/08.
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

#import "TLMOutputParser2.h"
#import "TLMPackage.h"
#import "TLMLogServer.h"

@implementation TLMOutputParser2

+ (NSString *)_statusStringForCharacter:(unichar)ch
{
    NSString *status = nil;
    switch (ch) {
        case 'd':
            status = NSLocalizedString(@"Deleted on server", @"");
            break;
        case 'u':
            status = NSLocalizedString(@"Updated on server", @"");
            break;
        case 'a':
            status = NSLocalizedString(@"Not installed", @"");
            break;
        case 'f':
            status = NSLocalizedString(@"Forcibly removed", @"");
            break;
        default:
            TLMLog(@"TLMOutputParser2", @"Unknown status code \"%C\"", ch);
            break;
    }
    return status;
}

+ (TLMPackage *)packageWithUpdateLine:(NSString *)outputLine;
{
    TLMPackage *package = [TLMPackage package];

    NSArray *components = [outputLine componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    // !!! early return here after a sanity check
    if ([components count] < 4) {
        TLMLog(@"TLMOutputParser2", @"Unexpected number of tokens in line \"%@\"", outputLine);
        [package setName:NSLocalizedString(@"Error parsing output line", @"")];
        [package setStatus:outputLine];
        [package setFailedToParse:YES];
        return package;
    }
    
    [package setName:[components objectAtIndex:0]];
    
    unichar ch = [[components objectAtIndex:1] characterAtIndex:0];
    [package setStatus:[self _statusStringForCharacter:ch]];
    
    if ('d' == ch)
        [package setWillBeRemoved:YES];
    
    if ('a' != ch)
        [package setCurrentlyInstalled:YES];
    
    if ('u' == ch)
        [package setNeedsUpdate:YES];
    
    if ('f' == ch)
        [package setCurrentlyInstalled:NO];
    
    if (NO == [[components objectAtIndex:2] isEqualToString:@"-"])
        [package setLocalVersion:[components objectAtIndex:2]];
    
    if (NO == [[components objectAtIndex:3] isEqualToString:@"-"])
        [package setRemoteVersion:[components objectAtIndex:3]];
    
    // no placeholder for this one, so check count
    if ([components count] > 4) {
        NSInteger s = [[components objectAtIndex:4] integerValue];
        if (s > 0) 
            [package setSize:[NSNumber numberWithUnsignedInteger:s]];
    }
    
    return package;
}

@end
