//
//  TLMASLStore.m
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

#import "TLMASLStore.h"
#import "TLMASLMessage.h"
#import "TLMLogUtilities.h"

NSString * const TLMASLStoreUpdateNotification = @"TLMASLStoreUpdateNotification";

@interface TLMASLQueryOperation : NSOperation
{
@private
    TLMASLStore *_store;
    NSDate      *_date;
}

- (id)initWithStore:(TLMASLStore *)store sinceDate:(NSDate *)date;

@end

@interface TLMASLStore ()
@property (readwrite, copy) NSDate *lastQueryDate;
@end

@implementation TLMASLStore

@synthesize lastQueryDate = _lastQueryDate;
@synthesize messages = _messagesByDate;

+ (void)initialize
{
    [self sharedStore];
}

+ (id)sharedStore;
{
    static id sharedStore = nil;
    if (nil == sharedStore)
        sharedStore = [self new];
    return sharedStore;
}

- (id)init
{
    self = [super init];
    if (self) {
        _queryQueue = [NSOperationQueue new];
        [_queryQueue setMaxConcurrentOperationCount:1];
        _messagesByDate = [NSMutableArray new];
    }
    return self;
}

- (void)dealloc
{
    [_queryQueue cancelAllOperations];
    [_queryQueue release];
    [_messagesByDate release];
    [_lastQueryDate release];
    [super dealloc];
}

- (BOOL)_hasPendingQuery { return [[_queryQueue operations] count] > 0; }

- (void)_startQuery
{
    TLMASLQueryOperation *op = [[TLMASLQueryOperation alloc] initWithStore:self sinceDate:[self lastQueryDate]];
    [_queryQueue addOperation:op];
    [op release];
}

- (void)update;
{
    if ([self _hasPendingQuery] == NO)
        [self _startQuery];
}

- (void)_postNotificationOnMainThread
{
    NSParameterAssert([NSThread isMainThread]);
}

- (void)addMessages:(NSArray *)newMessages
{
    NSParameterAssert([NSThread isMainThread]);
    [_messagesByDate addObjectsFromArray:newMessages];
    [[NSNotificationCenter defaultCenter] postNotificationName:TLMASLStoreUpdateNotification object:self];
}

@end


@implementation TLMASLQueryOperation

- (id)initWithStore:(TLMASLStore *)store sinceDate:(NSDate *)date;
{
    self = [super init];
    if (self) {
        _date = [date copy];
        _store = [store retain];
    }
    return self;
}

- (void)dealloc
{
    [_date release];
    [_store release];
    [super dealloc];
}

- (void)main
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [_store performSelectorOnMainThread:@selector(addMessages:) withObject:TLMASLMessagesSinceDate(_date) waitUntilDone:YES];
    [pool release];
}

@end
