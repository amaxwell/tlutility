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
- (void)_taskExited;

@end

struct BDSKTaskInternal {
    int32_t            _terminationStatus;
    int32_t            _running;
    int32_t            _launched;
    struct kevent      _event;
    CFRunLoopRef       _rl;
    CFRunLoopSourceRef _rlsource;
    OSSpinLock         _lock;
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

#define ASSERT_LAUNCH do { if (!_internal->_launched) { [NSException raise:@"BDSKTaskException" format:@"Task has not been launched"]; } } while (0)
#define ASSERT_NOTLAUNCHED do { if (_internal->_launched) { [NSException raise:@"BDSKTaskException" format:@"Task has already been launched"]; } } while (0)

- (id)init
{
    self = [super init];
    if (self) {
        _internal = NSZoneCalloc([self zone], 1, sizeof(struct BDSKTaskInternal));
        memset(&_internal->_event, 0, sizeof(struct kevent));
    }
    return self;
}

- (void)dealloc
{
    [_launchPath release];
    [_arguments release];
    [_environment release];
    [_currentDirectoryPath release];
    [_standardInput release];
    [_standardOutput release];
    [_standardError release];
    // runloop and source are freed in callback
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

// workaround for NSFileManager's asinine main thread requirement; unclear if using getcwd(3) would be equivalent
+ (NSString *)newCurrentDirectoryPath
{
    NSString *path = nil;
    if (pthread_main_np()) {
        path = [[[NSFileManager defaultManager] currentDirectoryPath] copy];
    }
    else if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber10_4) {
        NSFileManager *fm = [NSFileManager new];
        path = [[fm currentDirectoryPath] copy];
        [fm release];
    }    
    else {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:[fm methodSignatureForSelector:@selector(currentDirectoryPath)]];
        [inv setTarget:fm];
        [inv setSelector:@selector(currentDirectoryPath)];
        NSArray *rlmodes = [NSArray arrayWithObject:(id)kCFRunLoopDefaultMode];
        [inv performSelectorOnMainThread:@selector(invoke) withObject:nil waitUntilDone:YES modes:rlmodes];
        [inv getReturnValue:&path];
        path = [path copy];
    }
    return path;
}

static void __BDSKTaskNotify(void *info)
{
    BDSKTask *task = info;    
    [[NSNotificationCenter defaultCenter] postNotificationName:NSTaskDidTerminateNotification object:task];    
    
    OSSpinLockLock(&task->_internal->_lock);
    // retained by the runloop; invalidate it and then make sure we no longer have a reference
    CFRunLoopSourceInvalidate(task->_internal->_rlsource);
    task->_internal->_rlsource = NULL;
    
    // release the task's reference to the runloop and clear it
    NSCParameterAssert(NULL != task->_internal->_rl);
    if (task->_internal->_rl) {
        CFRelease(task->_internal->_rl);
        task->_internal->_rl = NULL;
    }
    OSSpinLockUnlock(&task->_internal->_lock);
}

- (void)launch;
{
    ASSERT_NOTLAUNCHED;
    
    if (nil == [self currentDirectoryPath]) {
        NSString *path = [BDSKTask newCurrentDirectoryPath];
        [self setCurrentDirectoryPath:path];
        [path release];
    }

    int argCount = [_arguments count];
    const char *workingDir = [_currentDirectoryPath fileSystemRepresentation];
    char **args = NSZoneCalloc([self zone], (argCount + 2), sizeof(char *));
    int i, iMax = argCount;
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
        unsigned envIndex = 0;
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
        
        chdir(workingDir);
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
        bool swap;
        do {
            swap = OSAtomicCompareAndSwap32Barrier(0, 1, &_internal->_running);
        } while (false == swap);
        NSParameterAssert(true == swap);
        
        do {
            swap = OSAtomicCompareAndSwap32Barrier(0, 1, &_internal->_launched);
        } while (false == swap);
        NSParameterAssert(true == swap);
        
        // NSTask docs say that these descriptors are closed in the parent task; required to make pipes work properly
        [handlesToClose makeObjectsPerformSelector:@selector(closeFile)];
        
        if (-1 != fd_null) close(fd_null);

        EV_SET(&_internal->_event, _processIdentifier, EVFILT_PROC, EV_ADD, NOTE_EXIT | NOTE_SIGNAL, 0, [self retain]);
        kevent(_kqueue, &_internal->_event, 1, NULL, 0, NULL);      
        
        // use a runloop source to ensure that the notification is posted on the correct thread
        _internal->_lock = OS_SPINLOCK_INIT;
        _internal->_rl = (CFRunLoopRef)CFRetain(CFRunLoopGetCurrent());
        CFRunLoopSourceContext rlcontext = { 0, self, CFRetain, CFRelease, CFCopyDescription, CFEqual, CFHash, NULL, NULL, __BDSKTaskNotify };
        _internal->_rlsource = CFRunLoopSourceCreate(CFAllocatorGetDefault(), 0, &rlcontext);
        CFRunLoopAddSource(_internal->_rl, _internal->_rlsource, kCFRunLoopCommonModes);
        CFRelease(_internal->_rlsource);
    }
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
    while ([self isRunning])
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
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
            
            if ((evt.fflags & NOTE_EXIT) == NOTE_EXIT)
                [task _taskExited];
            else if ((evt.fflags & NOTE_SIGNAL) == NOTE_SIGNAL)
                [task _taskSignaled];
            
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

- (void)_taskExited
{
    NSParameterAssert(_internal->_launched);
    // error to call this twice, since it decrements the retain count held by the kevent
    NSParameterAssert(_internal->_running);
        
    _internal->_event.flags = EV_DELETE;
    kevent(_kqueue, &_internal->_event, 1, NULL, 0, NULL);   
    
    int status;
    if (0 == waitpid(_processIdentifier, &status, WNOHANG))
        NSLog(@"*** ERROR *** task %@ (child pid = %d) still running", self, _processIdentifier);
    
    _processIdentifier = -1;

    int ret = WIFEXITED(status) ? WEXITSTATUS(status) : 1;
    bool swap;
    
    // set return value, then set isRunning to false
    do {
        swap = OSAtomicCompareAndSwap32Barrier(_internal->_terminationStatus, ret, &_internal->_terminationStatus);
    } while (false == swap);
    
    do {
        swap = OSAtomicCompareAndSwap32Barrier(_internal->_running, 0, &_internal->_running);
    } while (false == swap);    
        
    // balance retain when added to kqueue
    NSParameterAssert(_internal->_event.udata == self);
    [(BDSKTask *)_internal->_event.udata release];

    /* 
     The runloop source is still retaining us.  Lock runloop source access
     since the source may be handled before CFRunLoopWakeUp() is called, and it is 
     never handled in this thread.  Use a spinlock since this is a tiny race window.
     */
    OSSpinLockLock(&_internal->_lock);
    CFRunLoopSourceSignal(_internal->_rlsource);
    CFRunLoopWakeUp(_internal->_rl);
    OSSpinLockUnlock(&_internal->_lock);
}

@end

