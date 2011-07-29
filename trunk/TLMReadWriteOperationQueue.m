//
//  TLMReadWriteOperationQueue.m
//  TeX Live Utility
//
//  Created by Adam Maxwell on 01/09/09.
/*
 This software is Copyright (c) 2009-2011
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

#import "TLMReadWriteOperationQueue.h"
#import "TLMOperation.h"

@interface TLMReadWriteOperationQueue ()
@property (readwrite) NSUInteger operationCount;
@property (readwrite) BOOL writing;
@end

#pragma mark -

@implementation TLMReadWriteOperationQueue

@synthesize operationCount = _operationCount;
@synthesize writing = _isWriting;

static char _TLMOperationQueueOperationContext;
static bool _suddenTerminationSupported = false;

+ (void)initialize
{
    static bool didInit = false;
    if (true == didInit) return;
    didInit = true;

    [self defaultQueue];
    if ([NSProcessInfo instancesRespondToSelector:@selector(enableSuddenTermination)] && 
        [NSProcessInfo instancesRespondToSelector:@selector(disableSuddenTermination)])
        _suddenTerminationSupported = true;
}

+ (TLMReadWriteOperationQueue *)defaultQueue;
{
    static id sharedInstance = nil;
    if (nil == sharedInstance)
        sharedInstance = [self new];
    return sharedInstance;
}

- (id)init
{
    self = [super init];
    if (self) {
        _operationQueue = [NSOperationQueue new];
        _pendingOperations = [NSMutableArray new];
        _isWriting = NO;
        _queueLock = [NSLock new];
        [_operationQueue addObserver:self forKeyPath:@"operations" options:0 context:&_TLMOperationQueueOperationContext];
    }
    return self;
}

- (void)dealloc
{
    [_operationQueue removeObserver:self forKeyPath:@"operations"];
    [_operationQueue cancelAllOperations];
    [_operationQueue release];
    [_pendingOperations release];
    [_queueLock release];
    [super dealloc];
}

- (void)cancelAllOperations;
{
    // may callout to KVO
    [_operationQueue cancelAllOperations];
    
    [_queueLock lock];
    [_pendingOperations removeAllObjects];
    [_queueLock unlock];
}

- (void)_dequeueIfNeeded
{
    [_queueLock lock];
    
    // can't do anything or there's nothing left to do...
    if ([self isWriting] || [_pendingOperations count] == 0) {
        [_queueLock unlock];
        return;
    }
    
    NSMutableArray *toAdd = [NSMutableArray array];
    
    // enqueue as many pending operations as possible, but stop at the first writer
    for (TLMOperation *op in _pendingOperations) {
        if ([op isWriter]) {
            // only add a single writer, and never add it alongside another operation
            if ([toAdd count] == 0 && [self operationCount] == 0)
                [toAdd addObject:op];            
            break;
        }
        // not a writer, so add until we hit a reader
        [toAdd addObject:op];
        NSParameterAssert([op isWriter] == NO);
    }
    
    // add anything that can be added
    [_pendingOperations removeObjectsInArray:toAdd];
    
    [_queueLock unlock];

    if ([[toAdd lastObject] isWriter]) {
        NSParameterAssert([toAdd count] == 1);
    }
    
    // may cause callout to KVO
    for (TLMOperation *op in toAdd)
        [_operationQueue addOperation:op];
}

- (void)_updateSuddenTermination:(NSNumber *)isWriting
{
    NSParameterAssert([NSThread isMainThread]);
    if ([isWriting boolValue]) {
        [[NSProcessInfo processInfo] disableSuddenTermination];
        _suddenTerminationDisabled = YES;
    }
    else if (_suddenTerminationDisabled) {
        [[NSProcessInfo processInfo] enableSuddenTermination];
        _suddenTerminationDisabled = NO;
    }
}

- (BOOL)isWriting
{
    BOOL ret;
    @synchronized (self) {
        ret = _isWriting;
    }
    return ret;
}

- (void)setWriting:(BOOL)isWriting
{
    @synchronized (self) {
        if (_suddenTerminationSupported) {
            if ([NSThread isMainThread]) {
                [self _updateSuddenTermination:[NSNumber numberWithBool:isWriting]];
            }
            else {
                [self performSelectorOnMainThread:@selector(_updateSuddenTermination:) withObject:[NSNumber numberWithBool:isWriting] waitUntilDone:NO]; 
            }
        }
        _isWriting = isWriting;
    }
}

// NB: this will arrive on the queue's thread
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == &_TLMOperationQueueOperationContext) {
        NSArray *ops = [[_operationQueue operations] copy];
        [self setOperationCount:[ops count]];
        // only set here
        [self setWriting:([[ops lastObject] isWriter])];
        [ops release];
        [self _dequeueIfNeeded];
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)addOperation:(TLMOperation *)op;
{
    [_queueLock lock];
    [_pendingOperations addObject:op];
    [_queueLock unlock];
    [self _dequeueIfNeeded];
}

@end

