//
//  FVInvocationOperation.h
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

#import <Cocoa/Cocoa.h>
#import "FVConcreteOperation.h"
#import <libkern/OSAtomic.h>

/** @internal @brief FVOperation subclass wraps NSInvocation
 
 FVInvocationOperation is designed to be similar in usage to NSInvocationOperation.  It can be created with any invocation, but the invocation should not be modified after the operation has been enqueued.  FVInvocationOperation is capable of returning a value; non-objects are wrapped in an NSValue. */
@interface FVInvocationOperation : FVConcreteOperation
{
@private;
    NSInvocation *_invocation;
    id            _exception;
    void         *_retdata;
    OSSpinLock    _lock;
}

/** Designated initializer. */
- (id)initWithInvocation:(NSInvocation *)inv;
/** Convenience initializer.
 
 This method still creates an NSInvocation, so there's no performance win.
 @param target The target of @a sel.
 @param sel The selector which will be invoked.
 @param arg An optional argument of @a sel.  May be nil.
 @return An initialized operation. */
- (id)initWithTarget:(id)target selector:(SEL)sel object:(id)arg;

/** @return The operation's invocation. */
- (NSInvocation *)invocation;

/** @brief Get the return value.
 
 FVInvocationOperation can be used in a blocking mode if you poll the runloop until FVOperation::isFinished returns YES.  Use @a FVMainQueueRunLoopMode for the main thread queue, or @a NSDefaultRunLoopMode for most other queues:
 @code 
 [[FVOperationQueue mainQueue] addOperation:operation];
 while (NO == [operation isFinished])
    [[NSRunLoop currentRunLoop] runMode:FVMainQueueRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
 @endcode
 @warning This has only undergone limited testing, but is known to work for object and NSRect types.  Test it yourself for others.
 @return The return value of the invocation.  If this is not an object, it will be wrapped in an NSValue. */
- (id)result;

@end
