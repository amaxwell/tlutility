//
//  TLMOutputParser2.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/15/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

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
        default:
            TLMLog(@"TLMOutputParser2", @"Unknown status code \"%C\"", ch);
            break;
    }
    return status;
}

+ (TLMPackage *)packageWithOutputLine:(NSString *)outputLine;
{
    TLMPackage *package = [[TLMPackage new] autorelease];

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
    
    if (NO == [[components objectAtIndex:2] isEqualToString:@"-"])
        [package setLocalVersion:[components objectAtIndex:2]];
    
    if (NO == [[components objectAtIndex:3] isEqualToString:@"-"])
        [package setRemoteVersion:[components objectAtIndex:3]];
    
    return package;
}

@end
