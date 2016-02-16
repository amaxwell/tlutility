//
//  TLMLogServer.m
//  TeX Live Utility
//
//  Created by Adam Maxwell on 12/13/08.
/*
 This software is Copyright (c) 2008-2016
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
#import <pthread.h>

NSString * const TLMLogServerUpdateNotification = @"TLMLogServerUpdateNotification";
NSString * const TLMLogTotalProgressNotification = @"TLMLogTotalProgressNotification";
NSString * const TLMLogFinishedProgressNotification = @"TLMLogFinishedProgressNotification";
NSString * const TLMLogDidIncrementProgressNotification = @"TLMLogDidIncrementProgressNotification";
NSString * const TLMLogWillIncrementProgressNotification = @"TLMLogWillIncrementProgressNotification";
NSString * const TLMLogServerSyncNotification = @"TLMLogServerSyncNotification";
NSString * const TLMLogSize = @"TLMLogSize";
NSString * const TLMLogPackageName = @"TLMLogPackageName";
NSString * const TLMLogStatusMessage = @"TLMLogStatusMessage";

@implementation TLMLogServer

@synthesize messages = _messages;

static NSArray *_runLoopModes = nil;

+ (void)initialize
{
    // kCFRunLoopCommonModes doesn't work with NSNotificationQueue on 10.5.x
    NSString *rlmodes[] = { NSDefaultRunLoopMode, NSEventTrackingRunLoopMode, NSModalPanelRunLoopMode };
    if (nil == _runLoopModes)
        _runLoopModes = [[NSArray alloc] initWithObjects:rlmodes count:(sizeof(rlmodes) / sizeof(NSString *))];
}

// Do not use directly!  File scope only because pthread_once doesn't take an argument.
static id _sharedServer = nil;
static void __TLMLogServerInit() { _sharedServer = [TLMLogServer new]; }

+ (TLMLogServer *)sharedServer
{
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    (void) pthread_once(&once, __TLMLogServerInit);
    return _sharedServer;
}

static NSConnection * __TLMLSCreateAndRegisterConnectionForServer(TLMLogServer *server)
{
    NSConnection *connection = [[NSConnection alloc] initWithReceivePort:[NSPort port] sendPort:nil];
    [connection addRequestMode:NSModalPanelRunLoopMode];
    [connection addRequestMode:NSEventTrackingRunLoopMode];
    [connection setRootObject:[NSProtocolChecker protocolCheckerWithTarget:server protocol:@protocol(TLMLogServerProtocol)]];
    if ([connection registerName:SERVER_NAME] == NO)
        NSLog(@"-[TLMLogServer init] Failed to register connection named %@", SERVER_NAME);
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
        _updateClients = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, NULL, &kCFTypeDictionaryValueCallBacks);
    }
    return self;
}

- (void)_destroyConnection
{    
    // remove self as observer so we don't get _handleConnectionDied: while terminating
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSConnectionDidDieNotification object:_connection];
    [_connection registerName:nil];
    [[_connection sendPort] invalidate];
    [[_connection receivePort] invalidate];
    [_connection invalidate];
    [_connection release];
    _connection = nil;
}

- (void)_handleConnectionDied:(NSNotification *)aNote
{
    @synchronized(self) {
        TLMLog(__func__, @"Log server connection died, trying to recreate");
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSConnectionDidDieNotification object:_connection];
        
        // pool to force port invalidation/deallocation now, which allows immediate registration with the same name
        NSAutoreleasePool *pool = [NSAutoreleasePool new];
        [self _destroyConnection];
        [pool release];

        _connection = __TLMLSCreateAndRegisterConnectionForServer(self);
    }
}    

- (void)_handleApplicationTerminate:(NSNotification *)aNote
{
    @synchronized(self) {
        [self _destroyConnection];
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self _destroyConnection];
    [_messages release];
    [_nextNotification release];
    if (_updateClients) CFRelease(_updateClients);
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

- (NSArray *)messagesFromIndex:(NSUInteger)anIndex;
{
    NSArray *messages = nil;
    @synchronized(_messages) {
        NSUInteger count = [_messages count];
        if (anIndex < count)
            messages = [_messages subarrayWithRange:NSMakeRange(anIndex, count - anIndex)];
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
                                                   forModes:_runLoopModes];
}

- (void)_processNextNotification:(NSDictionary *)userInfo
{
    NSParameterAssert([NSThread isMainThread]);
    
    // post the pre-install/update notification
    NSNotification *note = [NSNotification notificationWithName:TLMLogWillIncrementProgressNotification
                                                         object:self
                                                       userInfo:userInfo];
    [[NSNotificationCenter defaultCenter] postNotification:note];
    
    // post the previous install/update notification, which is now a completed operation
    if (_nextNotification)
        [[NSNotificationCenter defaultCenter] postNotification:_nextNotification];

    // now set up the next post-install/update notification
    note = [NSNotification notificationWithName:TLMLogDidIncrementProgressNotification object:self userInfo:userInfo];
    [_nextNotification autorelease];
    _nextNotification = [note retain];
}
    
- (NSString *)_parseMessageAndNotify:(TLMLogMessage *)logMessage
{
    NSString *msg = [logMessage message];      
    NSString *parsedMessage = nil;
    if (([logMessage flags] & TLMLogUpdateOperation) || ([logMessage flags] & TLMLogInstallOperation)) {
        
        NSArray *comps = [msg componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        
        if ([comps count] >= 5) {
            
            // log messages are future tense, since tlmgr notifies before install
            NSString *status = [comps objectAtIndex:1];
            unichar ch = [status length] ? [status characterAtIndex:0] : 0;
            switch (ch) {
                case 'u':
                    status = NSLocalizedString(@"Updating ", @"single trailing space");
                    break;
                case 'a':
                    status = NSLocalizedString(@"Adding ", @"single trailing space");
                    break;
                case 'd':
                    status = NSLocalizedString(@"Deleting ", @"single trailing space");
                    break;
                case 'f':
                    status = NSLocalizedString(@"Forcibly removed ", @"single trailing space");
                    break;
                case 'i':
                    status = NSLocalizedString(@"Installing ", @"single trailing space");
                    break;
                case 'I':
                    status = NSLocalizedString(@"Reinstalling ", @"single trailing space");
                    break;
                case 'r':
                    status = NSLocalizedString(@"Local version is newer ", @"single trailing space");
                    break;
                default:
                    // tlmgr 2008 prints "exiting" here
                    status = [status stringByAppendingString:@" "];
                    TLMLog(__func__, @"Unhandled status \"%@\"", status);
                    break;
            }
            
            // append package name
            parsedMessage = [status stringByAppendingString:[comps objectAtIndex:0]];
            
            NSInteger bytes = [[comps objectAtIndex:4] integerValue];
            // failure to install gives a -1, so avoid underflow
            if (bytes < 0) bytes = 0;
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInteger:(NSUInteger)bytes], TLMLogSize, [comps objectAtIndex:0], TLMLogPackageName, [status stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]], TLMLogStatusMessage, nil];

            /*
             Main thread perform is expensive, but these are fairly low frequency events, and it's not doing much else.
             This is a workaround for tlmgr printing /before/ it installs a package, rather than after.  I need the
             notifications posted after install, or the progress bar doesn't work correctly.
             */
            [self performSelectorOnMainThread:@selector(_processNextNotification:) withObject:userInfo waitUntilDone:NO modes:_runLoopModes];
        }
        else if ([msg hasPrefix:@"total-bytes"]) {
            
            NSInteger totalBytes = [[comps lastObject] integerValue];
            parsedMessage = [NSString stringWithFormat:NSLocalizedString(@"Beginning download of %.1f kbytes", @""), totalBytes / 1024.0];

            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInteger:(NSUInteger)totalBytes] 
                                                                 forKey:TLMLogSize];
            NSNotification *note = [NSNotification notificationWithName:TLMLogTotalProgressNotification
                                                                 object:self
                                                               userInfo:userInfo];
            
            /*
             Again, main thread perform is expensive, but this occurs only once per update.
             This one is synchronous, so the progress indicator can be started immediately;
             otherwise, sometimes the log messages are displayed before the progress bar starts.
             */
            [[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:note waitUntilDone:YES];
        }
        else if ([msg hasPrefix:@"end-of-header"]) {
            
            parsedMessage = NSLocalizedString(@"Beginning download and installation of packages", @"");
        }
        else if ([msg hasPrefix:@"end-of-updates"]) {
            
            parsedMessage = NSLocalizedString(@"Installation complete; reconfiguring TeX Live", @"");
            NSNotification *note = [NSNotification notificationWithName:TLMLogFinishedProgressNotification
                                                                 object:self
                                                               userInfo:nil];
            
            // occurs after all machine-readable output has been printed; make sure we dequeue the last remaining notification
            [self performSelectorOnMainThread:@selector(_processNextNotification:) withObject:nil waitUntilDone:NO modes:_runLoopModes];
            [[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:note waitUntilDone:NO];            
        }
        else {
            // handle location-url and possibly other cases
            parsedMessage = [[msg retain] autorelease];
            if ([msg hasPrefix:@"location-url"] == NO)
                TLMLog(__func__, @"Parser did not recognize message \"%@\"", parsedMessage);
        }
    }
    else {
        TLMLog(__func__, @"Only prepared to parse messages for update operations");
        parsedMessage = [[msg retain] autorelease];
    }
    return parsedMessage;
}

- (id <TLMLogUpdateClient>)_clientForIdentifier:(uintptr_t)ident
{
    return (id)CFDictionaryGetValue(_updateClients, (void *)ident);
}

- (void)registerClient:(id <TLMLogUpdateClient>)obj withIdentifier:(uintptr_t)ident;
{
    NSParameterAssert([obj respondsToSelector:@selector(server:receivedLine:)]);
    NSParameterAssert(0 != ident);
    CFDictionarySetValue(_updateClients, (void *)ident, (const void *)obj);
}

- (void)unregisterClientWithIdentifier:(uintptr_t)ident;
{
    CFDictionaryRemoveValue(_updateClients, (void *)ident);
}

- (void)logMessage:(in bycopy TLMLogMessage *)message;
{
    // if the message is machine readable, parse it and post notifications, then reset the message text for display
    if ([message flags] & TLMLogMachineReadable) {
        // guaranteed to be non-nil if the original message was non-nil
        [message setMessage:[self _parseMessageAndNotify:message]];
    }
    
    [[self _clientForIdentifier:[message identifier]] server:self receivedLine:[message message]];
    
    @synchronized(_messages) {
        [_messages addObject:message];
    }
    
    if ([NSThread isMainThread]) {
        [self _notifyOnMainThread];
    }
    else {
        [self performSelectorOnMainThread:@selector(_notifyOnMainThread) withObject:nil waitUntilDone:NO modes:_runLoopModes];
    }
    
    // Herb S. requested this so there'd be a record of all messages in one place.
    // If tlu_ipctask fails to connect, it'll start logging to asl, so using this funnel point should be sufficient.
    // Added a pref since setting paper size causes syslog to crap itself.
    if ([[NSUserDefaults standardUserDefaults] boolForKey:TLMUseSyslogPreferenceKey])
        asl_log(NULL, NULL, ASL_LEVEL_NOTICE, "%s", [[message message] UTF8String]);
}

- (void)_postSync
{
    NSParameterAssert([[NSThread currentThread] isMainThread]);
    [[NSNotificationCenter defaultCenter] postNotificationName:TLMLogServerSyncNotification object:self];
    // tickle the runloop so we can (hopefully) get the event loop to redisplay windows
    [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantPast]];
}

@end

void TLMLog(const char *sender, NSString *format, ...)
{
    va_list list;
    va_start(list, format);
    NSString *message = [[[NSString alloc] initWithFormat:format arguments:list] autorelease];
    va_end(list);
    
    if (nil == sender) 
        sender = "com.googlecode.mactlmgr";
    
    TLMLogMessage *msg = [[TLMLogMessage alloc] init];
    
    NSDate *date = [NSDate new];
    [msg setDate:date];
    [date release];
    
    [msg setMessage:message];
    NSString *nsSender = [[NSString alloc] initWithUTF8String:sender];
    [msg setSender:nsSender];
    [nsSender release];
    
    // default to notice, since most of the stuff we log is informational
    [msg setLevel:@ASL_STRING_NOTICE];
    [msg setPid:getpid()];
    [[TLMLogServer sharedServer] logMessage:msg];
    [msg release];
    
}

void TLMLogServerSync()
{
    if ([[NSThread currentThread] isMainThread])
        [[TLMLogServer sharedServer] _postSync];
    else
        [[TLMLogServer sharedServer] performSelectorOnMainThread:@selector(_postSync) withObject:nil waitUntilDone:YES];
}
