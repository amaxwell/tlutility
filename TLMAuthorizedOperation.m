//
//  TLMAuthorizedOperation.m
//  TeX Live Utility
//
//  Created by Adam Maxwell on 12/20/08.
/*
 This software is Copyright (c) 2008-2016
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

#import "TLMAuthorizedOperation.h"
#import "TLMLogServer.h"
#import "TLMTask.h"
#import "TLMPreferenceController.h"
#import "TLMEnvironment.h"

#import <Security/Authorization.h>

#import <sys/types.h>
#import <sys/event.h>
#import <sys/time.h>

// for Distributed Objects (used by tlu_ipctask)
@protocol TLMAuthOperationProtocol

- (void)setWrapperPID:(in pid_t)pid;
- (void)setUnderlyingPID:(in pid_t)pid;

@end

// security-through-obscurity really is pointless for open source...but this groups some of the guts in a separate object
struct TLMAOInternal {
    NSArray         *_options;
    int              _kqueue;
    pid_t            _cwrapper_pid;
    struct kevent    _cwrapper_event;
    pid_t            _underlying_pid;   /* tlmgr or update script     */
    struct kevent    _underlying_event; /* tlmgr or update script     */
    BOOL             _childFinished;    /* tlu_ipctask finished       */
    TLMTask         *_task;             /* authorization not required */
    BOOL             _authorizationRequired;
    AuthorizationRef _authorization;
};    

@implementation TLMAuthorizedOperation

- (id)initWithAuthorizedCommand:(NSString *)absolutePath options:(NSArray *)options;
{
    NSParameterAssert(absolutePath);
    NSParameterAssert(options);
    
    // we override -main and don't need an NSTask, so use -init
    self = [super init];
    if (self) {
        _internal = NSZoneCalloc([self zone], 1, sizeof(struct TLMAOInternal));
        NSParameterAssert(_internal);
        
        // zero the kevent structures
        memset(&_internal->_cwrapper_event, 0, sizeof(struct kevent));
        memset(&_internal->_underlying_event, 0, sizeof(struct kevent));
        
        _internal->_kqueue = kqueue();
        NSParameterAssert(_internal->_kqueue);
        
        NSMutableArray *fullOptions = [options mutableCopy];
        [fullOptions insertObject:absolutePath atIndex:0];
        _internal->_options = [fullOptions copy];
        [fullOptions release];

        _internal->_authorizationRequired = YES;
    }
    return self;
}

- (id)initWithCommand:(NSString *)absolutePath options:(NSArray *)options;
{
    
    self = [self initWithAuthorizedCommand:absolutePath options:options];
    if (self) {
        
        // revised to initWithAuthorizedCommand:options: is now designated init, to avoid hitting TLMEnvironment
        _internal->_authorizationRequired = [[TLMEnvironment currentEnvironment] installRequiresRootPrivileges];
    }
    return self;
}

- (void)dealloc
{
    [_internal->_options release];
    if (_internal->_authorization) AuthorizationFree(_internal->_authorization, kAuthorizationFlagDestroyRights);
    [_internal->_task release];
    NSZoneFree([self zone], _internal);
    _internal = NULL;    
    [super dealloc];
}

- (BOOL)isWriter { return YES; }

- (TLMLogMessageFlags)messageFlags { return TLMLogDefault; }

- (void)_appendStringToErrorData:(NSString *)str
{
    NSMutableData *d = [[self errorData] mutableCopy];
    if (nil == d)
        d = [NSMutableData new];
    [d appendData:[str dataUsingEncoding:NSUTF8StringEncoding]];
    [self setErrorData:d];
    [d release];
}

- (AuthorizationRef)_authorization
{
    NSParameterAssert(_internal->_authorizationRequired);
    
    AuthorizationFlags authFlags = kAuthorizationFlagDefaults;

    // create a single authorization for the lifetime of this instance
    if (NULL == _internal->_authorization) {
        // docs say that this should never return an error
        (void) AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, authFlags, &_internal->_authorization);
    }     
    
    AuthorizationItem authItems = { kAuthorizationRightExecute, 0, NULL, 0 };
    AuthorizationRights authRights = { 1, &authItems };
    authFlags = kAuthorizationFlagDefaults | kAuthorizationFlagInteractionAllowed | kAuthorizationFlagPreAuthorize | kAuthorizationFlagExtendRights;
    
    // see if we can get appropriate rights...
    OSStatus status = AuthorizationCopyRights(_internal->_authorization, &authRights, NULL, authFlags, NULL);        
    
    if (errAuthorizationCanceled == status) {
        [self _appendStringToErrorData:NSLocalizedString(@"User cancelled operation", @"alert message")];
        // this isn't a failure, so the owner may need to check -isCancelled
        [self setFailed:NO];
        [self cancel];
    } else if (errAuthorizationSuccess != status) {
        [self _appendStringToErrorData:[NSString stringWithFormat:@"AuthorizationCopyRights error: %d (%s)", (int32_t)status, GetMacOSStatusErrorString(status)]];
        [self _appendStringToErrorData:NSLocalizedString(@"Failed to authorize operation", @"alert message")];
        [self setFailed:YES];
    }
    
    return noErr == status ? _internal->_authorization : NULL;
}

static NSArray * __TLMOptionArrayFromArguments(char **nullTerminatedArguments)
{
    NSMutableArray *options = [NSMutableArray array];
    char **ptr = nullTerminatedArguments;
    while (NULL != *ptr) {
        [options addObject:[NSString stringWithFileSystemRepresentation:*ptr++]];
    }
    return options;
}

- (void)_killChildProcesses
{
    // !!! early return here; sending `kill -KILL 0` as root is not what we want to do...
    
    // currently this can happen if the signed binary was tampered with, since AEWP returns 0 but the program fails to launch (so never checks in)
    if (0 == _internal->_cwrapper_pid) {
        TLMLog(__func__, @"tlu_ipctask was not running");
        return;
    }
    
    // underlying_pid may be zero...
    TLMLog(__func__, @"killing tlu_ipctask pid = %d", _internal->_cwrapper_pid);
    char *killargs[] = { NULL, NULL, NULL, NULL };
    
    // use SIGKILL since tlmgr doesn't respond to SIGTERM
    killargs[0] = "-KILL";
    
    /*
     Tlmgr_cwrapper should still be running here, since childFinished is NO.  However, note that there is a 
     short window for a race between the kevent() call and kill; in practice, that should be a non-issue 
     since PID values are 32 bits, and spawning enough processes to wrap around between these calls should not happen.
     */
    killargs[1] = (char *)[[NSString stringWithFormat:@"%d", _internal->_cwrapper_pid] saneFileSystemRepresentation];
    
    // possible that tlmgr has exited and tlu_ipctask is hanging, so we only have one process to kill
    if (_internal->_underlying_pid) {
        TLMLog(__func__, @"killing underlying pid = %d", _internal->_underlying_pid);
        killargs[2] = (char *)[[NSString stringWithFormat:@"%d", _internal->_underlying_pid] saneFileSystemRepresentation];
    }

    // run the task using AEWP if authorization required, or as unprivileged user if not
    if (_internal->_authorizationRequired) {
    
        // logs a message and returns NULL if authorization failed
        AuthorizationRef authorization = [self _authorization];
         
        OSStatus status = noErr;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated"
        /*
         In general, you're supposed to write your own helper tool for AEWP.  However, /bin/kill is guaranteed to do exactly what
         we need, and it's used all the time with sudo.  Hence, I'm taking the easy way out (again) and avoiding a possibly buggy
         rewrite of kill(1).
         */
        if (authorization)
            status = AuthorizationExecuteWithPrivileges(authorization, "/bin/kill", kAuthorizationFlagDefaults, killargs, NULL); 
#pragma clang diagnostic pop

        if (noErr != status) {
            NSString *errStr;
            errStr = [NSString stringWithFormat:@"AuthorizationExecuteWithPrivileges error: %d (%s)", (int32_t)status, GetMacOSStatusErrorString(status)];
            [self _appendStringToErrorData:errStr];
        }
    }
    else {

        TLMTask *task = [TLMTask launchedTaskWithLaunchPath:@"/bin/kill" arguments:__TLMOptionArrayFromArguments(killargs)];        
        [task waitUntilExit];
        if ([task terminationStatus] && [task standardError])
            [self _appendStringToErrorData:[task standardError]];
    }

}    

- (void)_closeQueue
{
    if (-1 != _internal->_kqueue) {
        
        // remove the tlu_ipctask kevent from the queue
        _internal->_cwrapper_event.flags = EV_DELETE;
        (void) HANDLE_EINTR(kevent(_internal->_kqueue, &_internal->_cwrapper_event, 1, NULL, 0, NULL));
        
        // remove the tlmgr kevent from the queue
        _internal->_underlying_event.flags = EV_DELETE;
        (void) HANDLE_EINTR(kevent(_internal->_kqueue, &_internal->_underlying_event, 1, NULL, 0, NULL));
        
        // close the queue itself
        close(_internal->_kqueue);
        _internal->_kqueue = -1;
    }
}   

// process executed by tlu_ipctask: either tlmgr or the update script
- (NSString *)_underlyingCommand
{
    // print the full path and all arguments
    return [_internal->_options componentsJoinedByString:@" "];
}

- (void)_runUntilChildExit
{
    int timeoutCount = 0;
    do {
        
        // run the runloop once to service any incoming messages
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantPast]];
        
        // block on kevent with 0.5 second timeout to check [self isCancelled]
        struct timespec timeout;
        timeout.tv_sec = 0;
        timeout.tv_nsec = 500000000;
        
        // only get one event at a time
        struct kevent event;
        int eventCount = HANDLE_EINTR(kevent(_internal->_kqueue, NULL, 0, &event, 1, &timeout));
                    
        // eventCount == 0 indicates a timeout
        if (0 != eventCount && event.filter == EVFILT_PROC && (event.fflags & NOTE_EXIT)) {
                        
            if ((pid_t)event.ident == _internal->_cwrapper_pid) {
                
                // set the finished bit when ipctask exits
                _internal->_childFinished = YES;
                
                // get the exit status of our child process (which is based on exit status of the tlmgr process)
                int ret, wstatus;
                if (_internal->_task) {
                    /*
                     Calling waitpid(2) here interferes with the call in BDSKTask,
                     so it returns -1 and sets errno to ECHLD.  To avoid that,
                     use the NSTask API to get exit status.
                     */
                    [_internal->_task waitUntilExit];
                    ret = [_internal->_task terminationStatus];
                }
                else {

                    /*
                     Formerly called with WNOHANG, but a user has a repeatable case where waitpid returns 0,
                     which obviously causes problems for us, since we already knew from ipctask logging that
                     it exited with status 0.  Try a blocking call to waitpid instead, since we know that
                     the process should be exited or exiting soon.  Chromium source mentions a similar race
                     here:
                     
                     http://src.chromium.org/svn/trunk/src/content/common/process_watcher_mac.cc
                     
                     Looking at BDSKTask.m, apparently I knew about this some time ago, and forgot to apply
                     the same fix here.  Duh.
                     */
                    
                    // initialize for logging
                    wstatus = 0;
                    ret = HANDLE_EINTR(waitpid((int)event.ident, &wstatus, 0));

                    int err = errno;
                    const char *errstr = -1 == ret ? strerror(err) : "No error";
                    TLMLog(__func__, @"waitpid returned %d, WIFEXITED(%d) = %d, errno = %d (%s)", ret, wstatus, WIFEXITED(wstatus), err, errstr);
                    ret = (ret != -1 && WIFEXITED(wstatus)) ? WEXITSTATUS(wstatus) : EXIT_FAILURE;
                }
                // set failure flag if ipctask failed
                [self setFailed:(EXIT_SUCCESS != ret)];
                TLMLog(__func__, @"kqueue noted that tlu_ipctask (pid = %ld) exited with status %d", event.ident, ret);
            }
            else if ((pid_t)event.ident == _internal->_underlying_pid) {
                
                // we only log the tlmgr PID for diagnostic purposes, since we can't get its exit status directly
                TLMLog(__func__, @"kqueue noted that pid %ld exited (%@)", event.ident, [self _underlyingCommand]);
                
                // can no longer kill this process
                _internal->_underlying_pid = 0;
            }
        }
        else if (0 == eventCount) {
            
            // handle a failure in the child before setWrapperPID:
            if (0 == _internal->_underlying_pid || 0 == _internal->_cwrapper_pid)
                timeoutCount++;
            
            if (timeoutCount > 10) {
                TLMLog(__func__, @"No child process on kqueue after %.1f seconds%Cbailing out.", timeoutCount * 0.5, TLM_ELLIPSIS);
                [self setFailed:YES];
            }
        }
        
        // kill child processes if the operation was cancelled or failed
        if (NO == _internal->_childFinished && ([self isCancelled] || [self failed])) {
            [self _killChildProcesses];
                        
            // set to break out of the main loop
            _internal->_childFinished = YES;
        }
        
    } while (NO == _internal->_childFinished);                
}    

/*
 Convenience function.  Always returns the path using NSBundle so there's no ivar to replace or 
 method to override (although someone can replace the executable itself, of course).
 */
static NSString *__TLMCwrapperPath()
{
    NSString *path = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"tlu_ipctask"];
    NSCParameterAssert(path);
    return path;
}

/*
 Even if codesign has been tampered with, the kill option in the signature should still prevent launch.  
 Unfortunately, we get no output and no PID checkin when the file has been modified; it's killed too early.  
 This function is a preflight check to give some useful diagnostics before trying to execute tlu_ipctask,
 but it's not critical to security.
 */
static BOOL __TLMCheckSignature()
{    
    NSString *cmd = @"/usr/bin/codesign";
    
    // see if codesign exists before trying to run it (which would raise an exception)
    NSFileManager *fm = [[NSFileManager new] autorelease];
    if ([fm isExecutableFileAtPath:cmd] == NO) {
        TLMLog(__func__, @"*** ERROR *** %@ does not exist; this is a serious security hole.", cmd);
        return NO;
    }
    
    TLMTask *task = [[TLMTask new] autorelease];
    [task setLaunchPath:cmd];
    [task setArguments:[NSArray arrayWithObjects:@"-vv", __TLMCwrapperPath(), nil]];
    [task launch];
    [task waitUntilExit];

    if ([task errorString]) {
        TLMLog([cmd UTF8String], @"%@", [[task errorString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);
    }
    
    return ([task terminationStatus] == 0);
}

- (void)main 
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
        
    TLMLog(__func__, @"Checking code signature before running %@ as root%C", [__TLMCwrapperPath() lastPathComponent], TLM_ELLIPSIS);
    if (__TLMCheckSignature() == NO) {
        TLMLog(__func__, @"*** ERROR *** The tlu_ipctask has been modified after signing!\nRefusing to run child process with invalid signature.");
        [self _appendStringToErrorData:NSLocalizedString(@"The tlu_ipctask helper application may have been tampered with.", @"")];
        [self setFailed:YES];
        [self cancel];
    }
    else {
        TLMLog(__func__, @"Signature was valid, okay to run %@", [__TLMCwrapperPath() lastPathComponent]);
    }
        
    AuthorizationRef authorization = NULL;

    // codesign failure sets -failed bit
    if (NO == [self failed] && (NO == _internal->_authorizationRequired || (authorization = [self _authorization]) != NULL)) {
        
        // set up the connection to listen on our worker thread, so we avoid a race when exiting
        NSConnection *connection = [NSConnection connectionWithReceivePort:[NSPort port] sendPort:nil];
        [connection setRootObject:[NSProtocolChecker protocolCheckerWithTarget:self protocol:@protocol(TLMAuthOperationProtocol)]];
        
        // NSConnection name will be a UUID
        CFUUIDRef uuid = CFUUIDCreate(NULL);
        NSString *serverName = [(id)CFUUIDCreateString(NULL, uuid) autorelease];
        CFRelease(uuid);
        
        // failure here isn't critical
        if ([connection registerName:serverName] == NO)
            TLMLog(__func__, @"-[TLMAuthorizedOperation init] Failed to register connection named %@", serverName);            
        
        const char *cmdPath = [__TLMCwrapperPath() saneFileSystemRepresentation];
        
        /*
         *** IMPORTANT: change the arg count offset if tlu_ipctask options change. ***
         
         Use calloc to zero the arg vector, then add the two required options for tlu_ipctask
         before adding the subprocess path and options.  A terminating 0 is required.
         */
        char **args = NSZoneCalloc([self zone], ([_internal->_options count] + 4), sizeof(char *));
        int i = 0;
        
        // first argument is the DO server name for IPC
        args[i++] = (char *)[serverName saneFileSystemRepresentation];
        
        // second argument is log message flags
        args[i++] = (char *)[[NSString stringWithFormat:@"%lu", (unsigned long)[self messageFlags]] saneFileSystemRepresentation];
        
        // third argument is address of the operation
        args[i++] = (char *)[[NSString stringWithFormat:@"%lu", (unsigned long)self] saneFileSystemRepresentation];
        
        // remaining options are the command to execute and its options
        for (NSString *option in _internal->_options) {
            args[i++] = (char *)[option saneFileSystemRepresentation];
        }
                
        /*
         Apple's current documentation [1] says to use launchd to run processes as root and they provide a sample [2] to do
         this.  However, using AEWP is still suggested as viable for an "installer" process, and I'm interpreting that loosely.
         Wedging IPC into the launchd process would be non-trivial, unless Apple improves the performance of asl_search to
         become usable; my tests showed that it took ~10 seconds per query, so it's worthless for progress updates to a tableview.
         In any case, I suspect that tlmgr itself is a more significant security hole, just because of the complexity of its
         job and the multiple subprocesses involved; the actual act of running it with root privileges is trivial by comparison.
         
         [1] http://developer.apple.com/documentation/Security/Conceptual/authorization_concepts/01introduction/chapter_1_section_1.html
         [2] http://developer.apple.com/samplecode/BetterAuthorizationSample/listing4.html
         
         */
        
        /*
         Passing a NULL communicationsPipe to AEWP means we return immediately instead of blocking until the child exits.  
         This allows us to pass the child PID back via IPC (DO at present), then monitor the process and check -isCancelled.
         */
        OSStatus status;
        
        if (_internal->_authorizationRequired) {
            
            TLMLog(__func__, @"Invoking privileged task via AuthorizationExecuteWithPrivileges");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated"
            status = AuthorizationExecuteWithPrivileges(authorization, cmdPath, kAuthorizationFlagDefaults, args, NULL);
#pragma clang diagnostic pop
        }
        else {
            
            TLMLog(__func__, @"Using TLMTask instead of AuthorizationExecuteWithPrivileges");
            _internal->_task = [TLMTask new]; 
            [_internal->_task setLaunchPath:__TLMCwrapperPath()];
            [_internal->_task setArguments:__TLMOptionArrayFromArguments(args)];
            [_internal->_task launch];
            // set to nonzero if the task failed to launch
            status = [_internal->_task isRunning] ? errAuthorizationSuccess : coreFoundationUnknownErr;
        }

        
        NSZoneFree([self zone], args);
        args = NULL;
        
        if (errAuthorizationSuccess == status) {
            [self setFailed:NO];
            
            // poll until the child exits
            [self _runUntilChildExit];
        }
        else if (_internal->_authorizationRequired) {
            NSString *errStr;
            errStr = [NSString stringWithFormat:@"AuthorizationExecuteWithPrivileges error: %d (%s)", (int32_t)status, GetMacOSStatusErrorString(status)];
            [self _appendStringToErrorData:errStr];
            [self setFailed:YES];
        }
        
        // exit status already set in _runUntilChildExit
        if ([_internal->_task errorString])
            [self _appendStringToErrorData:[_internal->_task errorString]];
        
        // child has exited at this point
        if (connection) {
            [connection registerName:nil];
            [[connection sendPort] invalidate];
            [[connection receivePort] invalidate];
            [connection invalidate];
        }
    }
    
    // ordinarily tlu_ipctask won't pass anything back up to us
    if ([self errorMessages])
        TLMLog(__func__, @"%@", [self errorMessages]);
    
    // clean up all scarce resources as soon as possible
    [self _closeQueue];

    [pool release];
}

- (void)setWrapperPID:(pid_t)pid;
{
    _internal->_cwrapper_pid = pid;
    TLMLog(__func__, @"tlu_ipctask checking in:  tlu_ipctask pid = %d", pid);
    EV_SET(&_internal->_cwrapper_event, pid, EVFILT_PROC, EV_ADD, NOTE_EXIT, 0, NULL);
    kevent(_internal->_kqueue, &_internal->_cwrapper_event, 1, NULL, 0, NULL);      
}

- (void)setUnderlyingPID:(pid_t)pid;
{
    _internal->_underlying_pid = pid;
    TLMLog(__func__, @"tlu_ipctask checking in: pid = %d (%@)", pid, [self _underlyingCommand]);
    EV_SET(&_internal->_underlying_event, pid, EVFILT_PROC, EV_ADD, NOTE_EXIT, 0, NULL);
    kevent(_internal->_kqueue, &_internal->_underlying_event, 1, NULL, 0, NULL);      
}

@end
