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
#import "BDSKTask.h"

#import <Security/Authorization.h>

#import <sys/types.h>
#import <sys/event.h>
#import <sys/time.h>

struct TLMAOInternal {
    int              _kqueue;
    pid_t            _cwrapper_pid;
    struct kevent    _cwrapper_event;
    pid_t            _underlying_pid;   /* tlmgr or update script  */
    struct kevent    _underlying_event; /* tlmgr or update script  */
    BOOL             _childFinished;    /* tlmgr_cwrapper finished */
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
        memset(&_internal->_underlying_event, 0, sizeof(struct kevent));
        
        _internal->_kqueue = kqueue();
        if (-1 == _internal->_kqueue) {
            int e = errno;
            TLMLog(__func__, @"Failed to create kqueue with error %s", strerror(e));
            [self release];
            self = nil;
        }
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
        [self _appendStringToErrorData:NSLocalizedString(@"Failed to authorize operation", @"alert message")];
        [self setFailed:YES];
    }
    
    return noErr == status ? _internal->_authorization : NULL;
}

- (void)_killChildProcesses
{
    // !!! early return here; sending `kill -KILL 0` as root is not what we want to do...
    
    // currently this can happen if the signed binary was tampered with, since AEWP returns 0 but the program fails to launch (so never checks in)
    if (0 == _internal->_cwrapper_pid) {
        TLMLog(__func__, @"tlmgr_cwrapper was not running");
        return;
    }
    
    // underlying_pid may be zero...
    TLMLog(__func__, @"killing %d and %d", _internal->_underlying_pid, _internal->_cwrapper_pid);
    char *killargs[] = { NULL, NULL, NULL, NULL };
    killargs[0] = "-KILL";
    
    /*
     Tlmgr_cwrapper should still be running here, since childFinished is NO.  However, note that there is a short window for a race between the kevent() call and kill; in practice, that should be a non-issue since PID values are 32 bits, and spawning enough processes to wrap around between these calls should not happen.
     */
    killargs[1] = (char *)[[NSString stringWithFormat:@"%d", _internal->_cwrapper_pid] fileSystemRepresentation];
    
    // possible that tlmgr has exited and tlmgr_cwrapper is hanging, so we only have one process to kill
    if (_internal->_underlying_pid)
        killargs[2] = (char *)[[NSString stringWithFormat:@"%d", _internal->_underlying_pid] fileSystemRepresentation];
    
    // logs a message and returns NULL if authorization failed
    AuthorizationRef authorization = [self _authorization];
     
    OSStatus status = noErr;
    if (authorization)
        status = AuthorizationExecuteWithPrivileges(authorization, "/bin/kill", kAuthorizationFlagDefaults, killargs, NULL); 
    
    if (noErr != status) {
        NSString *errStr;
        errStr = [NSString stringWithFormat:@"AuthorizationExecuteWithPrivileges error: %d (%s)", status, GetMacOSStatusErrorString(status)];
        [self _appendStringToErrorData:errStr];
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
        _internal->_underlying_event.flags = EV_DELETE;
        kevent(_internal->_kqueue, &_internal->_underlying_event, 1, NULL, 0, NULL);
        
        // close the queue itself
        close(_internal->_kqueue);
        _internal->_kqueue = -1;
    }
}   

// process executed by tlmgr_cwrapper: either tlmgr or the update script
- (NSString *)_underlyingProcessName
{
    NSArray *options = [self options];
    
    // first argument is y/n for tlmgr_cwrapper
    if ([options count] < 2)
        return @"*** ERROR ***: unknown process";
    
    // print the full path and all arguments
    return [[options subarrayWithRange:NSMakeRange(1, [options count] - 1)] componentsJoinedByString:@" "];
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
                TLMLog(__func__, @"kqueue noted that tlmgr_cwrapper (pid = %d) exited with status %d", event.ident, ret);
            }
            else if ((pid_t)event.ident == _internal->_underlying_pid) {
                
                // we only log the tlmgr PID for diagnostic purposes, since we can't get its exit status directly
                TLMLog(__func__, @"kqueue noted that pid %d exited (%@)", event.ident, [self _underlyingProcessName]);
                
                // can no longer kill this process
                _internal->_underlying_pid = 0;
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

- (BOOL)_checkSignature
{
    NSFileManager *fm = [[NSFileManager new] autorelease];
    
    // even if codesign has been tampered with, the kill option in the signature will still prevent launch
    NSString *cmd = @"/usr/bin/codesign";
    if ([fm isExecutableFileAtPath:cmd] == NO)
        return NO;
    
    BDSKTask *task = [[BDSKTask new] autorelease];
    [task setLaunchPath:cmd];
    [task setArguments:[NSArray arrayWithObjects:@"-vv", _path, nil]];
    [task setStandardError:[NSPipe pipe]];
    [task launch];
    [task waitUntilExit];
    
    // we get two short lines of output, so the pipe shouldn't fill up...
    NSFileHandle *fh = [[task standardError] fileHandleForReading];
    NSData *outputData = [fh readDataToEndOfFile];
    NSString *outputString = nil;
    if ([outputData length])
        outputString = [[[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding] autorelease];
    
    if (outputString) {
        TLMLog([cmd UTF8String], @"%@", [outputString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);
    }
    
    return ([task terminationStatus] == 0);
}

- (void)main 
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
        
    TLMLog(__func__, @"Checking code signature before running %@ as root%C", [_path lastPathComponent], 0x2026);
    if ([self _checkSignature] == NO) {
        TLMLog(__func__, @"*** ERROR *** The tlmgr_cwrapper has been modified after signing!\nRefusing to run child process with invalid signature.");
        [self _appendStringToErrorData:NSLocalizedString(@"The tlmgr_cwrapper helper application may have been tampered with.", @"")];
        [self setFailed:YES];
        [self cancel];
    }
    else {
        TLMLog(__func__, @"Signature was valid, okay to run %@", [_path lastPathComponent]);
    }
        
    AuthorizationRef authorization = NULL;

    // codesign failure sets -failed bit
    if (NO == [self failed] && (authorization = [self _authorization]) != NULL) {
        
        // set up the connection to listen on our worker thread, so we avoid a race when exiting
        _connection = [[NSConnection alloc] initWithReceivePort:[NSPort port] sendPort:nil];
        [_connection setRootObject:[NSProtocolChecker protocolCheckerWithTarget:self protocol:@protocol(TLMAuthOperationProtocol)]];
        
        // failure here isn't critical
        if ([_connection registerName:_serverName] == NO)
            TLMLog(__func__, @"-[TLMAuthorizedOperation init] Failed to register connection named %@", _serverName);            
        
        const char *cmdPath = [_path fileSystemRepresentation];
        
        // add an extra arg and use calloc to zero the arg vector
        char **args = NSZoneCalloc([self zone], ([_options count] + 2), sizeof(char *));
        int i = 0;
        
        // first argument is the DO server name for IPC
        args[i++] = (char *)[_serverName fileSystemRepresentation];
        
        // fill argv with autoreleased C-strings
        for (NSString *option in _options) {
            args[i++] = (char *)[option fileSystemRepresentation];
        }
                
        /*
         Passing a NULL communicationsPipe to AEWP means we return immediately instead of blocking until the child exits.  
         This allows us to pass the child PID back via IPC (DO at present), then monitor the process and check -isCancelled.
         */
        OSStatus status = AuthorizationExecuteWithPrivileges(authorization, cmdPath, kAuthorizationFlagDefaults, args, NULL);
        
        NSZoneFree([self zone], args);
        args = NULL;
        
        if (errAuthorizationSuccess == status) {
            [self setFailed:NO];
            
            // poll until the child exits
            [self _runUntilChildExit];
        }
        else {
            NSString *errStr;
            errStr = [NSString stringWithFormat:@"AuthorizationExecuteWithPrivileges error: %d (%s)", status, GetMacOSStatusErrorString(status)];
            [self _appendStringToErrorData:errStr];
            [self setFailed:YES];
        }  
    }
    
    // ordinarily tlmgr_cwrapper won't pass anything back up to us
    if ([self errorMessages])
        TLMLog(__func__, @"%@", [self errorMessages]);
    
    // clean up all scarce resources as soon as possible
    [self _closeQueue];
    [self _destroyConnection];

    [pool release];
}

- (void)setWrapperPID:(pid_t)pid;
{
    _internal->_cwrapper_pid = pid;
    TLMLog(__func__, @"tlmgr_cwrapper checking in:  tlmgr_cwrapper pid = %d", pid);
    EV_SET(&_internal->_cwrapper_event, pid, EVFILT_PROC, EV_ADD, NOTE_EXIT, 0, NULL);
    kevent(_internal->_kqueue, &_internal->_cwrapper_event, 1, NULL, 0, NULL);      
}

- (void)setUnderlyingPID:(pid_t)pid;
{
    _internal->_underlying_pid = pid;
    TLMLog(__func__, @"tlmgr_cwrapper checking in: pid = %d (%@)", pid, [self _underlyingProcessName]);
    EV_SET(&_internal->_underlying_event, pid, EVFILT_PROC, EV_ADD, NOTE_EXIT, 0, NULL);
    kevent(_internal->_kqueue, &_internal->_underlying_event, 1, NULL, 0, NULL);      
}

@end
