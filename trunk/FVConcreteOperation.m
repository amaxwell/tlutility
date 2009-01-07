//
//  FVConcreteOperation.m
//  FileView
//
//  Created by Adam Maxwell on 2/23/08.
/*
 This software is Copyright (c) 2008-2009
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

#import "FVConcreteOperation.h"
#import "FVOperationQueue.h"
#import <libkern/OSAtomic.h>

struct FVOpFlags {
    volatile int32_t _cancelled;
    volatile int32_t _priority;
    volatile int32_t _executing;
    volatile int32_t _finished;
    volatile int32_t _concurrent;
};

@implementation FVConcreteOperation

- (id)init;
{
    self = [super init];
    if (self) {
        _queue = nil;
        _flags = NSZoneCalloc([self zone], 1, sizeof(struct FVOpFlags));
        
        // set this by default
        _flags->_concurrent = 1;
    }
    return self;
}

- (void)dealloc
{
    NSZoneFree([self zone], (void *)_flags);
    [_queue release];
    [super dealloc];
}

- (void)setQueue:(FVOperationQueue *)queue
{
    NSAssert(nil == _queue, @"setQueue: may only be called once");
    _queue = [queue retain];
}

- (FVOperationQueue *)queue { return _queue; }

- (FVOperationQueuePriority)queuePriority;
{
    return _flags->_priority;
}

- (void)setQueuePriority:(FVOperationQueuePriority)queuePriority;
{
    bool didSwap;
    do {
        didSwap = OSAtomicCompareAndSwap32Barrier(_flags->_priority, queuePriority, &(_flags->_priority));
    } while (false == didSwap);
}

- (void)start;
{
    // [super start] performs some validation; we'd have to set _executing bit after that call for async, but before for sync, which is not possible.  Hence, reimplement the whole thing here.
    if ([self isCancelled])
        [NSException raise:NSInternalInconsistencyException format:@"attempt to execute a cancelled operation"];
    if ([self isExecuting] || [self isFinished])
        [NSException raise:NSInternalInconsistencyException format:@"attempt to start a previously executed operation"];
    
    OSAtomicIncrement32Barrier(&(_flags->_executing));
    
    if ([self isConcurrent])
        [NSThread detachNewThreadSelector:@selector(main) toTarget:self withObject:nil];
    else
        [self main];
}

- (void)finished
{
    [super finished];
    OSAtomicIncrement32Barrier(&(_flags->_finished));
}

- (void)cancel;
{
    // allow multiple calls to -cancel
    OSAtomicIncrement32Barrier(&(_flags->_cancelled));
}

- (BOOL)isCancelled;
{
    return 0 != _flags->_cancelled;
}

- (BOOL)isExecuting;
{
    return 1 == _flags->_executing;
}

- (BOOL)isFinished;
{
    return 1 == _flags->_finished;
}

- (BOOL)isConcurrent;
{
    return 1 == _flags->_concurrent;
}

- (void)setConcurrent:(BOOL)flag;
{
    if ([self isCancelled])
        [NSException raise:NSInternalInconsistencyException format:@"attempt to modify a cancelled operation"];
    if ([self isExecuting] || [self isFinished])
        [NSException raise:NSInternalInconsistencyException format:@"attempt to modify a previously executed operation"];
    
    bool didSwap;
    int32_t val = flag ? 1 : 0;
    do {
        didSwap = OSAtomicCompareAndSwap32Barrier(_flags->_concurrent, val, &(_flags->_concurrent));
    } while (false == didSwap);
}

@end
