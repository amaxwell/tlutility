//
//  FVPriorityQueue.m
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

#import "FVPriorityQueue.h"
#include <algorithm>
#include <exception>

@interface FVPriorityQueueEnumerator : NSEnumerator
{
    NSUInteger       _currentIndex;
    NSUInteger       _count;
    FVPriorityQueue *_queue;
}
- (id)initWithQueue:(FVPriorityQueue *)queue;
@end

static inline bool compare(id value1, id value2)
{
    /*
     From testing with NSNumbers, if we want greater values to be returned first (i.e. 10 before 1):
     
     if ([value1 compare:value2] == NSOrderedAscending), value2 has higher priority (return true).
     
     Using NSStrings, this leads to z...a ordering.
     
     if (true) NSCAssert([value2 queuePriority] >= [value1 queuePriority], @"incorrect priority");

     */
    return (NSOrderedAscending == [value1 compare:value2]);
}

// for sorting the heap in priority order (highest priority first)
static inline bool enumeration_compare(id value1, id value2)
{
    return (NSOrderedDescending == [value1 compare:value2]);
}


@implementation FVPriorityQueue

static inline NSUInteger __FVPriorityQueueRoundUpCapacity(NSUInteger capacity) {
    if (capacity < 4) return 4;
#if (MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5)
    return (1 << flsl(capacity));
#else
    return (1 << (int(log2(capacity)) + 1));
#endif
}

static inline void __FVPriorityQueueSetCount(FVPriorityQueue *self, NSUInteger count)
{
    self->_count = count;
}

static inline NSUInteger __FVPriorityQueueCount(FVPriorityQueue *self)
{
    return self->_count;
}

static inline void __FVPriorityQueueSetCapacity(FVPriorityQueue *self, NSUInteger capacity)
{
    self->_capacity = capacity;
}

static inline NSUInteger __FVPriorityQueueCapacity(FVPriorityQueue *self)
{
    return self->_capacity;
}

static void __FVPriorityQueueGrow(FVPriorityQueue *self, NSUInteger numNewValues)
{
    NSUInteger oldCount = __FVPriorityQueueCount(self);
    NSUInteger capacity = __FVPriorityQueueRoundUpCapacity(oldCount + numNewValues);
    __FVPriorityQueueSetCapacity(self, capacity);
    self->_values = (id *)NSZoneRealloc([self zone], self->_values, capacity * sizeof(id));
}

static inline id *__FVPriorityQueueHeapStart(FVPriorityQueue *self)
{
    return self->_values;
}

static inline id *__FVPriorityQueueHeapEnd(FVPriorityQueue *self)
{
    NSUInteger count = __FVPriorityQueueCount(self);
    return &(self->_values[count]);
}

- (id)initWithCapacity:(NSUInteger)capacity;
{
    self = [super init];
    if (self) {
                
        // queue does not retain its objects, so always add/remove from the set last
        
        _set = CFSetCreateMutable(CFAllocatorGetDefault(), 0, &kCFTypeSetCallBacks);
        
        capacity = __FVPriorityQueueRoundUpCapacity(capacity);
        _values = (id *)NSZoneCalloc([self zone], capacity, sizeof(id));
        __FVPriorityQueueSetCount(self, 0);
        __FVPriorityQueueSetCapacity(self, capacity);
        _madeHeap = NO;
        _sorted = NO;
        _mutations = 0;
        
        if (NULL == _values || NULL == _set) {
            if (_set) CFRelease(_set);
            NSZoneFree([self zone], _values);
            [super dealloc];
            self = nil;
        }
        
    }
    return self;
}

- (id)init { return [self initWithCapacity:0]; }

- (void)dealloc
{
    if (_set) CFRelease(_set);
    NSZoneFree([self zone], _values);
    [super dealloc];
}

- (void)push:(id)object;
{ 
    NSParameterAssert([object respondsToSelector:@selector(compare:)]);
    if (CFSetContainsValue(_set, object) == FALSE) {
        CFSetAddValue(_set, object);
        NSUInteger count = __FVPriorityQueueCount(self);
        count++;
        __FVPriorityQueueSetCount(self, count);
        if (count == __FVPriorityQueueCapacity(self))
            __FVPriorityQueueGrow(self, 1);

        _values[count - 1] = object;
        if (_madeHeap)
            std::push_heap(__FVPriorityQueueHeapStart(self), __FVPriorityQueueHeapEnd(self), compare);
        
        _mutations++;
        _sorted = NO;
    }
    NSAssert(self->_count == (NSUInteger)CFSetGetCount(self->_set), @"set and queue must have the same count");
}

- (void)_makeHeap
{
    std::make_heap(__FVPriorityQueueHeapStart(self), __FVPriorityQueueHeapEnd(self), compare);
    _madeHeap = YES;
    _sorted = NO;
    _mutations++;
}

#define FV_STACK_MAX 256

- (void)pushMultiple:(NSArray *)objects;
{
    CFArrayRef cfObjects = reinterpret_cast <CFArrayRef>(objects);
    const CFIndex iMax = CFArrayGetCount(cfObjects);
    CFIndex i, numberAdded = 0;
    
    id stackBuf[FV_STACK_MAX] = { nil };
    id *buffer = NULL;

    if (iMax > FV_STACK_MAX) {
        try {
            buffer = new id[iMax];
        }
        catch (std::bad_alloc&) {
            // !!! early return
            NSLog(@"*** ERROR *** unable to allocate space for %d objects", iMax);
            return;
        }
    }
    else {
        buffer = stackBuf;
    }
    
    NSUInteger count = __FVPriorityQueueCount(self);
    for (i = 0; i < iMax; i++) {
        id object = reinterpret_cast <id>(const_cast <void *>(CFArrayGetValueAtIndex(cfObjects, i)));
        NSParameterAssert([object respondsToSelector:@selector(compare:)]);
        if (CFSetContainsValue(_set, object) == FALSE) {
            CFSetAddValue(_set, object);
            buffer[numberAdded] = object;
            numberAdded++;
        }
    }
    if (numberAdded > 0) {
        
        if ((count + numberAdded) >= __FVPriorityQueueCapacity(self))
            __FVPriorityQueueGrow(self, numberAdded);
        
        id *dest = &_values[count];
        // copy before changing count
        memcpy(dest, buffer, numberAdded * sizeof(id));
        __FVPriorityQueueSetCount(self, count + numberAdded);
        [self _makeHeap];
        
        _mutations++;
    }
    if (stackBuf != buffer) delete buffer;
    NSAssert(self->_count == (NSUInteger)CFSetGetCount(self->_set), @"set and queue must have the same count");
}

- (id)pop;
{ 
    NSUInteger count = __FVPriorityQueueCount(self);    
    id toReturn = nil;

    if (count > 0) {   
        
        // marks as unsorted
        if (NO == _madeHeap)
            [self _makeHeap];

        std::pop_heap(__FVPriorityQueueHeapStart(self), __FVPriorityQueueHeapEnd(self), compare);
        count--;
        __FVPriorityQueueSetCount(self, count);
        toReturn = *(__FVPriorityQueueHeapEnd(self));
        
        // make sure we don't remove the last reference to this object
        toReturn = [[toReturn retain] autorelease];
        CFSetRemoveValue(_set, toReturn);
        
        if (0 == count)
            _madeHeap = 0;
        
        _mutations++;
    }
    NSAssert(self->_count == (NSUInteger)CFSetGetCount(self->_set), @"set and queue must have the same count");
    return toReturn;
}

- (void)removeAllObjects
{
    CFSetRemoveAllValues(_set);
    __FVPriorityQueueSetCount(self, 0);
    _madeHeap = NO;
    _mutations++;
}

- (NSEnumerator *)objectEnumerator
{
    return [[[FVPriorityQueueEnumerator allocWithZone:[self zone]] initWithQueue:self] autorelease];
}

- (void)_sortQueueForEnumeration
{
    // have to call make_heap before sorting
    std::make_heap(__FVPriorityQueueHeapStart(self), __FVPriorityQueueHeapEnd(self), enumeration_compare);
    std::sort_heap(__FVPriorityQueueHeapStart(self), __FVPriorityQueueHeapEnd(self), enumeration_compare);
    
    // sorting the heap loses its heap properties
    _madeHeap = NO;
    _sorted = YES;
    _mutations++;
}

- (void)makeObjectsPerformSelector:(SEL)selector
{
    NSUInteger i, count = __FVPriorityQueueCount(self);    
    [self _sortQueueForEnumeration];
    for (i = 0; i < count; i++)
        [_values[i] performSelector:selector];
}

#if (MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_5)
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)stackbuf count:(NSUInteger)len;
{
    // We keep track of whether the heap is sorted in order to make this method reentrant.
    if (NO == _sorted)
        [self _sortQueueForEnumeration];
        
    // this was taken from CFArray.c
    if (__FVPriorityQueueCount(self) == 0) return 0;
    enum { ATSTART = 0, ATEND = 1 };
    if (ATSTART == state->state) { // first time
        state->state = ATEND;
        state->mutationsPtr = &_mutations;
        state->itemsPtr = __FVPriorityQueueHeapStart(self);
        return __FVPriorityQueueCount(self);
    }
    return 0;
}
#endif

- (NSUInteger)count;
{ 
    NSAssert(self->_count == (NSUInteger)CFSetGetCount(self->_set), @"set and queue must have the same count");
    return __FVPriorityQueueCount(self);
}

void FVPriorityQueueApplyFunction(FVPriorityQueue *queue, FVPriorityQueueApplierFunction applier, void *context)
{
    [queue _sortQueueForEnumeration];
    const void **values = (const void **)__FVPriorityQueueHeapStart(queue);
    CFArrayRef array = CFArrayCreate(CFGetAllocator(queue), values, __FVPriorityQueueCount(queue), NULL);
    CFArrayApplyFunction(array, CFRangeMake(0, CFArrayGetCount(array)), applier, context);
    CFRelease(array);
}

@end

#pragma mark -
#pragma mark FVPriorityQueueEnumerator

@implementation FVPriorityQueueEnumerator

- (id)initWithQueue:(FVPriorityQueue *)queue
{
    self = [super init];
    if (self) {
        _currentIndex = 0;
        _queue = [queue retain];
        _count = [queue count];
        [_queue _sortQueueForEnumeration];
    }
    return self;
}

- (void)dealloc
{
    [_queue release];
    [super dealloc];
}

- (id)nextObject
{
    id obj = nil;
    if (_currentIndex < _count) {
        obj = *(__FVPriorityQueueHeapStart(_queue) + _currentIndex);
        _currentIndex++;
        if (_count == _currentIndex)
            obj = [[obj retain] autorelease];
    }
    return obj;
}

@end

