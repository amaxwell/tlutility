//
//  TLMLogServer.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/13/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "TLMLogServer.h"
#import "TLMASLMessage.h"
#import <asl.h>

NSString * const TLMLogServerUpdateNotification = @"TLMLogServerUpdateNotification";
#define SERVER_NAME @"com.googlecode.mactlmgr.logserver"

@protocol TLMLogServer <NSObject>
- (oneway void)logMessage:(in bycopy TLMASLMessage *)message;
@end

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
        [_connection setRootObject:[NSProtocolChecker protocolCheckerWithTarget:self protocol:@protocol(TLMLogServer)]];
        [_connection registerName:SERVER_NAME];
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
    
- (oneway void)logMessage:(in bycopy TLMASLMessage *)message;
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
    
    TLMASLMessage *msg = [[TLMASLMessage alloc] init];
    [msg setDate:[NSDate date]];
    [msg setMessage:message];
    [msg setSender:sender];
    [msg setLevel:@ASL_STRING_ERR];
    [msg setPid:[NSNumber numberWithInteger:getpid()]];
    [[TLMLogServer sharedServer] logMessage:msg];
    [msg release];
    
}
