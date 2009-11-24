//
//  BDSKTask.m
//  Bibdesk
//
//  Created by Adam Maxwell on 8/25/08.
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

#import "BDSKTask.h"
#import <libkern/OSAtomic.h>
#import <crt_externs.h>
#import <sys/types.h>
#import <sys/event.h>
#import <sys/time.h>
#import <sys/resource.h>
#import <pthread.h>

@interface BDSKTask (Private)

+ (void)_watchQueue;
- (void)_taskSignaled;
- (void)_disableNotification;
- (void)_taskExited;

@end

struct BDSKTaskInternal {
    int32_t            _terminationStatus;
    int32_t            _running;
    int32_t            _launched;
    int32_t            _canNotify;
    struct kevent      _event;
    CFRunLoopRef       _rl;
    CFRunLoopSourceRef _rlsource;
    pthread_mutex_t    _lock;
};

@implementation BDSKTask

static int _kqueue = -1;

+ (void)initialize
{
    if ([BDSKTask class] != self) return;
    _kqueue = kqueue();
    // persistent thread to watch all tasks
    [NSThread detachNewThreadSelector:@selector(_watchQueue) toTarget:self withObject:nil];
}

+ (BDSKTask *)launchedTaskWithLaunchPath:(NSString *)path arguments:(NSArray *)arguments;
{
    BDSKTask *task = [[self new] autorelease];
    [task setLaunchPath:path];
    [task setArguments:arguments];
    [task launch];
    return task;
}

#define ASSERT_LAUNCH do { if (!_internal->_launched) { [NSException raise:@"BDSKTaskException" format:@"Task has not been launched"]; } } while (0)
#define ASSERT_NOTLAUNCHED do { if (_internal->_launched) { [NSException raise:@"BDSKTaskException" format:@"Task has already been launched"]; } } while (0)

- (id)init
{
    self = [super init];
    if (self) {
        _internal = NSZoneCalloc([self zone], 1, sizeof(struct BDSKTaskInternal));
        memset(&_internal->_event, 0, sizeof(struct kevent));
        pthread_mutex_init(&_internal->_lock, NULL);
        _internal->_canNotify = 1;
    }
    return self;
}

- (void)dealloc
{
    /*
     Set _canNotify in case kevent unblocks before we can remove it from the queue,
     since the event's task pointer is about to become invalid (and it mustn't access
     the lock after this flag is set).  Lock before entering _disableNotification, so 
     we can shrink our race window even smaller.
     */
    OSAtomicCompareAndSwap32Barrier(1, 0, &_internal->_canNotify);
    pthread_mutex_lock(&_internal->_lock);
    [self _disableNotification];
    pthread_mutex_unlock(&_internal->_lock);
    pthread_mutex_destroy(&_internal->_lock);
    [_launchPath release];
    [_arguments release];
    [_environment release];
    [_currentDirectoryPath release];
    [_standardInput release];
    [_standardOutput release];
    [_standardError release];
    // runloop and source are freed in __BDSKTaskNotify or _disableNotification
    NSParameterAssert(NULL == _internal->_rl);
    NSParameterAssert(NULL == _internal->_rlsource);
    NSZoneFree(NSZoneFromPointer(_internal), _internal);
    [super dealloc];
}

- (void)setLaunchPath:(NSString *)path;
{
    ASSERT_NOTLAUNCHED;
    [_launchPath autorelease];
    _launchPath = [path copy];
}

- (void)setArguments:(NSArray *)arguments;
{
    ASSERT_NOTLAUNCHED;
    [_arguments autorelease];
    _arguments = [arguments copy];
}

- (void)setEnvironment:(NSDictionary *)dict;
{
    ASSERT_NOTLAUNCHED;
    [_environment autorelease];
    _environment = [dict copy];
}

- (void)setCurrentDirectoryPath:(NSString *)path;
{
    ASSERT_NOTLAUNCHED;
    [_currentDirectoryPath autorelease];
    _currentDirectoryPath = [path copy];
}

// set standard I/O channels; may be either an NSFileHandle or an NSPipe
- (void)setStandardInput:(id)input;
{
    ASSERT_NOTLAUNCHED;
    [_standardInput autorelease];
    _standardInput = [input retain];
}

- (void)setStandardOutput:(id)output;
{
    ASSERT_NOTLAUNCHED;
    [_standardOutput autorelease];
    _standardOutput = [output retain];
}

- (void)setStandardError:(id)error;
{
    ASSERT_NOTLAUNCHED;
    [_standardError autorelease];
    _standardError = [error retain];
}

// get parameters
- (NSString *)launchPath; { return _launchPath; }
- (NSArray *)arguments; { return _arguments; }
- (NSDictionary *)environment; { return _environment; }
- (NSString *)currentDirectoryPath; { return _currentDirectoryPath; }

// get standard I/O channels; could be either an NSFileHandle or an NSPipe
- (id)standardInput; { return _standardInput; }
- (id)standardOutput; { return _standardOutput; }
- (id)standardError; { return _standardError; }

static void __BDSKTaskNotify(void *info)
{
    // note: we have a hard retain at this point, so -dealloc and _disableNotification can't be called
    BDSKTask *task = info;    
    [[NSNotificationCenter defaultCenter] postNotificationName:NSTaskDidTerminateNotification object:task];    
    
    pthread_mutex_lock(&task->_internal->_lock);
    
    // source is retained by the runloop; invalidate it and then make sure we no longer have a reference
    CFRunLoopSourceInvalidate(task->_internal->_rlsource);
    task->_internal->_rlsource = NULL;
    
    // release the task's reference to the runloop and clear it
    NSCParameterAssert(NULL != task->_internal->_rl);
    if (task->_internal->_rl) {
        CFRelease(task->_internal->_rl);
        task->_internal->_rl = NULL;
    }
    pthread_mutex_unlock(&task->_internal->_lock);
    
    // balance additional retain in _taskExited
    [task release];
}

- (void)launch;
{
    ASSERT_NOTLAUNCHED;
    
    NSUInteger argCount = [_arguments count];
    const char *workingDir = [_currentDirectoryPath fileSystemRepresentation];
    char **args = NSZoneCalloc([self zone], (argCount + 2), sizeof(char *));
    NSUInteger i, iMax = argCount;
    args[0] = (char *)[_launchPath fileSystemRepresentation];
    for (i = 0; i < iMax; i++) {
        args[i + 1] = (char *)[[_arguments objectAtIndex:i] fileSystemRepresentation];
    }
    args[argCount + 1] = NULL;
    
    char ***nsEnvironment = _NSGetEnviron();
    char **env = *nsEnvironment;
    
    NSDictionary *environment = [self environment];
    if (environment) {
        // fill with pointers to autoreleased C strings
        env = NSZoneCalloc([self zone], [environment count] + 1, sizeof(char *));
        NSString *key;
        NSUInteger envIndex = 0;
        for (key in environment) {
            env[envIndex++] = (char *)[[NSString stringWithFormat:@"%@=%@", key, [environment objectForKey:key]] UTF8String];        
        }
        env[envIndex] = NULL;
    }
    
    // fileHandleWithNullDevice returns a descriptor of -1, so use fd_null instead
    int fd_out = -1, fd_inp = -1, fd_err = -1, fd_null = open("/dev/null", O_RDWR);
    id fh = nil;
    
    // the end of a pipe passed to the child needs to be closed in the parent process
    NSMutableSet *handlesToClose = [NSMutableSet new];
    
    fh = [self standardInput];
    if ([fh isKindOfClass:[NSPipe class]]) {
        [handlesToClose addObject:[fh fileHandleForReading]];
        fd_inp = [[fh fileHandleForReading] fileDescriptor];
    }
    else if (nil != fh) {
        fd_inp = [fh isEqual:[NSFileHandle fileHandleWithNullDevice]] ? fd_null : [fh fileDescriptor];
    }
    
    fh = [self standardOutput];
    if ([fh isKindOfClass:[NSPipe class]]) {
        [handlesToClose addObject:[fh fileHandleForWriting]];
        fd_out = [[fh fileHandleForWriting] fileDescriptor];
    }
    else if (nil != fh) {
        fd_out = [fh isEqual:[NSFileHandle fileHandleWithNullDevice]] ? fd_null : [fh fileDescriptor];
    }
    
    fh = [self standardError];
    if ([fh isKindOfClass:[NSPipe class]]) {
        [handlesToClose addObject:[fh fileHandleForWriting]];
        fd_err = [[fh fileHandleForWriting] fileDescriptor];
    }
    else if (nil != fh) {
        fd_err = [fh isEqual:[NSFileHandle fileHandleWithNullDevice]] ? fd_null : [fh fileDescriptor];
    }
    
    // avoid a race between exec and setting up our kqueue
    int blockpipe[2] = { -1, -1 };
    if (pipe(blockpipe))
        perror("failed to create blockpipe");
    
    /*
     Figure out the max number of file descriptors for a process; getrlimit is not listed as
     async-signal safe in the sigaction(2) man page, so we assume it's not safe to call after 
     fork().  The fork(2) page says that child rlimits are set to zero.
     */
    rlim_t maxOpenFiles = OPEN_MAX;
    struct rlimit openFileLimit;
    if (getrlimit(RLIMIT_NOFILE, &openFileLimit) == 0)
        maxOpenFiles = openFileLimit.rlim_cur;
    
    // !!! No CF or Cocoa after this point in the child process!
    _processIdentifier = fork();
    
    if (0 == _processIdentifier) {
        // child process
        
        // set process group for killpg()
        (void)setpgid(getpid(), getpid());
        
        // setup stdio descriptors (if not inheriting from parent)
        if (-1 != fd_inp) dup2(fd_inp, STDIN_FILENO);        
        if (-1 != fd_out) dup2(fd_out, STDOUT_FILENO);
        if (-1 != fd_err) dup2(fd_err, STDERR_FILENO);  
        
        if (workingDir) chdir(workingDir);
        
        /*         
         Unfortunately, a side effect of blocking on a pipe is that other processes inherit our blockpipe
         descriptors as well.  Consequently, if taskB calls fork() while taskA is still setting up its
         kevent, taskB inherits the pipe for taskA, and taskA will never launch since taskB doesn't close
         them.  This was a very confusing race to debug, and it resulted in a bunch of orphaned child
         processes.
         
         Using a class-scope lock is one possible solution, but NSTask doesn't use that log, and subclasses
         that override -launch would also not benefit from locking (e.g., TLMTask).  Since TLMTask sets up
         NSPipes in -launch before calling -[super launch], those pipes and any created by Cocoa would not
         be protected by that lock.  Closing all remaining file descriptors doesn't break any documented 
         behavior of NSTask, and it should take care of that problem.  It's not a great solution, since 
         inheriting other descriptors could possibly be useful, but I don't need to share arbitrary file 
         descriptors, whereas I do need subclassing and threads to work properly.
         */
        rlim_t j;
        for (j = (STDERR_FILENO + 1); j < maxOpenFiles; j++) {
            
            // don't close this until we're done reading from it!
            if ((unsigned)blockpipe[0] != j)
                (void) close(j);
        }
        
        char ignored;
        // block until the parent has setup complete
        read(blockpipe[0], &ignored, 1);
        close(blockpipe[0]);
        
        int ret = execve(args[0], args, env);
        _exit(ret);
    }
    else if (-1 == _processIdentifier) {
        // parent: error
        perror("fork() failed");
        _internal->_terminationStatus = 2;
    }
    else {        
        // parent process
        
        // CASB probably not necessary anymore...
        OSAtomicCompareAndSwap32Barrier(0, 1, &_internal->_running);
        OSAtomicCompareAndSwap32Barrier(0, 1, &_internal->_launched);
        
        // NSTask docs say that these descriptors are closed in the parent task; required to make pipes work properly
        [handlesToClose makeObjectsPerformSelector:@selector(closeFile)];
        
        if (-1 != fd_null) close(fd_null);
        
        /*
         The kevent will have a weak reference to this task, so -dealloc can occur without waiting for notification.
         This behavior is documented for NSTask, presumably so you can fire it off and not have any resources hanging
         around after the exec.
         */
        EV_SET(&_internal->_event, _processIdentifier, EVFILT_PROC, EV_ADD, NOTE_EXIT | NOTE_SIGNAL, 0, self);
        kevent(_kqueue, &_internal->_event, 1, NULL, 0, NULL);      
        
        // use a runloop source to ensure that the notification is posted on the correct thread
        _internal->_rl = (CFRunLoopRef)CFRetain(CFRunLoopGetCurrent());
        
        // weak reference in runloop context
        CFRunLoopSourceContext rlcontext = { 0, self, NULL, NULL, CFCopyDescription, CFEqual, CFHash, NULL, NULL, __BDSKTaskNotify };
        _internal->_rlsource = CFRunLoopSourceCreate(CFAllocatorGetDefault(), 0, &rlcontext);
        CFRunLoopAddSource(_internal->_rl, _internal->_rlsource, kCFRunLoopCommonModes);
        CFRelease(_internal->_rlsource);
        
        // all setup is complete, so now widow the pipe and exec in the child
        close(blockpipe[0]);   
        close(blockpipe[1]);
    }
    
    // executed by child and parent
    [handlesToClose release];
    NSZoneFree(NSZoneFromPointer(args), args);
    if (*nsEnvironment != env) NSZoneFree(NSZoneFromPointer(env), env);
}

- (void)interrupt;
{
    ASSERT_LAUNCH;
    killpg(_processIdentifier, SIGINT);
}

- (void)terminate;
{
    ASSERT_LAUNCH;
    killpg(_processIdentifier, SIGTERM);
}

- (BOOL)suspend;
{
    ASSERT_LAUNCH;
    return (killpg(_processIdentifier, SIGSTOP) == 0);
}

- (BOOL)resume;
{
    ASSERT_LAUNCH;
    return (killpg(_processIdentifier, SIGCONT) == 0);
}

- (int)processIdentifier; 
{ 
    ASSERT_LAUNCH;
    return _processIdentifier; 
}

- (BOOL)isRunning; { return (0 != _internal->_running); }

- (int)terminationStatus; 
{ 
    ASSERT_LAUNCH;
    if ([self isRunning]) [NSException raise:NSInternalInconsistencyException format:@"Task is still running"];
    return _internal->_terminationStatus; 
}

- (void)waitUntilExit;
{
    ASSERT_LAUNCH;
    while ([self isRunning]) {
        NSDate *next = [[NSDate allocWithZone:[self zone]] initWithTimeIntervalSinceNow:0.1];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:next];
        [next release];
    }
}

@end

@implementation BDSKTask (Private)

+ (void)_watchQueue
{
    do {
        
        NSAutoreleasePool *pool = [NSAutoreleasePool new];
        struct kevent evt;
        
        if (kevent(_kqueue, NULL, 0, &evt, 1, NULL)) {
            
            BDSKTask *task = evt.udata;
            OSMemoryBarrier();
            
            // can only fail if _disableNotification is called immediately after kevent unblocks
            if (task->_internal->_canNotify && pthread_mutex_trylock(&task->_internal->_lock) == 0) {
                
                /* 
                 Retain to make sure we hold a reference to the task long enough to handle these calls,
                 so we're guaranteed that _disableNotification will not be called during another callout.
                 */
                task = [task retain];
                pthread_mutex_unlock(&task->_internal->_lock);
                
                if ((evt.fflags & NOTE_EXIT) == NOTE_EXIT)
                    [task _taskExited];
                else if ((evt.fflags & NOTE_SIGNAL) == NOTE_SIGNAL)
                    [task _taskSignaled];
                
                [task release];
            }
            
        }
        [pool release];
        
    } while (1);
}

// presently just informational; _taskExited is called when the process exits due to a signal
- (void)_taskSignaled
{
    int status;
    if (waitpid(_processIdentifier, &status, WNOHANG)) {
        if (WIFSIGNALED(status))
            NSLog(@"task terminated with signal %d", WTERMSIG(status));
        else if (WIFSTOPPED(status))
            NSLog(@"task stopped with signal %d", WSTOPSIG(status));
    }
}

/*
 This is only called from -dealloc.  The kevent thread retains when it unblocks and handles the event,
 so we can never get this during a callout from kevent.  Locking here is required so that the kevent
 thread won't do callout during/after dealloc.
 */
- (void)_disableNotification
{        
    // called unconditionally from -dealloc, so we may have already notified and freed this source
    if (_internal->_rlsource) {
        
        // after this point, _taskExited and __BDSKTaskNotify will never be called, so account for their teardown
        _internal->_event.flags = EV_DELETE;
        kevent(_kqueue, &_internal->_event, 1, NULL, 0, NULL);
        
        CFRunLoopSourceInvalidate(_internal->_rlsource);
        _internal->_rlsource = NULL;
        
        // release the task's reference to the runloop and clear it
        NSCParameterAssert(NULL != _internal->_rl);
        if (_internal->_rl) {
            CFRelease(_internal->_rl);
            _internal->_rl = NULL;
        } 
    }
}

// kevent thread has a retain, so no contention with _disableNotification since we can't dealloc
- (void)_taskExited
{
    NSParameterAssert(_internal->_launched);
    NSParameterAssert(_internal->_running);
    NSParameterAssert(_internal->_event.udata == self);
    
    _internal->_event.flags = EV_DELETE;
    kevent(_kqueue, &_internal->_event, 1, NULL, 0, NULL);   
    
    /*
     Was passing WNOHANG, but http://lists.apple.com/archives/darwin-dev/2009/Nov/msg00100.html describes
     a race condition between kqueue and wait.  Since we know the child has exited, we can allow waitpid
     to block without fear that it will block indefinitely.
     */
    int wait_flags = 0;
    int ret, status;
    
    // keep trying in case of EINTR
    ret = waitpid(_processIdentifier, &status, wait_flags);
    while (-1 == ret && EINTR == errno)
        ret = waitpid(_processIdentifier, &status, wait_flags);
    
    if (0 == ret)
        NSLog(@"*** ERROR *** task %@ (child pid = %d) still running", self, _processIdentifier);
    
    _processIdentifier = -1;
    
    ret = WIFEXITED(status) ? WEXITSTATUS(status) : 1;
    bool swap;
    
    // set return value, then set isRunning to false
    do {
        swap = OSAtomicCompareAndSwap32Barrier(_internal->_terminationStatus, ret, &_internal->_terminationStatus);
    } while (false == swap);
    
    do {
        swap = OSAtomicCompareAndSwap32Barrier(_internal->_running, 0, &_internal->_running);
    } while (false == swap);    
    
    /* 
     Transfer ownership through the callout to avoid dealloc.  Lock runloop source access
     since the source may be handled before CFRunLoopWakeUp() is called, and it is 
     never handled in this thread.
     */
    pthread_mutex_lock(&_internal->_lock);
    [self retain];
    CFRunLoopSourceSignal(_internal->_rlsource);
    CFRunLoopWakeUp(_internal->_rl);
    pthread_mutex_unlock(&_internal->_lock);
}

@end

