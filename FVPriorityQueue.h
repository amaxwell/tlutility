//
//  FVPriorityQueue.h
//  FileView
//
//  Created by Adam Maxwell on 2/9/08.
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

/** @internal @brief Priority queue (ordered set) 
 
 FVPriorityQueue is an ordered collection of unique objects.  Objects are ordered in the queue by priority, as determined by the result of compare: as follows:
 @code
 if ([value1 compare:value2] == NSOrderedDescending), value1 has higher priority
 if ([value1 compare:value2] == NSOrderedAscending), value2 has higher priority
 @endcode
 A twist on usual queue behavior is that duplicate objects (as determined by -[NSObject isEqual:]) are not added to the queue in push:, but are silently ignored.  This allows easy maintenance of a unique set of objects in the priority queue.  Note that -hash must be implemented correctly for any objects that override -isEqual:, and the value of -hash for a given object must not change while the object is in the queue.
 
 Enumeration via NSFastEnumeration or NSEnumerator is performed in queue order (high priority objects are returned before low priority objects).  Selectors invoked via FVPriorityQueue::makeObjectsPerformSelector: are performed in the same order (high priority first).
 
 @warning FVPriorityQueue instances may be shared among threads, but must be protected by a mutex in order to avoid concurrent reads and/or writes (including enumeration).  This may be relaxed in future to allow simultaneous reads.
 
 Thanks to Mike Ash for demonstrating how to use std::make_heap.
 http://www.mikeash.com/?page=pyblog/using-evil-for-good.html
 
 */

#if (MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_5)
@interface FVPriorityQueue : NSObject <NSFastEnumeration>
#else
@interface FVPriorityQueue : NSObject
#endif
{
@private;
    CFMutableSetRef  _set;
    id              *_values;
    NSUInteger       _count;
    NSUInteger       _capacity;
    unsigned long    _mutations;
    BOOL             _madeHeap;
    BOOL             _sorted;
}

/** Designated intializer. */
- (id)init;

/** Single-object access.
 @return The highest priority item; if several items have highest priority, returns any of those items. */
- (id)pop;

/** Single-object insertion.
 @param object The object to add. */
- (void)push:(id)object;

/** Multi-object insertion.
 Semantically equivalent to @code for(object in objects){ [queue push:object]; } @endcode but more efficient and convenient.
 @param objects The collection of objects to add.  Order is ignored. */
- (void)pushMultiple:(NSArray *)objects;

/** Enumeration.
 Objects are returned in descending priority (high priority objects returned first).
 @return An autoreleased enumerator. */
- (NSEnumerator *)objectEnumerator;

/** Operation on the collection.
 The \a selector is invoked on each object in the queue in order of descending priority (high priority first).
 @param selector Selector to invoke. */
- (void)makeObjectsPerformSelector:(SEL)selector;

/** Object count.
 @return The number of objects in the queue. */ 
- (NSUInteger)count;
/** Remove all objects. */
- (void)removeAllObjects;

@end

typedef void (*FVPriorityQueueApplierFunction)(const void *value, void *context);
__private_extern__ void FVPriorityQueueApplyFunction(FVPriorityQueue *theSet, FVPriorityQueueApplierFunction applier, void *context);
