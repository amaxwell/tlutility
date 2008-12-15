//
//  TLMLogMessage.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/12/08.
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

#import "TLMLogMessage.h"

@implementation TLMLogMessage

@synthesize date = _date;
@synthesize message = _message;
@synthesize sender = _sender;
@synthesize pid = _pid;
@synthesize level = _level;

- (void)dealloc
{
    [_date release];
    [_sender release];
    [_message release];
    [_pid release];
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
    [coder encodeObject:_pid];
}

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (self) {
        _date = [[coder decodeObject] copy];
        _message = [[coder decodeObject] copy];
        _sender = [[coder decodeObject] copy];
        _level = [[coder decodeObject] copy];
        _pid = [[coder decodeObject] copy];
    }
    return self;
}

- (id)replacementObjectForPortCoder:(NSPortCoder *)encoder
{
    return [encoder isByref] ? (id)[NSDistantObject proxyWithLocal:self connection:[encoder connection]] : (id)self;
}

- (NSUInteger)hash { return [_date hash]; }

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
- (NSString *)description { return [NSString stringWithFormat:@"%@ %@ %@[%@]\t%@", _date, _level, _sender, _pid, _message]; }
- (NSComparisonResult)compare:(TLMLogMessage *)other { return [_date compare:[other date]]; }

@end
