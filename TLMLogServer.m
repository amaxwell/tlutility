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

#import "TLMPreferenceController.h"
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

static NSConnection * __TLMLSCreateAndRegisterConnectionForServer(TLMLogServer *server)
{
    NSConnection *connection = [[NSConnection alloc] initWithReceivePort:[NSPort port] sendPort:nil];
    [connection addRequestMode:NSModalPanelRunLoopMode];
    [connection addRequestMode:NSEventTrackingRunLoopMode];
    [connection setRootObject:[NSProtocolChecker protocolCheckerWithTarget:server protocol:@protocol(TLMLogServerProtocol)]];
    if ([connection registerName:SERVER_NAME] == NO)
        TLMLog(@"TLMLogServer", @"-[TLMLogServer init] Failed to register connection named %@", SERVER_NAME);
    [[NSNotificationCenter defaultCenter] addObserver:server
                                             selector:@selector(_handleConnectionDied:) 
                                                 name:NSConnectionDidDieNotification
                                               object:connection];            
    return connection;
}

- (id)init
{
    self = [super init];
    if (self) {
        _connection = __TLMLSCreateAndRegisterConnectionForServer(self);
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
    // remove self as delegate so we don't get _handleConnectionDied: while terminating
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSConnectionDidDieNotification object:_connection];
    [[NSPortNameServer systemDefaultPortNameServer] removePortForName:SERVER_NAME];
    [[_connection sendPort] invalidate];
    [[_connection receivePort] invalidate];
    [_connection invalidate];
    [_connection release];
    _connection = nil;
}

- (void)_handleConnectionDied:(NSNotification *)aNote
{
    TLMLog(@"TLMLogServer", @"Log server connection died, trying to recreate");
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSConnectionDidDieNotification object:_connection];
    [self _destroyConnection];
    _connection = __TLMLSCreateAndRegisterConnectionForServer(self);
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

- (void)_notifyOnMainThread
{
    NSParameterAssert([NSThread isMainThread]);
    NSNotification *note = [NSNotification notificationWithName:TLMLogServerUpdateNotification object:self];
    [[NSNotificationQueue defaultQueue] enqueueNotification:note
                                               postingStyle:NSPostASAP
                                               coalesceMask:NSNotificationCoalescingOnSender
                                                   forModes:[NSArray arrayWithObject:(id)kCFRunLoopCommonModes]];
}
    
- (void)logMessage:(in bycopy TLMLogMessage *)message;
{
    @synchronized(_messages) {
        [_messages addObject:message];
    }
    NSArray *rlmodes = [[NSArray alloc] initWithObjects:(id *)&kCFRunLoopCommonModes count:1];
    [self performSelectorOnMainThread:@selector(_notifyOnMainThread) withObject:nil waitUntilDone:NO modes:rlmodes];
    [rlmodes release];
    
    // Herb S. requested this so there'd be a record of all messages in one place.
    // If tlmgr_cwrapper fails to connect, it'll start logging to asl, so using this funnel point should be sufficient.
    // Added a pref since setting paper size causes syslog to crap itself.
    if ([[NSUserDefaults standardUserDefaults] boolForKey:TLMUseSyslogPreferenceKey])
        asl_log(NULL, NULL, ASL_LEVEL_ERR, "%s", [[message message] UTF8String]);
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
