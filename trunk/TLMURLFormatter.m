//
//  TLMURLFormatter.m
//  TeX Live Utility
//
//  Created by Adam Maxwell on 12/8/08.
/*
 This software is Copyright (c) 2008-2011
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

#import "TLMURLFormatter.h"


@implementation TLMURLFormatter

@synthesize returnsURL = _returnsURL;

- (NSString *)stringForObjectValue:(id)obj;
{
    return [obj isKindOfClass:[NSURL class]] ? [obj absoluteString] : obj;
}

- (BOOL)getObjectValue:(id *)obj forString:(NSString *)string errorDescription:(NSString **)error;
{
    BOOL success = YES;
    // need to ensure it can be composed, since "ftp://" is a non-nil URL, but is nil after appending a path component
    NSURL *aURL = nil;
    if (string)
        aURL = [[NSURL URLWithString:string] tlm_URLByAppendingPathComponent:@"/a/test/path"];
    if (nil == aURL) {
        success = NO;
        if (error) *error = NSLocalizedString(@"This URL was not valid.", @"error message");
        *obj = nil;
    }
    else if ([aURL scheme] == nil) {
        success = NO;
        if (error) *error = NSLocalizedString(@"This URL is missing a scheme, such as http.", @"error message");
        *obj = nil;        
    }
    else {
        *obj = [self returnsURL] ? [NSURL URLWithString:string] : string;
    }
    return success;
}

@end
