//
//  TLMASLMessage.m
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

#import "TLMASLMessage.h"
#import <asl.h>

@implementation TLMASLMessage

@synthesize date = _date;
@synthesize message = _message;
@synthesize sender = _sender;
@synthesize pid = _pid;
@synthesize level = _level;

- (id)initWithASLMessage:(void *)message
{
    self = [super init];
    if (self) {
        const char *val;
        aslmsg msg = message;
        
        val = asl_get(msg, ASL_KEY_TIME);
        if (NULL == val) val = "0";
        _date = (NSDate *)CFDateCreate(CFAllocatorGetDefault(), strtol(val, NULL, 0) - kCFAbsoluteTimeIntervalSince1970);
        
        val = asl_get(msg, ASL_KEY_SENDER);
        if (NULL == val) val = "Unknown";
        _sender = [[NSString alloc] initWithUTF8String:val];
        
        val = asl_get(msg, ASL_KEY_PID);
        if (NULL == val) val = "-1";
        pid_t pid = strtol(val, NULL, 0);
        _pid = [[NSNumber alloc] initWithInteger:pid];
        
        val = asl_get(msg, ASL_KEY_MSG);
        if (NULL == val) val = "Empty log message";
        _message = [[NSString alloc] initWithUTF8String:val];
        
        val = asl_get(msg, ASL_KEY_LEVEL);
        if (NULL == val) val = "";
        _level = [[NSString alloc] initWithUTF8String:val];        
    }
    return self;
}

- (void)dealloc
{
    [_date release];
    [_sender release];
    [_message release];
    [_pid release];
    [_level release];
    [super dealloc];
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
- (NSString *)description { return [NSString stringWithFormat:@"%@ %@[%d]\t%@", _date, _sender, _pid, _message]; }
- (NSComparisonResult)compare:(TLMASLMessage *)other { return [_date compare:[other date]]; }

@end
