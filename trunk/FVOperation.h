//
//  FVOperation.h
//  FileView
//
//  Created by Adam Maxwell on 2/8/08.
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

/** @file FVOperation.h  Abstract operation. */

enum {
    FVOperationQueuePriorityVeryLow  = -8,
    FVOperationQueuePriorityLow      = -4,
    FVOperationQueuePriorityNormal   =  0,
    FVOperationQueuePriorityHigh     =  4,
    FVOperationQueuePriorityVeryHigh =  8
};
typedef int32_t FVOperationQueuePriority;

/** FVOperation abstract class.
 
 This is an abstract class.  A subclass must override FVOperation::main to actually do work. 
 The lifecycle of an operation goes like this:
 
 - owner does [FVOperationSubclass new]
 - owner adds operation to queue
 - queue checks for uniqueness, and adds the operation to the queue if it's not present
 - queue calls FVOperation::setQueue: with itself as the argument
 - when a task slot is free, the queue calls FVOperation::start and puts the operation in a bag of running tasks
 - when FVOperation::start finishes, the task calls FVOperation::finished
 - FVOperation::finished checks to see if the operation wasn't cancelled, and calls FVOperationQueue::finishedOperation: with self as the argument
 - the queue then releases the operation and it's gone
 
 The queue maintains a set of active oprations so they can be cancelled even when running FVOperation::start (which could prevent callbacks from being invoked in an operation subclass). */
@interface FVOperation : NSObject

/** Designated initializer. */
- (id)init;

/** Hash value.
 
 Subclasses should override hash and isEqual: for correct coalescing semantics.  Default implementation uses pointer equality, so returns the object's address cast to an NSUInteger as hash.
 @return The hash value. */
- (NSUInteger)hash;
/** Equality test.
 
 Subclasses should override hash and isEqual: for correct coalescing semantics.  Default implementation uses pointer equality.
 @return YES if instances are equal as determined by the implementor. */
- (BOOL)isEqual:(id)object;

/** Compares priority.
 
 If receiver's priority is higher than other, returns NSOrderedDescending.  If receiver's priority is lower than other, returns NSOrderedAscending.  If same priority, returns NSOrderedSame.
 @param other The FVOperation to compare against.
 @return The result of the comparison test. */
- (NSComparisonResult)compare:(FVOperation *)other;

/** Starts the operation.
 
 If FVOperation::isConcurrent returns YES, detaches a thread to call FVOperation::main.  If not concurrent, calls FVOperation::main from whatever thread called FVOperation::start.  Raises if the operation was previously cancelled or executed. */
- (void)start;

/** Check to see if the operation is concurrent.
 
 This method returns NO by default for consistency with NSOperation.  Subclasses may override this.
 @return YES if it detaches a new thread in FVOperation::start, NO otherwise. */
- (BOOL)isConcurrent;

/** Notification that an operation is finished.
 
 A subclass must call this when FVOperation::main completes in order to avoid leaking FVOperation instances in the queue. */
- (void)finished;

//
// subclasses must implement all of the following; do not call super
//

/** Sets the FVOperationQueue.
 
 Required for subclassers.  Do not call super.
 @param aQueue The queue that will execute this task. */
- (void)setQueue:(id)aQueue;

/** The queue that will execute the task.
 
 Required for subclassers.  Do not call super.
 @return An instance of FVOperationQueue or nil. */
- (id)queue;

/** Priority of this task.
 
 Required for subclassers.  Do not call super. */

/** Priority of this task.
 
 Required for subclassers.  Do not call super. 
 @return The operation's priority. */
- (FVOperationQueuePriority)queuePriority;

/** Set priority of this task.
 
 Required for subclassers.  Do not call super.
 @param queuePriority An integral value from the FVOperation.h::FVOperationQueuePriority enum. */
- (void)setQueuePriority:(FVOperationQueuePriority)queuePriority;

/** Cancel this task.
 
 Required for subclassers.  Do not call super. */
- (void)cancel;

/** Cancellation status of this task.
 
 Required for subclassers.  Do not call super.
 @return YES if FVOperation::cancel was called previously. */
- (BOOL)isCancelled;

/** Whether the task is running.
 
 Required for subclassers.  Do not call super.
 @return YES if the task is currently executing. */
- (BOOL)isExecuting;

/** Whether the task is finished.
 
 Required for subclassers.  Do not call super.
 @return YES if the task has finished executing. */
- (BOOL)isFinished;

/** Primary work entry point.
 
 Required for subclassers.  Do not call super.
 The operation queue calls this in order to execute the task, if it has not previously been cancelled. */
- (void)main;

/** Change concurrency.
 
 Required for subclassers.  Do not call super.
 This is not part of the NSOperation API, but it's useful.  Raises an exception if the operation was previously cancelled or executed.
 @param flag YES if the operation should detach its own thread to call FVOperation::main. */
- (void)setConcurrent:(BOOL)flag;

@end

/** @typedef int32_t FVOperationQueuePriority 
 Operation queue priority enum.
 */

/** @var FVOperationQueuePriorityVeryLow 
 Lowest priority. 
 */
/** @var FVOperationQueuePriorityLow 
 Low priority.
 */
/** @var FVOperationQueuePriorityNormal 
 Normal priority.
 */
/** @var FVOperationQueuePriorityHigh 
 High priority.
 */
/** @var FVOperationQueuePriorityVeryHigh 
 Highest priority.
 */
