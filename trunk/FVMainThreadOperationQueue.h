//
//  FVMainThreadOperationQueue.h
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
#import "FVOperationQueue.h"
#import <libkern/OSAtomic.h>

@class FVOperation, FVPriorityQueue;

/** @internal @brief Implementation of FVOperationQueue.
 
 @warning FVMainThreadOperationQueue must never be instantiated directly.  It is only used and instantiated by the FVOperationQueue abstract class.  
 
 The following notes may be of interest to FVOperationQueue subclass implementors:  FVMainThreadOperationQueue attaches a CFRunLoopObserver to the main thread for processing queue entries.  Operations are processed while the main thread's runloop is running in the @a FVMainQueueRunLoopMode or any of the modes associated with @a kCFRunLoopCommonModes, and are processed in the @a kCFRunLoopEntry and @a kCFRunLoopBeforeWaiting runloop entry points.  FVMainThreadOperationQueue is thread-safe. */
@interface FVMainThreadOperationQueue : FVOperationQueue
{
@private
    CFRunLoopObserverRef _observer;
    OSSpinLock           _queueLock;
    FVPriorityQueue     *_pendingOperations;
    NSMutableSet        *_activeOperations;  
}
@end
