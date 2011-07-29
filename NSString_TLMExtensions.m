//
//  NSString_TLMExtensions.m
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 06/07/11.
/*
 This software is Copyright (c) 2011
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

#import "NSString_TLMExtensions.h"


@implementation NSString (TLMExtensions)

+ (NSString *)stringWithFileSystemRepresentation:(const char *)cstr;
{
    if (NULL == cstr) return nil;
    if (strlen(cstr) == 0) return @"";
    
    NSString *str = [(NSString *)CFStringCreateWithFileSystemRepresentation(CFAllocatorGetDefault(), cstr) autorelease];
    if (nil == str)
        [NSException raise:NSInvalidArgumentException format:@"Unable to convert string from file system representation: %s", cstr];
    return str;
}

- (const char *)saneFileSystemRepresentation;
{    
    // workaround for rdar://problem/9565599
    CFIndex len = CFStringGetMaximumSizeOfFileSystemRepresentation((CFStringRef)self);
    NSMutableData *mdata = [[[NSMutableData allocWithZone:[self zone]] initWithLength:len] autorelease];
    if (CFStringGetFileSystemRepresentation((CFStringRef)self, [mdata mutableBytes], len) == FALSE) {
        mdata = nil;
        [NSException raise:NSInvalidArgumentException format:@"Unable to convert string to file system representation: %@", self];
    }
    [mdata setLength:(strlen([mdata bytes]) + 1)];
    return [mdata bytes];
}

- (NSComparisonResult)localizedCaseInsensitiveNumericCompare:(NSString *)aStr;
{
    return [self compare:aStr
                 options:NSCaseInsensitiveSearch | NSNumericSearch
                   range:NSMakeRange(0, [self length])
                  locale:[NSLocale currentLocale]];
}

@end
