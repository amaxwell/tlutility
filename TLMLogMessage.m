//
//  TLMLogMessage.m
//  TeX Live Utility
//
//  Created by Adam Maxwell on 12/12/08.
/*
 This software is Copyright (c) 2008-2012
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

#import "TLMLogMessage.h"

@implementation TLMLogMessage

@synthesize date = _date;
@synthesize message = _message;
@synthesize sender = _sender;
@synthesize pid = _pid;
@synthesize level = _level;
@synthesize flags = _flags;
@synthesize operationAddress = _operationAddress;

- (void)dealloc
{
    [_date release];
    [_sender release];
    [_message release];
    [_level release];
    [super dealloc];
}

// only encoded by NSPortCoder, which doesn't support key/value coding
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_date];
    [coder encodeObject:_message];
    [coder encodeObject:_sender];
    [coder encodeObject:_level];
    /*
     Encode objects since old-style coding doesn't support primitive types directly,
     and I don't want to worry about endianness (which should not be a problem on
     the same host...but still).
     */
    [coder encodeObject:[NSNumber numberWithUnsignedLong:_operationAddress]];
    [coder encodeObject:[NSNumber numberWithUnsignedInteger:_pid]];
    [coder encodeObject:[NSNumber numberWithUnsignedInteger:_flags]];
}

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (self) {
        _date = [[coder decodeObject] copy];
        _message = [[coder decodeObject] copy];
        _sender = [[coder decodeObject] copy];
        _level = [[coder decodeObject] copy];
        _operationAddress = [[coder decodeObject] unsignedLongValue];
        _pid = [[coder decodeObject] unsignedIntegerValue];
        _flags = [[coder decodeObject] unsignedIntegerValue];
    }
    return self;
}

- (id)initWithPropertyList:(NSDictionary *)plist
{
    self = [super init];
    if (self) {
        _date = [[plist objectForKey:@"_date"] copy];
        _message = [[plist objectForKey:@"_message"] copy];
        _sender = [[plist objectForKey:@"_sender"] copy];
        _level = [[plist objectForKey:@"_level"] copy];
        _pid = [[plist objectForKey:@"_pid"] unsignedIntegerValue];
        _flags = [[plist objectForKey:@"_flags"] unsignedIntegerValue];
    }
    return self;
}

- (id)replacementObjectForPortCoder:(NSPortCoder *)encoder
{
    return [encoder isByref] ? (id)[NSDistantObject proxyWithLocal:self connection:[encoder connection]] : (id)self;
}

- (id)propertyList
{
    NSMutableDictionary *plist = [NSMutableDictionary dictionary];
    [plist setObject:_date forKey:@"_date"];
    [plist setObject:_message forKey:@"_message"];
    [plist setObject:_sender forKey:@"_sender"];
    [plist setObject:_level forKey:@"_level"];
    [plist setObject:[NSNumber numberWithUnsignedInteger:_pid] forKey:@"_pid"];
    [plist setObject:[NSNumber numberWithUnsignedInteger:_flags] forKey:@"_flags"];
    return plist;
}

- (NSUInteger)hash { return [_date hash]; }

- (id)operation
{
    /*
     NSZoneFromPointer ensures that we won't try and dereference a pointer in 
     the wrong process, but doesn't ensure that it's a valid object. This is
     a weak reference if there ever was one.
     */
    return NSZoneFromPointer((void *)[self operationAddress]) ? (id)[self operationAddress] : nil;
}

- (BOOL)isEqual:(id)other
{
    if ([other isKindOfClass:[self class]] == NO)
        return NO;
    if ([other pid] != _pid)
        return NO;
    if ([[other message] isEqualToString:_message] == NO)
        return NO;
    if ([(NSString *)[other sender] isEqualToString:_sender] == NO)
        return NO;
    if ([[other date] compare:_date] != NSOrderedSame)
        return NO;
    return YES;
}
- (NSString *)description { return [NSString stringWithFormat:@"%@ %@ %@[%lu]\t%@", _date, _level, _sender, (unsigned long)_pid, _message]; }
- (NSComparisonResult)compare:(TLMLogMessage *)other { return [_date compare:[other date]]; }
- (BOOL)matchesSearchString:(NSString *)searchTerm { return [[self description] rangeOfString:searchTerm options:NSCaseInsensitiveSearch].length; }

@end
