//
//  TLMLogServer.h
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

#import <Cocoa/Cocoa.h>

// posted on the main thread
extern NSString * const TLMLogServerUpdateNotification;

// posted on the main thread; request to immediately update log display services
extern NSString * const TLMLogServerSyncNotification;

// progress notifications posted on the main thread
extern NSString * const TLMLogTotalProgressNotification;         // posted to begin deterministic progress updates
extern NSString * const TLMLogDidIncrementProgressNotification;  // posted with number of bytes since previous update
extern NSString * const TLMLogWillIncrementProgressNotification; // posted with number of bytes in next update
extern NSString * const TLMLogFinishedProgressNotification;      // no userInfo; posted when further progress is unknown

// userInfo key in progress notifications (size in bytes as NSNumber)
extern NSString * const TLMLogSize;
extern NSString * const TLMLogPackageName;
extern NSString * const TLMLogStatusMessage;

@protocol TLMLogUpdateClient;

@interface TLMLogServer : NSObject 
{
@private
    NSMutableArray         *_messages;
    NSConnection           *_connection;
    NSNotification         *_nextNotification;
    CFMutableDictionaryRef  _updateClients;
}

+ (TLMLogServer *)sharedServer;

// returns messages in range (anIndex, end) or nil if anIndex is out of range
- (NSArray *)messagesFromIndex:(NSUInteger)anIndex;

- (void)registerClient:(id <TLMLogUpdateClient>)obj withIdentifier:(uintptr_t)ident;
- (void)unregisterClientWithIdentifier:(uintptr_t)ident;

// returns a snapshot of all messages
@property(readonly, retain) NSArray *messages;

@end

@protocol TLMLogUpdateClient <NSObject>
- (void)server:(TLMLogServer *)server receivedLine:(NSString *)msg;
@end

__BEGIN_DECLS
extern void TLMLog(const char *sender, NSString *format, ...) NS_FORMAT_FUNCTION(2,3);
// force an update of the log display clients; use sparingly
extern void TLMLogServerSync(void);
__END_DECLS

