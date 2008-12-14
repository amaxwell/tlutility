//
//  TLMOutputParser.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/6/08.
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

#import "TLMOutputParser.h"


@implementation TLMOutputParser

+ (TLMPackage *)packageWithOutputLine:(NSString *)outputLine;
{
    NSParameterAssert(nil != outputLine);   
    
    NSString *removePrefix = @"remove ";

    TLMPackage *package = [TLMPackage package];
    
    // e.g. "remove pageno (removed on server)"
    if ([outputLine hasPrefix:removePrefix]) {
        
        // package will be removed by tlmgr update --all
        NSMutableString *mstatus = [NSMutableString stringWithString:outputLine];
        CFStringTrimWhitespace((CFMutableStringRef)mstatus);
        [mstatus deleteCharactersInRange:NSMakeRange(0, [removePrefix length])];
        NSRange r = [mstatus rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
        if (r.length) {
            [package setName:[mstatus substringToIndex:r.location]];
            [package setStatus:NSLocalizedString(@"Needs removal", @"")];
            [package setWillBeRemoved:YES];
            [package setCurrentlyInstalled:YES];
        }
    }
    // e.g. "answers cannot be found in http://mirror.ctan.org/systems/texlive/tlnet/2008"
    else if ([outputLine rangeOfString:@"cannot be found"].length) {
        
        // this is the old version of "removed on server"
        NSRange r = [outputLine rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
        [package setName:[outputLine substringToIndex:r.location]];
        [package setStatus:NSLocalizedString(@"Needs removal", @"")];
        [package setWillBeRemoved:YES];
        [package setCurrentlyInstalled:YES];
    }
    // e.g. "auto-install: pstool"
    else if ([outputLine hasPrefix:@"auto-install:"]) {
        
        // wtf does "auto-install" mean anyway? 
        NSRange r = [outputLine rangeOfString:@"auto-install:"];
        [package setName:[[outputLine substringFromIndex:NSMaxRange(r)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
        [package setStatus:NSLocalizedString(@"Needs install", @"")];
    }
    // e.g. "ifxetex: local: 9906, source: 10831"
    else if ([outputLine rangeOfString:@"local:"].length) {
        
        // package is installed, but needs update
        [package setStatus:NSLocalizedString(@"Needs update", @"")];
        [package setCurrentlyInstalled:YES];
        
        NSScanner *scanner = [[NSScanner alloc] initWithString:outputLine];
        
        NSString *packageName;
        if ([scanner scanUpToString:@":" intoString:&packageName]) {
            [package setName:packageName];
            
            // scan past the colon
            [scanner scanString:@":" intoString:NULL];
        }
        
        if ([scanner scanString:@"local:" intoString:NULL]) {
            NSString *localVersion;
            if ([scanner scanCharactersFromSet:[NSCharacterSet alphanumericCharacterSet] intoString:&localVersion])
                [package setLocalVersion:localVersion];
            
            // scan past the comma
            [scanner scanString:@"," intoString:NULL];
        }
        
        if ([scanner scanString:@"source:" intoString:NULL]) {
            NSString *remoteVersion;
            if ([scanner scanCharactersFromSet:[NSCharacterSet alphanumericCharacterSet] intoString:&remoteVersion])
                [package setRemoteVersion:remoteVersion];
        }
        [scanner release];
    }
    else {
        // major wtf time here...
        [package setName:NSLocalizedString(@"Error parsing package string", @"")];
        [package setStatus:outputLine];
        [package setFailedToParse:YES];
    }
    
    return package;
}

#pragma mark Info parsing

static bool hasKeyPrefix(NSString *line)
{
    NSScanner *scanner = [NSScanner scannerWithString:line];
    [scanner setCharactersToBeSkipped:[NSCharacterSet alphanumericCharacterSet]];
    return ([scanner scanString:@":" intoString:NULL]);
}

+ (NSDictionary *)_infoDictionaryWithString:(NSString *)infoString
{
    NSArray *lines = [infoString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    NSString *key = nil;
    NSMutableString *value = nil;
    for (NSString *line in lines) {

        if (hasKeyPrefix(line)) {
            if (key && value) {
                CFStringTrimWhitespace((CFMutableStringRef)value);
                [dict setObject:value forKey:key];
            }
            value = [NSMutableString string];
            NSRange r = [line rangeOfString:@":"];
            key = [line substringToIndex:r.location];
            [value appendString:[line substringFromIndex:NSMaxRange(r)]];
        }
        else {
            [value appendString:line];
        }
    }
    if (key && value) {
        CFStringTrimWhitespace((CFMutableStringRef)value);
        [dict setObject:value forKey:key];
    }
    return dict;
}

+ (NSAttributedString *)attributedStringWithInfoString:(NSString *)infoString;
{
    NSDictionary *info = [self _infoDictionaryWithString:infoString];
    
    // !!! early return here if parsing fails
    if ([info count] == 0)
        return [[[NSAttributedString alloc] initWithString:infoString] autorelease];
    
    NSMutableAttributedString *attrString = [[NSMutableAttributedString alloc] init];
    
    NSString *value;
    NSUInteger previousLength;
    NSFont *userFont = [NSFont userFontOfSize:0.0];
    NSFont *boldFont = [[NSFontManager sharedFontManager] convertFont:userFont toHaveTrait:NSBoldFontMask];

    value = [info objectForKey:@"Package"];
    if (value) {
        previousLength = [attrString length];
        [[attrString mutableString] appendString:NSLocalizedString(@"Package:", @"")];
        [attrString addAttribute:NSFontAttributeName value:boldFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        
        previousLength = [attrString length];
        [[attrString mutableString] appendFormat:@" %@\n\n", value];
        [attrString addAttribute:NSFontAttributeName value:userFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
    }
    
    value = [info objectForKey:@"ShortDesc"];
    if (value) {
        previousLength = [attrString length];
        [[attrString mutableString] appendString:NSLocalizedString(@"Summary:", @"")];
        [attrString addAttribute:NSFontAttributeName value:boldFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        
        previousLength = [attrString length];
        [[attrString mutableString] appendFormat:@" %@\n\n", value];
        [attrString addAttribute:NSFontAttributeName value:userFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
    }
    
    value = [info objectForKey:@"Installed"];
    if (value) {
        previousLength = [attrString length];
        [[attrString mutableString] appendString:NSLocalizedString(@"Status:", @"")];
        [attrString addAttribute:NSFontAttributeName value:boldFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        if ([value caseInsensitiveCompare:@"yes"] == NSOrderedSame) {
            value = NSLocalizedString(@"Installed", @"");
        }
        else {
            value = NSLocalizedString(@"Not installed", @"");
        }
        previousLength = [attrString length];
        [[attrString mutableString] appendFormat:@" %@\n\n", value];
        [attrString addAttribute:NSFontAttributeName value:userFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
    }
    
    value = [info objectForKey:@"tlmgr"];
    if (value) {
        
        NSRange r = [value rangeOfString:@"installation location "];
        NSURL *linkURL = nil;

        if (r.length)
            linkURL = [NSURL URLWithString:[value substringFromIndex:NSMaxRange(r)]];
        
        if (linkURL) {
            previousLength = [attrString length];
            [[attrString mutableString] appendString:NSLocalizedString(@"Link: ", @"")];
            [attrString addAttribute:NSFontAttributeName value:boldFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        
            previousLength = [attrString length];
            [[attrString mutableString] appendString:[linkURL absoluteString]];
            [attrString addAttribute:NSFontAttributeName value:userFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            [attrString addAttribute:NSLinkAttributeName value:linkURL range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            
            previousLength = [attrString length];
            [[attrString mutableString] appendString:@"\n\n"];
            [attrString removeAttribute:NSLinkAttributeName range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        }
    }
    
    value = [info objectForKey:@"LongDesc"];
    if (value) {
        previousLength = [attrString length];
        [[attrString mutableString] appendString:NSLocalizedString(@"Description:\n", @"")];
        [attrString addAttribute:NSFontAttributeName value:boldFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        
        previousLength = [attrString length];
        [[attrString mutableString] appendFormat:@"%@\n", value];
        [attrString addAttribute:NSFontAttributeName value:userFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
    }
    
    return [attrString autorelease];
}

@end
