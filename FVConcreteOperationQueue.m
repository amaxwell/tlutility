//
//  FVConcreteOperationQueue.m
//  FileView
//
//  Created by Adam Maxwell on 2/24/08.
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

#import "FVConcreteOperationQueue.h"
#import "FVOperation.h"
#import "FVInvocationOperation.h"
#import "FVPriorityQueue.h"
#import "FVMainThreadOperationQueue.h"

// for sysctl stuff
#import <sys/types.h>
#import <sys/sysctl.h>

#import <pthread.h>
#import <mach/mach.h>
#import <mach/mach_port.h>

@implementation FVConcreteOperationQueue

// NSConditionLock conditions
enum {
    QUEUE_STARTUP          = 1,
    QUEUE_STARTUP_COMPLETE = 2,
    QUEUE_RUNNING          = 3,
    QUEUE_TERMINATED       = 4
};

// Threading parameters.  20 seems high, but I tried using NSOperationQueue and ended up spawning 70+ threads with no problems.  Most of them just block while waiting for ATS font data (at least in the PDF case), but we could end up with some disk thrash while reading (need to check this).  A recommendation by Chris Kane http://www.cocoabuilder.com/archive/message/cocoa/2008/2/1/197773 indicates that dumping all the operations in the queue and letting the kernel sort out resource allocation is a reasonable approach, since we don't know a prioi which operations will be fast or slow.

static volatile int32_t _activeQueueCount = 0;
static volatile int32_t _activeCPUs = 0;

// Allow a maximum of 10 operations per active CPU core and a minimum of 2 per core; untuned.  Main idea here is to keep from killing performance by creating too many threads or operations, but memory/disk are also big factors that are unaccounted for here.
+ (NSUInteger)_availableOperationCount
{
    int32_t maxConcurrentOperations = _activeCPUs * 10;
    int32_t minConcurrentOperations = 2;    
    return MAX((maxConcurrentOperations - ((_activeQueueCount - 1) * minConcurrentOperations)), minConcurrentOperations);
}

+ (void)_updateKernelInfo:(id)unused
{
    size_t size = sizeof(int32_t);
    int32_t numberOfCPUs = 0;
    
    if (sysctlbyname("hw.ncpu", &numberOfCPUs, &size, NULL, 0) != 0)
        numberOfCPUs = 1; 
    
    if (numberOfCPUs > 1) {
        int32_t activeCPUs;
        if (sysctlbyname("hw.activecpu", &activeCPUs, &size, NULL, 0) == 0)
            numberOfCPUs = activeCPUs;
    }
    OSAtomicCompareAndSwap32Barrier(_activeCPUs, numberOfCPUs, &_activeCPUs);
}

+ (void)initialize
{
    TLMINITIALIZE(FVConcreteOperationQueue);
    
    // update every 10 seconds to see if a processor has been disabled
    [NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(_updateKernelInfo:) userInfo:nil repeats:YES];
    [self _updateKernelInfo:nil];
    NSParameterAssert(_activeCPUs > 0);    
}

- (id)init
{
    self = [super init];
    if (self) {
        
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(handleAppTerminate:) name:NSApplicationWillTerminateNotification object:NSApp];
        
        _concurrent = FVOperationQueueDefaultMaxConcurrentOperationCount;
        
        // this lock protects all of the collection ivars
        _queueLock = OS_SPINLOCK_INIT;
        
        // pending operations
        _pendingOperations = [FVPriorityQueue new];
        
        // running operations
        _activeOperations = [NSMutableSet new];
        
        _threadLock = [[NSConditionLock alloc] initWithCondition:QUEUE_STARTUP];
        
        // Converted to use raw mach ports instead of NSMachPort since I recently noticed that Apple says NSPort isn't thread safe, in spite of the threaded notification processing example that I originally borrowed the NSMachPort code from.  Filed rdar://5772256 in hopes that this will be clarified someday.
        _threadPort = MACH_PORT_NULL;
        
        // this causes a retain cycle, so the owner has to call -terminate to deallocate
        [NSThread detachNewThreadSelector:@selector(_runOperationThread:) toTarget:self withObject:nil];
        
        // block until the port is set up to receive messages, or callbacks won't be delivered properly
        [_threadLock lockWhenCondition:QUEUE_STARTUP_COMPLETE];
        [_threadLock unlockWithCondition:QUEUE_RUNNING];
        
        OSAtomicIncrement32Barrier(&_activeQueueCount);
        
    }
    return self;
}

- (void)dealloc
{
    NSAssert1(1 == _terminate, @"*** ERROR *** attempt to deallocate %@ without calling -terminate", self);
    [_threadLock release];
    [_pendingOperations release];
    [_activeOperations release];
    [super dealloc];
}

- (void)handleAppTerminate:(NSNotification *)aNote
{
    [self terminate];
}

- (void)cancel;
{
    OSSpinLockLock(&_queueLock);
    
    // objects in _pendingOperations queue are waiting to be executed, so just removing is likely sufficient; cancel anyways, just to be safe
    [_pendingOperations makeObjectsPerformSelector:@selector(cancel)];
    [_pendingOperations removeAllObjects];
    
    // these objects are presently executing, and we do not want them to call -finishedOperation: when their thread exits
    [_activeOperations makeObjectsPerformSelector:@selector(cancel)];
    [_activeOperations removeAllObjects];
    
    OSSpinLockUnlock(&_queueLock);
}

- (void)_setThreadPriority:(NSNumber *)p
{
    [NSThread setThreadPriority:[p doubleValue]];
}

- (void)setThreadPriority:(double)p;
{
    NSNumber *val = [NSNumber numberWithDouble:p];
    FVInvocationOperation *op = [[FVInvocationOperation alloc] initWithTarget:self selector:@selector(_setThreadPriority:) object:val];
    // make sure it runs on our worker thread, not some ephemeral thread!
    [op setConcurrent:NO];
    [self addOperation:op];
    [op release];
}

// __CFSendTrivialMachMessage copied from CFRunLoop.c
static uint32_t __FVSendTrivialMachMessage(mach_port_t port, uint32_t msg_id, CFOptionFlags options, uint32_t timeout) {
    kern_return_t result;
    mach_msg_header_t header;
    header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
    header.msgh_size = sizeof(mach_msg_header_t);
    header.msgh_remote_port = port;
    header.msgh_local_port = MACH_PORT_NULL;
    header.msgh_id = msg_id;
    result = mach_msg(&header, MACH_SEND_MSG|options, header.msgh_size, 0, MACH_PORT_NULL, timeout, MACH_PORT_NULL);
    if (result == MACH_SEND_TIMED_OUT) mach_msg_destroy(&header);
    return result;
}

- (void)_wakeThread
{
    kern_return_t ret;
    ret = __FVSendTrivialMachMessage(_threadPort, 0, MACH_SEND_TIMEOUT, 0);
    if (ret != MACH_MSG_SUCCESS && ret != MACH_SEND_TIMED_OUT) {
        // we can ignore MACH_SEND_INVALID_DEST when terminating
        if (MACH_SEND_INVALID_DEST != ret || 1 != _terminate) HALT;
    }
}

- (void)addOperation:(FVOperation *)operation;
{
    [operation setQueue:self];
    [self willChangeValueForKey:@"operations"];
    OSSpinLockLock(&_queueLock);
    [_pendingOperations push:operation];
    OSSpinLockUnlock(&_queueLock);
    [self didChangeValueForKey:@"operations"];
    [self _wakeThread];
}

- (void)addOperations:(NSArray *)operations;
{
    [operations makeObjectsPerformSelector:@selector(setQueue:) withObject:self];
    [self willChangeValueForKey:@"operations"];
    OSSpinLockLock(&_queueLock);
    [_pendingOperations pushMultiple:operations];
    OSSpinLockUnlock(&_queueLock);
    [self didChangeValueForKey:@"operations"];
    [self _wakeThread];
}

- (NSArray *)operations;
{
    NSMutableArray *array = [NSMutableArray array];
    OSSpinLockLock(&_queueLock);
    for (id operation in _activeOperations)
        [array addObject:operation];
    for (id operation in _pendingOperations)
        [array addObject:operation];
    OSSpinLockUnlock(&_queueLock);
    return array;
}

- (NSUInteger)operationCount;
{
    NSUInteger count = 0;
    OSSpinLockLock(&_queueLock);
    count += [_activeOperations count];
    count += [_pendingOperations count];
    OSSpinLockUnlock(&_queueLock);
    return count;
}

- (NSInteger)maxConcurrentOperationCount;
{
    return _concurrent;
}

- (void)setMaxConcurrentOperationCount:(NSInteger)cnt;
{
    NSParameterAssert(cnt < INT32_MAX);
    int32_t new = cnt;
    OSAtomicCompareAndSwap32Barrier(_concurrent, new, &_concurrent);
}

- (NSUInteger)_availableOperationCount
{
    NSInteger count = [[self class] _availableOperationCount];
    // copy to local variable in case it changes before we return
    NSInteger concurrent = _concurrent;
    if (FVOperationQueueDefaultMaxConcurrentOperationCount != concurrent)
        count = MIN(count, concurrent);
    return count;
}

- (void)_startQueuedOperations
{
    OSSpinLockLock(&_queueLock);
    while ([_pendingOperations count] && ([_activeOperations count] < [self _availableOperationCount])) {
        // no KVO notification here; this is essentially a reordering of the operations key
        FVOperation *op = [_pendingOperations pop];
        // Coalescing based on _activeOperations here is questionable, since it's possible that the active operation is stale.
        if (NO == [op isCancelled] && NO == [_activeOperations containsObject:op]) {            
            [_activeOperations addObject:op];
            // avoid a deadlock for a non-threaded operation; -start can trigger -finishedOperation immediately on this thread
            OSSpinLockUnlock(&_queueLock);
            [op start];
            OSSpinLockLock(&_queueLock);
        }        
    }
    OSSpinLockUnlock(&_queueLock);
}

// finishedOperation: callback received on an arbitrary thread
- (void)finishedOperation:(FVOperation *)anOperation;
{
    [self willChangeValueForKey:@"operations"];
    OSSpinLockLock(&_queueLock);
    [_activeOperations removeObject:anOperation];
    OSSpinLockUnlock(&_queueLock);
    [self didChangeValueForKey:@"operations"];
    
    // If the queue didn't flush because too many operations were active, we need to tickle the thread again.
    // ??? will this cause reentrancy of _startQueuedOperations?
    [self _wakeThread];
}

- (void)terminate
{
    OSAtomicDecrement32Barrier(&_activeQueueCount);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self cancel];
    OSAtomicCompareAndSwap32Barrier(0, 1, &_terminate);
    [self _wakeThread];
    [_threadLock lockWhenCondition:QUEUE_TERMINATED];
    [_threadLock unlock];
}

// __CFPortAllocate copied from CFRunLoop.c
static mach_port_t __FVPortAllocate(void) {
    mach_port_t result;
    kern_return_t ret;
    ret = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &result);
    if (KERN_SUCCESS == ret) {
        ret = mach_port_insert_right(mach_task_self(), result, result, MACH_MSG_TYPE_MAKE_SEND);
    }
    if (KERN_SUCCESS == ret) {
        mach_port_limits_t limits;
        limits.mpl_qlimit = 1;
        ret = mach_port_set_attributes(mach_task_self(), result, MACH_PORT_LIMITS_INFO, (mach_port_info_t)&limits, MACH_PORT_LIMITS_INFO_COUNT);
    }
    return (KERN_SUCCESS == ret) ? result : MACH_PORT_NULL;
}

// __CFPortFree copied from CFRunLoop.c
static void __FVPortFree(mach_port_t port) {
    mach_port_destroy(mach_task_self(), port);
}

static mach_port_t __FVGetQueuePort(void *info)
{
    return ((FVConcreteOperationQueue *)info)->_threadPort;
}

static void * __FVQueueMachPerform(void *msg, CFIndex size, CFAllocatorRef allocator, void *info)
{
    [(FVConcreteOperationQueue *)info _startQueuedOperations];
    return NULL;
}

- (void)_runOperationThread:(id)unused;
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    if ([NSThread instancesRespondToSelector:@selector(setName:)])
        [[NSThread currentThread] setName:[NSString stringWithFormat:@"Dedicated thread for %@", self]];
    
    [_threadLock lockWhenCondition:QUEUE_STARTUP];
    
    // pass the queue as info, but don't retain/release it since it will outlive the source
    CFRunLoopSourceContext1 context = { 1, self, NULL, NULL, NULL, NULL, NULL, __FVGetQueuePort, __FVQueueMachPerform };
    _threadPort = __FVPortAllocate();
    
    // CFRunLoop dies if this happens, so do the same
    if (MACH_PORT_NULL == _threadPort) HALT;
    
    CFRunLoopRef rl = CFRunLoopGetCurrent();
    union { 
        CFRunLoopSourceContext c; 
        struct _v1 {
            CFRunLoopSourceContext1 c1; 
            unsigned long padding;
        } v1;
    } ctxt_u;
    ctxt_u.v1.c1 = context;
    CFRunLoopSourceRef source = CFRunLoopSourceCreate(NULL, 0, &ctxt_u.c);
    CFRunLoopAddSource(rl, source, kCFRunLoopDefaultMode);
    CFRelease(source);
    
    [_threadLock unlockWithCondition:QUEUE_STARTUP_COMPLETE];
    [_threadLock lockWhenCondition:QUEUE_RUNNING];
    
    do {
        
        [pool release];
        pool = [NSAutoreleasePool new];
        
        SInt32 result = CFRunLoopRunInMode(kCFRunLoopDefaultMode, 10, TRUE);
        if (kCFRunLoopRunFinished == result || kCFRunLoopRunStopped == result)
            OSAtomicCompareAndSwap32Barrier(0, 1, &_terminate);
        
    } while (0 == _terminate);

    CFRunLoopSourceInvalidate(source);
    mach_port_t port = _threadPort;
    _threadPort = MACH_PORT_NULL;
    __FVPortFree(port);

    [_threadLock unlockWithCondition:QUEUE_TERMINATED];
    [pool release];
}

@end

