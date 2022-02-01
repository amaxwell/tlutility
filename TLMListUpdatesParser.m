//
//  TLMOutputParser.m
//  TeX Live Utility
//
//  Created by Adam Maxwell on 12/6/08.
/*
 This software is Copyright (c) 2008-2016
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

#import "TLMListUpdatesParser.h"
#import "TLMLogServer.h"

@implementation TLMListUpdatesParser

#pragma mark Update parsing

+ (NSString *)_statusStringForCharacter:(unichar)ch
{
    NSString *status = nil;
    switch (ch) {
        case 'd':
            status = NSLocalizedString(@"Needs removal", @"status for package");
            break;
        case 'u':
            status = NSLocalizedString(@"Update available", @"status for package");
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
 casyl    f    -    -    -
 pageno    d    -    -    -
 arsclassica    a    -    11634    297310
 oberdiek    u    10278    11378    12339256
 
 */

/* max number of columns from original machine-readable output through 2012 */
#define MIN_COLUMNS 5

enum {
    TLMNameIndex             = 0,
    TLMStatusIndex           = 1,
    TLMLocalVersionIndex     = 2,
    TLMRemoteVersionIndex    = 3,
    TLMSizeIndex             = 4,
    /* stuff we ignore */
    TLMRepositoryTag         = 7,
    TLMLocalCatVersionIndex  = 8,
    TLMRemoteCatVersionIndex = 9
};

static NSString * __TLMStringFromComponentsAtIndex(NSArray *components, NSUInteger idx)
{
    NSString *ret = nil;
    if ([components count] > idx) {
        ret = [components objectAtIndex:idx];
        if ([ret isEqualToString:@"-"])
            ret = nil;
    }
    return ret;
}

+ (TLMPackage *)packageWithUpdateLine:(NSString *)outputLine;
{
    TLMPackage *package = [TLMPackage package];
    
    // probably safe to use \t as separator here, but just accept any whitespace
    NSArray *components = [outputLine componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    // !!! early return here after a sanity check
    if ([components count] < MIN_COLUMNS) {
        TLMLog(__func__, @"Too few tokens in line \"%@\"; may be an older tlmgr", outputLine);
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
    
    [package setLocalVersion:__TLMStringFromComponentsAtIndex(components, TLMLocalVersionIndex)];
    
    [package setRemoteVersion:__TLMStringFromComponentsAtIndex(components, TLMRemoteVersionIndex)];
    
    NSInteger s = [__TLMStringFromComponentsAtIndex(components, TLMSizeIndex) integerValue];
    if (s > 0) [package setSize:[NSNumber numberWithUnsignedInteger:s]];
    
    // !!! pinning: add repo name?
    NSString *tag = __TLMStringFromComponentsAtIndex(components, TLMRepositoryTag);
    [package setPinned:(nil != tag && NO == [tag isEqualToString:@"-"] && NO == [tag isEqualToString:@"main"])];
    
    [package setLocalCatalogueVersion:__TLMStringFromComponentsAtIndex(components, TLMLocalCatVersionIndex)];

    [package setRemoteCatalogueVersion:__TLMStringFromComponentsAtIndex(components, TLMRemoteCatVersionIndex)];

    return package;
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

+ (NSArray *)packagesFromListUpdatesOutput:(NSString *)outputString atLocationURL:(NSURL **)actualLocation
{
    // all lines of output
    NSArray *lines = [outputString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    
    // after removing header lines
    NSMutableArray *packageLines = [[lines mutableCopy] autorelease];

    /*
     version 2:
     location-url    http://mirror.hmc.edu/ctan/systems/texlive/tlnet/2008
     total-bytes    216042383
     end-of-header
    */
    NSUInteger headerStopIndex = __TLMIndexOfStringWithPrefix(packageLines, @"end-of-header");
    NSDictionary *header = nil;
    if (NSNotFound != headerStopIndex) {
        header = __TLMHeaderDictionaryWithLines([packageLines subarrayWithRange:NSMakeRange(0, headerStopIndex)]);
        [packageLines removeObjectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, headerStopIndex + 1)]];
    }
    else {
        // saw this happen once (tlmgr returned an error)
        TLMLog(__func__, @"*** ERROR *** header not found in output:\n%@", lines);
        packageLines = nil;
    }

    if ([header objectForKey:@"location-url"]) {
        if (actualLocation)
            *actualLocation = [NSURL URLWithString:[header objectForKey:@"location-url"]];
    }
    else {
        if (actualLocation)
            *actualLocation = nil;
        TLMLog(__func__, @"*** WARNING *** missing location-url in header = %@", header);
    }
    
    // should be the last line in the output, so iterate in reverse order
    NSUInteger outputStopIndex = [packageLines count];
    while (outputStopIndex--) {
        
        // this marker is currently only on the machine-readable code paths, and we don't want to pass it to the parser
        if ([[packageLines objectAtIndex:outputStopIndex] hasPrefix:@"end-of-updates"]) {
            [packageLines removeObjectAtIndex:outputStopIndex];
            break;
        }
    }

    // now we've dealt with the header, so continue on and parse the package lines
    NSMutableArray *packages = [NSMutableArray array];
    NSCharacterSet *nonWhitespace = [[NSCharacterSet whitespaceCharacterSet] invertedSet];
    for (NSString *line in packageLines) {
        if ([line rangeOfCharacterFromSet:nonWhitespace].length)
            [packages addObject:[self packageWithUpdateLine:line]];
    }
    
    return packages;
}

@end

