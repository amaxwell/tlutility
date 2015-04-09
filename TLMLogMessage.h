//
//  TLMLogMessage.h
//  TeX Live Utility
//
//  Created by Adam Maxwell on 12/12/08.
/*
 This software is Copyright (c) 2008-2015
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

#import <Cocoa/Cocoa.h>

enum {
    TLMLogDefault          = 0,        /* no parsing possible   */
    TLMLogMachineReadable  = (1 << 0), /* message can be parsed */
    TLMLogUpdateOperation  = (1 << 1), /* operation/output type */
    TLMLogInstallOperation = (1 << 2)  /* operation/output type */
};
typedef NSUInteger TLMLogMessageFlags;

@interface TLMLogMessage : NSObject <NSCoding>
{
@private
    NSDate             *_date;
    NSString           *_message;
    NSString           *_sender;
    NSString           *_level;
    pid_t               _pid;  
    uintptr_t           _identifier;
    TLMLogMessageFlags  _flags;
}

- (id)initWithPropertyList:(NSDictionary *)plist;
- (BOOL)matchesSearchString:(NSString *)searchTerm;

@property (readwrite, copy) NSDate *date;
@property (readwrite, copy) NSString *message;
@property (readwrite, copy) NSString *sender;
@property (readwrite, copy) NSString *level;
@property (readwrite) pid_t pid;
@property (readwrite) TLMLogMessageFlags flags;
@property (readonly) NSDictionary *propertyList;
@property (readwrite) uintptr_t identifier;

@end

#define SERVER_NAME @"com.googlecode.mactlmgr.logserver"

@protocol TLMLogServerProtocol <NSObject>
- (void)logMessage:(in bycopy TLMLogMessage *)message;
@end
