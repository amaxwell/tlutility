//
//  BDSKTask.m
//  Bibdesk
//
//  Created by Adam Maxwell on 8/25/08.
/*
 This software is Copyright (c) 2008-2013
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
    BOOL               _canNotify;
    struct kevent      _event;
    CFRunLoopRef       _rl;
    CFRunLoopSourceRef _rlsource;
    pthread_mutex_t    _lock;
    id                 _task;
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

#define ASSERT_LAUNCH do { if (!_launched) { [NSException raise:@"BDSKTaskException" format:@"Task has not been launched"]; } } while (0)
#define ASSERT_NOTLAUNCHED do { if (_launched) { [NSException raise:@"BDSKTaskException" format:@"Task has already been launched"]; } } while (0)

- (id)init
{
    self = [super init];
    if (self) {
        _internal = NSZoneCalloc([self zone], 1, sizeof(struct BDSKTaskInternal));
        memset(&_internal->_event, 0, sizeof(struct kevent));
        pthread_mutex_init(&_internal->_lock, NULL);
        _internal->_canNotify = 1;
        _internal->_task = self;
    }
    return self;
}

- (void)dealloc
{
    [self _disableNotification];
    [_launchPath release];
    [_arguments release];
    [_environment release];
    [_currentDirectoryPath release];
    [_standardInput release];
    [_standardOutput release];
    [_standardError release];
    [super dealloc];
}

- (void)finalize
{
    [self _disableNotification];
    [super finalize];
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
    
    // trivial sanity check here
    NSCParameterAssert(task->_internal->_task == task);
    task->_internal->_task = nil;
    
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
    
    // only freed when the child exits, so the kevent callout always has a valid udata pointer
    pthread_mutex_destroy(&task->_internal->_lock);
    NSZoneFree(NSZoneFromPointer(task->_internal), task->_internal);
    task->_internal = NULL;
    
    // balance additional retain in _taskExited
    [task release];
}

/*
 Undocumented behavior of -[NSFileManager fileSystemRepresentationWithPath:]
 is to raise an exception when passed an empty string.  Since this is called by
 -[NSString fileSystemRepresentation], use CF.  rdar://problem/9565599
 
 https://bitbucket.org/jfh/machg/issue/244/p1d3-crash-during-view-differences
 
 Have to copy all -[NSString fileSystemRepresentation] pointers to avoid garbage collection
 issues with -fileSystemRepresentation, anyway.  How tedious compared to -autorelease...
 
 http://lists.apple.com/archives/objc-language/2011/Mar/msg00122.html
 */
static char *__BDSKCopyFileSystemRepresentation(NSString *str)
{
    if (nil == str) return NULL;
    
    CFIndex len = CFStringGetMaximumSizeOfFileSystemRepresentation((CFStringRef)str);
    char *cstr = NSZoneCalloc(NSDefaultMallocZone(), len, sizeof(char));
    if (CFStringGetFileSystemRepresentation((CFStringRef)str, cstr, len) == FALSE) {
        NSZoneFree(NSDefaultMallocZone(), cstr);
        cstr = NULL;
    }
    return cstr;
}

- (void)launch;
{
    ASSERT_NOTLAUNCHED;
    
    const NSUInteger argCount = [_arguments count];
    char *workingDir = __BDSKCopyFileSystemRepresentation(_currentDirectoryPath);
    
    // fill with pointers to copied C strings
    char **args = NSZoneCalloc([self zone], (argCount + 2), sizeof(char *));
    NSUInteger i;
    args[0] = __BDSKCopyFileSystemRepresentation(_launchPath);
    for (i = 0; i < argCount; i++) {
        args[i + 1] = __BDSKCopyFileSystemRepresentation([_arguments objectAtIndex:i]);
    }
    args[argCount + 1] = NULL;
    
    char ***nsEnvironment = _NSGetEnviron();
    char **env = *nsEnvironment;
    
    NSDictionary *environment = [self environment];
    if (environment) {
        // fill with pointers to copied C strings
        env = NSZoneCalloc([self zone], [environment count] + 1, sizeof(char *));
        NSString *key;
        NSUInteger envIndex = 0;
        for (key in environment) {
            env[envIndex++] = __BDSKCopyFileSystemRepresentation([NSString stringWithFormat:@"%@=%@", key, [environment objectForKey:key]]);        
        }
        env[envIndex] = NULL;
    }
    
    // fileHandleWithNullDevice returns a descriptor of -1, so use fd_null instead
    int fd_out = -1, fd_inp = -1, fd_err = -1, fd_null = open("/dev/null", O_WRONLY);
    id fh = nil;
    
    // the end of a pipe passed to the child needs to be closed in the parent process
    NSMutableSet *handlesToClose = [NSMutableSet set];
    NSFileHandle *nullHandle = [NSFileHandle fileHandleWithNullDevice];
    [handlesToClose addObject:nullHandle];
    
    fh = [self standardInput];
    if ([fh isKindOfClass:[NSPipe class]]) {
        [handlesToClose addObject:[fh fileHandleForReading]];
        fd_inp = [[fh fileHandleForReading] fileDescriptor];
    }
    else if (nil != fh) {
        fd_inp = [fh isEqual:nullHandle] ? fd_null : [fh fileDescriptor];
    }
    
    fh = [self standardOutput];
    if ([fh isKindOfClass:[NSPipe class]]) {
        [handlesToClose addObject:[fh fileHandleForWriting]];
        fd_out = [[fh fileHandleForWriting] fileDescriptor];
    }
    else if (nil != fh) {
        fd_out = [fh isEqual:nullHandle] ? fd_null : [fh fileDescriptor];
    }
    
    fh = [self standardError];
    if ([fh isKindOfClass:[NSPipe class]]) {
        [handlesToClose addObject:[fh fileHandleForWriting]];
        fd_err = [[fh fileHandleForWriting] fileDescriptor];
    }
    else if (nil != fh) {
        fd_err = [fh isEqual:nullHandle] ? fd_null : [fh fileDescriptor];
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
    int maxOpenFiles = OPEN_MAX;
    struct rlimit openFileLimit;
    if (getrlimit(RLIMIT_NOFILE, &openFileLimit) == 0)
        maxOpenFiles = (int)openFileLimit.rlim_cur;
    
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
         
         Using a class-scope lock is one possible solution, but NSTask couldn't use that lock, and subclasses
         that override -launch would also not benefit from locking (e.g., TLMTask).  Since TLMTask sets up
         NSPipes in -launch before calling -[super launch], those pipes and any created by Cocoa would not
         be protected by that lock.  Closing all remaining file descriptors in the child doesn't break any 
         documented behavior of NSTask, and it should take care of that problem.  It's not a great solution,
         since inheriting other descriptors could possibly be useful, but I don't need to share arbitrary file 
         descriptors, whereas I do need subclassing and threads to work properly.
         */
        int j;
        for (j = (STDERR_FILENO + 1); j < maxOpenFiles; j++) {
            
            // don't close this until we're done reading from it!
            if (blockpipe[0] != j)
                (void) close(j);
        }
        
        char ignored;
        // block until the parent has setup complete
        (void) HANDLE_EINTR(read(blockpipe[0], &ignored, 1));
        close(blockpipe[0]);
        
        int ret = execve(args[0], args, env);
        _exit(ret);
    }
    else if (-1 == _processIdentifier) {
        // parent: error
        int forkError = errno;
        NSLog(@"fork() failed in task %@: %s", self, strerror(forkError));
        _terminationStatus = 2;
        
        // clean up what we can
        [handlesToClose makeObjectsPerformSelector:@selector(closeFile)];
        if (-1 != fd_null) (void) close(fd_null);
        close(blockpipe[0]);   
        close(blockpipe[1]);
    }
    else {        
        // parent process
                
        // CASB probably not necessary anymore...
        OSAtomicCompareAndSwap32Barrier(0, 1, &_running);
        OSAtomicCompareAndSwap32Barrier(0, 1, &_launched);
        
        // NSTask docs say that these descriptors are closed in the parent task; required to make pipes work properly
        [handlesToClose makeObjectsPerformSelector:@selector(closeFile)];
        
        if (-1 != fd_null) (void) close(fd_null);

        /*
         The kevent will have a strong reference to the _internal pointer, which has a weak reference to the task
         itself.  This allows -dealloc to occur without waiting for notification, as documented for NSTask.
         Presumably this is so you can fire it off and not have any resources hanging around after the exec.
         */
        EV_SET(&_internal->_event, _processIdentifier, EVFILT_PROC, EV_ADD, NOTE_EXIT | NOTE_SIGNAL, 0, _internal);
        (void) HANDLE_EINTR(kevent(_kqueue, &_internal->_event, 1, NULL, 0, NULL));      
        
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
    
    /*
     Free all the copied C strings.  Don't modify the base pointer of args or env, since we have to
     free those too!
     */
    free(workingDir);
    char **freePtr = args;
    while (NULL != *freePtr) { 
        free(*freePtr++);
    }
    
    NSZoneFree(NSZoneFromPointer(args), args);
    if (*nsEnvironment != env) {
        freePtr = env;
        while (NULL != *freePtr) { 
            free(*freePtr++);
        }
        NSZoneFree(NSZoneFromPointer(env), env);
    }
    
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

- (BOOL)isRunning; { return (0 != _running); }

- (int)terminationStatus; 
{ 
    ASSERT_LAUNCH;
    if ([self isRunning]) [NSException raise:NSInternalInconsistencyException format:@"Task is still running"];
    return _terminationStatus; 
}

- (NSTaskTerminationReason)terminationReason; 
{ 
    ASSERT_LAUNCH;
    if ([self isRunning]) [NSException raise:NSInternalInconsistencyException format:@"Task is still running"];
    return _terminationReason; 
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
        
        struct kevent evt;
        
        // block indefinitely
        const int eventCount = HANDLE_EINTR(kevent(_kqueue, NULL, 0, &evt, 1, NULL));

        if (eventCount == -1) {
            /*
             This is a total bandaid for a problem I'm seeing, as I've no idea
             why a kqueue file descriptor could go invalid. I suspect it's a side
             effect of a memory smasher somewhere.
             */
            int err = errno;
            NSLog(@"kevent failed in %s with error: %s", __func__, strerror(err));
            (void) close(_kqueue);
            _kqueue = kqueue();
            continue;
        }        
            
        if (evt.flags & EV_ERROR || EVFILT_PROC != evt.filter) {
            NSLog(@"Skipping bad event from kqueue: flags=%d, filter=%d, data=%ld", evt.flags, evt.filter, evt.data);
            continue;
        }
            
        struct BDSKTaskInternal *internal = evt.udata;
        pthread_mutex_lock(&internal->_lock);
        
        // can only fail if _disableNotification is called immediately after kevent unblocks
        if (internal->_canNotify) {
            
            NSAutoreleasePool *pool = [NSAutoreleasePool new];
            
            // retain a pointer to the task before unlocking
            BDSKTask *task = [internal->_task retain];
            pthread_mutex_unlock(&internal->_lock);

            // may be called multiple times; no need to free anything
            if (evt.fflags & NOTE_SIGNAL)
                [task _taskSignaled];
            
            /*
             Only called once; can free stuff on this code path, as -dealloc will not be called
             while it's executing because we have a retain on the task.
             */
            if (evt.fflags & NOTE_EXIT)
                [task _taskExited];
            
            [task release];
            
            [pool drain];
            
        }
        else {

            NSLog(@"Not posting NSTaskDidTerminateNotification for deallocated task %p", internal->_task);

            // delete this event to make sure we don't get anything else
            internal->_event.flags = EV_DELETE;
            (void) HANDLE_EINTR(kevent(_kqueue, &internal->_event, 1, NULL, 0, NULL));

            /*
             -dealloc or -finalize have called _disableNotification, and it
             is now our responsibility to free the _internal pointer.
             */
            pthread_mutex_unlock(&internal->_lock);
            pthread_mutex_destroy(&internal->_lock);

            // runloop and source were freed in _disableNotification
            NSParameterAssert(NULL == internal->_rl);
            NSParameterAssert(NULL == internal->_rlsource);
            NSZoneFree(NSZoneFromPointer(internal), internal);
            
        }      
        
    } while (1);
}

// presently just informational; _taskExited is called when the process exits due to a signal
- (void)_taskSignaled
{
    int status;
    if (HANDLE_EINTR(waitpid(_processIdentifier, &status, WNOHANG))) {
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
    // !!! early return if task has already exited
    if (NULL == _internal)
        return;
    
    // Unset _canNotify in case kevent unblocks before we can remove it from the queue.
    pthread_mutex_lock(&_internal->_lock);
    _internal->_canNotify = NO;
    
    /*
     Called unconditionally from -dealloc, so we may have already notified and freed this source,
     (in which case _internal would be NULL), or we are dealing with an object that failed to
     launch and thus doesn't have a runloop source.
     */
    if (_internal->_rlsource) {
        
        /*
         After this point, _taskExited and __BDSKTaskNotify will never be called, so account for their teardown.
         Could do some of this in the kevent handler when the child exits, but best to get rid of these
         resources now.
         */
        CFRunLoopSourceInvalidate(_internal->_rlsource);
        _internal->_rlsource = NULL;
        
        // release the task's reference to the runloop and clear it
        NSCParameterAssert(NULL != _internal->_rl);
        if (_internal->_rl) {
            CFRelease(_internal->_rl);
            _internal->_rl = NULL;
        } 
    }
    
    pthread_mutex_unlock(&_internal->_lock);
    
    // runloop and source are freed in __BDSKTaskNotify or _disableNotification
    NSParameterAssert(NULL == _internal->_rl);
    NSParameterAssert(NULL == _internal->_rlsource);
    
    /*
     Lock and _internal pointer itself are only freed when the kevent is received
     after the child task exits, but we no longer need a reference to it.
    */
    _internal = NULL;
}

// kevent thread has a retain, so no contention with _disableNotification since we can't dealloc
- (void)_taskExited
{
    pthread_mutex_lock(&_internal->_lock);
    
    NSParameterAssert(_launched);
    NSParameterAssert(_running);
    NSParameterAssert(_internal->_event.udata == _internal);
    
    _internal->_event.flags = EV_DELETE;
    kevent(_kqueue, &_internal->_event, 1, NULL, 0, NULL);   
    
    /*
     Was passing WNOHANG, but http://lists.apple.com/archives/darwin-dev/2009/Nov/msg00100.html describes
     a race condition between kqueue and wait.  Since we know the child has exited, we can allow waitpid
     to block without fear that it will block indefinitely.
     */
    int ret, status;
    
    ret = HANDLE_EINTR(waitpid(_processIdentifier, &status, 0));
    
    // happens if you call waitpid() on the child process elsewhere; don't do that
    if (-1 == ret)
        perror(__func__);
    
    if (0 == ret)
        NSLog(@"*** ERROR *** task %@ (child pid = %d) still running", self, _processIdentifier);
    
    _processIdentifier = -1;
    
    _terminationReason = WIFSIGNALED(status) ? NSTaskTerminationReasonUncaughtSignal : NSTaskTerminationReasonExit;
    
    ret = WIFEXITED(status) ? WEXITSTATUS(status) : 1;
    bool swap;
    
    // set return value, then set isRunning to false
    do {
        swap = OSAtomicCompareAndSwap32Barrier(_terminationStatus, ret, &_terminationStatus);
    } while (false == swap);
    
    do {
        swap = OSAtomicCompareAndSwap32Barrier(_running, 0, &_running);
    } while (false == swap);    
    
    /* 
     Transfer ownership through the callout to avoid dealloc.  Lock runloop source access
     since the source may be handled before CFRunLoopWakeUp() is called, and it is 
     never handled in this thread.
     */
    [self retain];
    CFRunLoopSourceSignal(_internal->_rlsource);
    CFRunLoopWakeUp(_internal->_rl);
    pthread_mutex_unlock(&_internal->_lock);
}

@end

