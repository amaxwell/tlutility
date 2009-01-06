//
//  FVOperationQueue.h
//  FileViewTest
//
//  Created by Adam Maxwell on 09/21/07.
/*
 This software is Copyright (c) 2007-2009
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

@class FVOperation;

/** @file FVOperationQueue.h  Abstract operation queue. */ 

/** \var FVMainQueueRunLoopMode 
 Can use this to run main queue operations in a blocking mode. */
__private_extern__ NSString * const FVMainQueueRunLoopMode;

#define FVOperationQueueDefaultMaxConcurrentOperationCount (-1)

/** Abstract operation queue.
 
 This class declares the interface for an operation queue with similar semantics to NSOperationQueue.  Initializers return an instance of a concrete subclass, never of an FVOperationQueue itself.  FVOperationQueue is thread safe, and instances may be shared between threads with no additional locking, although the client is responsible for keeping a valid reference. */
@interface FVOperationQueue : NSObject

/** Main thread queue.
 
 A shared instance of FVOperationQueue that executes FVOperation::start on the main thread.  Adding operations to this queue is roughly equivalent to using +[NSObject cancelPreviousPerformRequestsWithTarget:selector:object:]/-[NSObject performSelector:withObject:afterDelay:inModes:] with a zero delay and kCFRunLoopCommonModes, but you can add operations from any thread. */
+ (FVOperationQueue *)mainQueue;

/** Designated initializer.  
 
 Returns a queue set up with default parameters.  Call FVOperationQueue::terminate before releasing the last reference to the queue or else it will leak. */
- (id)init;

/** Add operations to the queue.
 
 Operations are coalesced using FVOperation::isEqual.  If you want different behavior, override FVOperation::hash and FVOperation::isEqual: in a subclass.
 @param operations Array of FVOperation objects; order is ignored. */
- (void)addOperations:(NSArray *)operations;

/** Return a snapshot of the operations array.
 
 Primarily for KVO.  This call may be expensive since it has to lock, and is not reentrant. */
- (NSArray *)operations;

/** Count of all pending and executing operations.
 
 Primarily for KVO.  This is significantly cheaper than calling [[queue operations] count]. */
- (NSUInteger)operationCount;

/** Add a single operation to the queue 
 
 Operations are coalesced using FVOperation::isEqual.  If you want different behavior, override FVOperation::hash and FVOperation::isEqual: in a subclass. 
 @param operation An instance of an FVOperation subclass. */
- (void)addOperation:(FVOperation *)operation;

/** Stops any pending or active operations. */
- (void)cancel;
- (void)cancelAllOperations;

/** The queue will be invalid after this call. */
- (void)terminate;

/** Sent after each FVOperation::main completes. 
 
 You will typically never call this directly unless you override FVOperation::finished. */
- (void)finishedOperation:(FVOperation *)anOperation;

/** Set the worker thread's priority.
 
 Calls +[NSThread setThreadPriority:].  Mainly useful for a queue that will be running non-concurrent operations.
 @param p Value between 0.0 and 1.0, where 1.0 is highest priority. */
- (void)setThreadPriority:(double)p;

- (NSInteger)maxConcurrentOperationCount;
- (void)setMaxConcurrentOperationCount:(NSInteger)cnt;



@end
