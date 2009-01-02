//
//  TLMOutputParser2.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/15/08.
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

#import "TLMOutputParser2.h"
#import "TLMPackage.h"
#import "TLMLogServer.h"

@implementation TLMOutputParser2

+ (NSString *)_statusStringForCharacter:(unichar)ch
{
    NSString *status = nil;
    switch (ch) {
        case 'd':
            status = NSLocalizedString(@"Deleted on server", @"status for package");
            break;
        case 'u':
            status = NSLocalizedString(@"Updated on server", @"status for package");
            break;
        case 'a':
            status = NSLocalizedString(@"Not installed", @"status for package");
            break;
        case 'f':
            status = NSLocalizedString(@"Forcibly removed", @"status for package");
            break;
        case 'r':
            status = NSLocalizedString(@"Local version is newer", @"status for package");
            break;
        default:
            TLMLog(__func__, @"Unknown status code \"%C\"", ch);
            break;
    }
    return status;
}

/*
 froude:tmp amaxwell$ tlmgr2 --machine-readable update --list 2>/dev/null
 ...
 casyl	f	-	-	-
 pageno	d	-	-	-
 arsclassica	a	-	11634	297310
 oberdiek	u	10278	11378	12339256
 
*/

#define MAX_COLUMNS 5

enum {
    TLMNameIndex          = 0,
    TLMStatusIndex        = 1,
    TLMLocalVersionIndex  = 2,
    TLMRemoteVersionIndex = 3,
    TLMSizeIndex          = 4
};

+ (TLMPackage *)packageWithUpdateLine:(NSString *)outputLine;
{
    TLMPackage *package = [TLMPackage package];

    // probably safe to use \t as separator here, but just accept any whitespace
    NSArray *components = [outputLine componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    // !!! early return here after a sanity check
    if ([components count] < MAX_COLUMNS) {
        TLMLog(__func__, @"Unexpected number of tokens in line \"%@\"", outputLine);
        [package setName:NSLocalizedString(@"Error parsing output line", @"error message for unreadable package")];
        [package setStatus:outputLine];
        [package setFailedToParse:YES];
        return package;
    }
    
    [package setName:[components objectAtIndex:TLMNameIndex]];
    
    unichar ch = [[components objectAtIndex:TLMStatusIndex] characterAtIndex:0];
    [package setStatus:[self _statusStringForCharacter:ch]];
    
    if ('d' == ch)
        [package setWillBeRemoved:YES];
    
    if ('a' != ch)
        [package setInstalled:YES];
    
    if ('u' == ch)
        [package setNeedsUpdate:YES];
    
    if ('f' == ch)
        [package setWasForciblyRemoved:YES];
        
    if (NO == [[components objectAtIndex:TLMLocalVersionIndex] isEqualToString:@"-"])
        [package setLocalVersion:[components objectAtIndex:TLMLocalVersionIndex]];
    
    if (NO == [[components objectAtIndex:TLMRemoteVersionIndex] isEqualToString:@"-"])
        [package setRemoteVersion:[components objectAtIndex:TLMRemoteVersionIndex]];
    
    if (NO == [[components objectAtIndex:TLMSizeIndex] isEqualToString:@"-"]) {
        NSInteger s = [[components objectAtIndex:TLMSizeIndex] integerValue];
        if (s > 0) [package setSize:[NSNumber numberWithUnsignedInteger:s]];
    }
    
    return package;
}

@end
