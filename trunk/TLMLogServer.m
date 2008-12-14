//
//  TLMLogServer.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/13/08.
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

#import "TLMLogServer.h"
#import "TLMLogMessage.h"
#import <asl.h>

NSString * const TLMLogServerUpdateNotification = @"TLMLogServerUpdateNotification";

@implementation TLMLogServer

@synthesize messages = _messages;

+ (id)sharedServer
{
    static id sharedServer = nil;
    if (nil == sharedServer)
        sharedServer = [self new];
    return sharedServer;
}

- (id)init
{
    self = [super init];
    if (self) {
        _connection = [[NSConnection connectionWithReceivePort:[NSPort port] sendPort:nil] retain];
        [_connection addRequestMode:NSModalPanelRunLoopMode];
        [_connection addRequestMode:NSEventTrackingRunLoopMode];
        [_connection setRootObject:[NSProtocolChecker protocolCheckerWithTarget:self protocol:@protocol(TLMLogServer)]];
        if ([_connection registerName:SERVER_NAME] == NO)
            NSLog(@"Failed to register connection named %@", SERVER_NAME);
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(_handleApplicationTerminate:) 
                                                     name:NSApplicationWillTerminateNotification
                                                   object:nil];
        _messages = [NSMutableArray new];
    }
    return self;
}

- (void)_destroyConnection
{
    [[NSPortNameServer systemDefaultPortNameServer] removePortForName:SERVER_NAME];
    [[_connection sendPort] invalidate];
    [[_connection receivePort] invalidate];
    [_connection invalidate];
    [_connection release];
    _connection = nil;
}

- (void)_handleApplicationTerminate:(NSNotification *)aNote
{
    [self _destroyConnection];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self _destroyConnection];
    [_messages release];
    [super dealloc];
}

- (NSArray *)messages
{
    NSArray *messages = nil;
    @synchronized(_messages) {
        messages = [[_messages copy] autorelease];
    }
    return messages;
}
    
- (oneway void)logMessage:(in bycopy TLMLogMessage *)message;
{
    @synchronized(_messages) {
        [_messages addObject:message];
    }
    NSArray *rlmodes = [NSArray arrayWithObjects:NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil];
    NSNotification *notification = [NSNotification notificationWithName:TLMLogServerUpdateNotification object:self];
    [[NSNotificationQueue defaultQueue] enqueueNotification:notification 
                                               postingStyle:NSPostASAP 
                                               coalesceMask:NSNotificationCoalescingOnSender 
                                                   forModes:rlmodes];
}

@end

void TLMLog(NSString *sender, NSString *format, ...)
{
    va_list list;
    va_start(list, format);
    NSString *message = [[[NSString alloc] initWithFormat:format arguments:list] autorelease];
    va_end(list);
    
    if (nil == sender) 
        sender = @"com.googlecode.mactlmgr";
    
    TLMLogMessage *msg = [[TLMLogMessage alloc] init];
    [msg setDate:[NSDate date]];
    [msg setMessage:message];
    [msg setSender:sender];
    [msg setLevel:@ASL_STRING_ERR];
    [msg setPid:[NSNumber numberWithInteger:getpid()]];
    [[TLMLogServer sharedServer] logMessage:msg];
    [msg release];
    
}
