//
//  TLMAuthorizedOperation.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/20/08.
/*
 This software is Copyright (c) 2008
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

#import <Security/Authorization.h>

#import <sys/types.h>
#import <sys/event.h>
#import <sys/time.h>

struct TLMAOInternal {
    int              _kqueue;
    pid_t            _cwrapper_pid;
    struct kevent    _cwrapper_event;
    pid_t            _tlmgr_pid;
    struct kevent    _tlmgr_event;
    BOOL             _childFinished;
    AuthorizationRef _authorization;
};    

@implementation TLMAuthorizedOperation

@synthesize options = _options;

- (id)init
{
    self = [super init];
    if (self) {
        _path = [[[NSBundle mainBundle] pathForAuxiliaryExecutable:@"tlmgr_cwrapper"] copy];
        NSParameterAssert(_path);
        
        // NSConnection name will be a UUID
        CFUUIDRef uuid = CFUUIDCreate(NULL);
        _serverName = (NSString *)CFUUIDCreateString(NULL, uuid);
        CFRelease(uuid);

        _internal = NSZoneCalloc([self zone], 1, sizeof(struct TLMAOInternal));
        
        // zero the kevent structures
        memset(&_internal->_cwrapper_event, 0, sizeof(struct kevent));
        memset(&_internal->_tlmgr_event, 0, sizeof(struct kevent));
        
        _internal->_kqueue = kqueue();
    }
    return self;
}

- (void)dealloc
{
    if (_internal->_authorization) AuthorizationFree(_internal->_authorization, kAuthorizationFlagDestroyRights);
    NSZoneFree([self zone], _internal);
    _internal = NULL;
    
    [_path release];
    [_options release];
    [_serverName release];
    [super dealloc];
}

- (AuthorizationRef)_authorization
{
    if (NULL == _internal->_authorization) {
        
        OSStatus status;
        AuthorizationFlags authFlags = kAuthorizationFlagDefaults;
        AuthorizationRef authorization;
        status = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, authFlags, &authorization);
        
        AuthorizationItem authItems = { kAuthorizationRightExecute, 0, NULL, 0 };
        AuthorizationRights authRights = { 1, &authItems };
        
        authFlags = kAuthorizationFlagDefaults | kAuthorizationFlagInteractionAllowed | kAuthorizationFlagPreAuthorize | kAuthorizationFlagExtendRights;
        if (noErr == status)
            status = AuthorizationCopyRights(authorization, &authRights, NULL, authFlags, NULL);        
        
        if (noErr == status) {
            _internal->_authorization = authorization;
        }
        else if (errAuthorizationCanceled == status) {
            [self setErrorData:[NSLocalizedString(@"User cancelled operation", @"") dataUsingEncoding:NSUTF8StringEncoding]];
            // this isn't a failure, so the owner may need to check -isCancelled
            [self setFailed:NO];
            [self cancel];
        } else if (errAuthorizationSuccess != status) {
            [self setErrorData:[NSLocalizedString(@"Failed to authorize operation", @"") dataUsingEncoding:NSUTF8StringEncoding]];
            [self setFailed:YES];
        }
    }        
    return _internal->_authorization;
}

- (void)_killChildProcesses
{
    TLMLog(nil, @"killing %d and %d", _internal->_tlmgr_pid, _internal->_cwrapper_pid);
    const char *killPath = "/bin/kill";
    char *killargs[] = { NULL, NULL, NULL, NULL };
    killargs[0] = "-KILL";
    
    /*
     Tlmgr_cwrapper should still be running here, since childFinished is NO.  However, note that there is a short window for a race between the kevent() call and kill; in practice, that should be a non-issue since PID values are 32 bits, and spawning enough processes to wrap around between these calls should not happen.
     */
    killargs[2] = (char *)[[NSString stringWithFormat:@"%d", _internal->_cwrapper_pid] fileSystemRepresentation];
    
    // in case tlmgr has exited and tlmgr_cwrapper is hanging
    if (_internal->_tlmgr_pid)
        killargs[1] = (char *)[[NSString stringWithFormat:@"%d", _internal->_tlmgr_pid] fileSystemRepresentation];
    
    // !!! FIXME: what if authorization expires before we get here?  That's pretty likely...
    AuthorizationRef authorization = [self _authorization];
    OSStatus status;
    if (authorization)
        status = AuthorizationExecuteWithPrivileges(authorization, killPath, kAuthorizationFlagDefaults, killargs, NULL);   
    
    if (status) {
        NSString *errStr;
        errStr = [NSString stringWithFormat:@"AuthorizationExecuteWithPrivileges error: %d (%s)", status, GetMacOSStatusErrorString(status)];
        [self setErrorData:[errStr dataUsingEncoding:NSUTF8StringEncoding]];
    }
}    

- (void)_destroyConnection
{
    [[NSPortNameServer systemDefaultPortNameServer] removePortForName:_serverName];
    [[_connection sendPort] invalidate];
    [[_connection receivePort] invalidate];
    [_connection invalidate];
    [_connection release];
    _connection = nil;
}

- (void)_closeQueue
{
    if (-1 != _internal->_kqueue) {
        
        // remove the tlmgr_cwrapper kevent from the queue
        _internal->_cwrapper_event.flags = EV_DELETE;
        kevent(_internal->_kqueue, &_internal->_cwrapper_event, 1, NULL, 0, NULL);
        
        // remove the tlmgr kevent from the queue
        _internal->_tlmgr_event.flags = EV_DELETE;
        kevent(_internal->_kqueue, &_internal->_tlmgr_event, 1, NULL, 0, NULL);
        
        // close the queue itself
        close(_internal->_kqueue);
        _internal->_kqueue = -1;
    }
}    

- (void)_runUntilChildExit
{
    
    do {
        
        // run the runloop once to service any incoming messages
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantPast]];
        
        // block on kevent with 0.5 second timeout to check [self isCancelled]
        struct timespec timeout;
        timeout.tv_sec = 0;
        timeout.tv_nsec = 500000000;
        
        // only get one event at a time
        struct kevent event;
        int eventCount = kevent(_internal->_kqueue, NULL, 0, &event, 1, &timeout);
                    
        // eventCount == 0 indicates a timeout
        if (0 != eventCount && event.filter == EVFILT_PROC && (event.fflags & NOTE_EXIT) == NOTE_EXIT) {
                        
            if ((pid_t)event.ident == _internal->_cwrapper_pid) {
                
                // set the finished bit when cwrapper exits
                _internal->_childFinished = YES;
                
                // get the exit status of our child process (which is based on exit status of the tlmgr process)
                int ret, wstatus;
                ret = waitpid(event.ident, &wstatus, WNOHANG | WUNTRACED);
                ret = (ret != 0 && WIFEXITED(wstatus)) ? WEXITSTATUS(wstatus) : EXIT_FAILURE;                
                                    
                // set failure flag if cwrapper failed
                [self setFailed:(EXIT_SUCCESS != ret)];
                TLMLog(@"TLMAuthorizedOperation", @"kqueue noted that tlmgr_cwrapper (pid = %d) exited with status %d", event.ident, ret);
            }
            else if ((pid_t)event.ident == _internal->_tlmgr_pid) {
                
                // we only log the tlmgr PID for diagnostic purposes, since we can't get its exit status directly
                TLMLog(@"TLMAuthorizedOperation", @"kqueue noted that tlmgr (pid = %d) exited", event.ident);
                
                // can no longer kill this process
                _internal->_tlmgr_pid = 0;
            }
        }
        
        // kill child processes if the operation was cancelled
        if (NO == _internal->_childFinished && [self isCancelled]) {
            [self _killChildProcesses];
                        
            // set to break out of the main loop
            _internal->_childFinished = YES;
        }
        
    } while (NO == _internal->_childFinished);                
}    

- (void)main 
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    AuthorizationRef authorization = [self _authorization];
    
    if (authorization) {
        
        // set up the connection to listen on our worker thread, so we avoid a race when exiting
        _connection = [[NSConnection alloc] initWithReceivePort:[NSPort port] sendPort:nil];
        [_connection setRootObject:[NSProtocolChecker protocolCheckerWithTarget:self protocol:@protocol(TLMAuthOperationProtocol)]];
        if ([_connection registerName:_serverName] == NO)
            TLMLog(@"TLMAuthorizedOperation", @"-[TLMAuthorizedOperation init] Failed to register connection named %@", _serverName);            
        
        const char *cmdPath = [_path fileSystemRepresentation];
        
        // add an extra arg and use calloc to zero the arg vector
        char **args = NSZoneCalloc([self zone], ([_options count] + 2), sizeof(char *));
        int i = 0;
        
        args[i++] = (char *)[_serverName fileSystemRepresentation];
        
        // fill argv with autoreleased C-strings
        for (NSString *option in _options) {
            args[i++] = (char *)[option fileSystemRepresentation];
        }
                
        /*
         Passing a NULL communicationsPipe to AEWP means we return immediately instead of blocking until the child exits.  Hence, we can pass the child PID back via IPC (DO), then monitor the process and check -isCancelled.
         */
        OSStatus status = AuthorizationExecuteWithPrivileges(authorization, cmdPath, kAuthorizationFlagDefaults, args, NULL);
        
        NSZoneFree([self zone], args);
        
        if (errAuthorizationSuccess == status) {
            [self setFailed:NO];
            
            // poll until the child exits
            [self _runUntilChildExit];
        }
        else {
            NSString *errStr;
            errStr = [NSString stringWithFormat:@"AuthorizationExecuteWithPrivileges error: %d (%s)", status, GetMacOSStatusErrorString(status)];
            [self setErrorData:[errStr dataUsingEncoding:NSUTF8StringEncoding]];
            [self setFailed:YES];
        }  
    }
    
    // ordinarily tlmgr_cwrapper won't pass anything back up to us
    if ([self errorMessages])
        TLMLog(@"TLMAuthorizedOperation", @"%@", [self errorMessages]);
    
    // clean up all scarce resources as soon as possible
    [self _closeQueue];
    [self _destroyConnection];

    [pool release];
}

- (void)setWrapperPID:(pid_t)pid;
{
    _internal->_cwrapper_pid = pid;
    TLMLog(@"TLMAuthorizedOperation", @"tlmgr_cwrapper checking in:  tlmgr_cwrapper pid = %d", pid);
    EV_SET(&_internal->_cwrapper_event, pid, EVFILT_PROC, EV_ADD, NOTE_EXIT, 0, NULL);
    kevent(_internal->_kqueue, &_internal->_cwrapper_event, 1, NULL, 0, NULL);      
}

- (void)setTlmgrPID:(pid_t)pid;
{
    _internal->_tlmgr_pid = pid;
    TLMLog(@"TLMAuthorizedOperation", @"tlmgr_cwrapper checking in:  tlmgr pid = %d", pid);
    EV_SET(&_internal->_tlmgr_event, pid, EVFILT_PROC, EV_ADD, NOTE_EXIT, 0, NULL);
    kevent(_internal->_kqueue, &_internal->_tlmgr_event, 1, NULL, 0, NULL);      
}

@end
