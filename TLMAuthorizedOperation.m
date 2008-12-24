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

@implementation TLMAuthorizedOperation

@synthesize options = _options;

- (id)init
{
    self = [super init];
    if (self) {
        _path = [[[NSBundle mainBundle] pathForAuxiliaryExecutable:@"tlmgr_cwrapper"] copy];
        NSParameterAssert(_path);
        CFUUIDRef uuid = CFUUIDCreate(NULL);
        _serverName = (NSString *)CFUUIDCreateString(NULL, uuid);
        CFRelease(uuid);
    }
    return self;
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

- (void)dealloc
{
    [self _destroyConnection];
    [_path release];
    [_options release];
    [_serverName release];
    [super dealloc];
}

- (void)main 
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    OSStatus status;
    AuthorizationFlags authFlags = kAuthorizationFlagDefaults;
    AuthorizationRef authorization;
    
    status = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, authFlags, &authorization);
    if (errAuthorizationSuccess != status) {
        [self setFailed:YES];
    }
    else {
        
        AuthorizationItem authItems = { kAuthorizationRightExecute, 0, NULL, 0 };
        AuthorizationRights authRights = { 1, &authItems };
        
        authFlags = kAuthorizationFlagDefaults | kAuthorizationFlagInteractionAllowed | kAuthorizationFlagPreAuthorize | kAuthorizationFlagExtendRights;
        status = AuthorizationCopyRights(authorization, &authRights, NULL, authFlags, NULL);
        
        if (errAuthorizationCanceled == status) {
            [self setErrorData:[NSLocalizedString(@"User cancelled operation", @"") dataUsingEncoding:NSUTF8StringEncoding]];
            // this isn't a failure, so the owner may need to check -isCancelled
            [self setFailed:NO];
            [self cancel];
        } else if (errAuthorizationSuccess != status) {
            [self setErrorData:[NSLocalizedString(@"Failed to authorize operation", @"") dataUsingEncoding:NSUTF8StringEncoding]];
            [self setFailed:YES];
        }
        else {
            
            // set up the connection to listen on our worker thread, so we avoid a race when exiting
            _connection = [[NSConnection alloc] initWithReceivePort:[NSPort port] sendPort:nil];
            [_connection setRootObject:[NSProtocolChecker protocolCheckerWithTarget:self protocol:@protocol(TLMAuthOperationProtocol)]];
            if ([_connection registerName:_serverName] == NO)
                TLMLog(@"TLMAuthorizedOperation", @"-[TLMAuthorizedOperation init] Failed to register connection named %@", _serverName);            
            
            const char *cmdPath = [_path fileSystemRepresentation];
            
            // add an extra arg and use calloc to zero the arg vector
            char **args = NSZoneCalloc([self zone], ([_options count] + 2), sizeof(char *));
            int i = 0;
            
            args[i++] = (char *)[_serverName UTF8String];
            
            // fill with autoreleased C-strings
            for (NSString *option in _options) {
                args[i++] = (char *)[option fileSystemRepresentation];
            }
            
            authFlags = kAuthorizationFlagDefaults;
            
            /*
             Passing NULL communicationsPipe to AEWP means we return immediately instead of blocking until the child exits.  Hence, we can pass the child PID back via IPC (DO), then monitor the process and check -isCancelled.
             */
            status = AuthorizationExecuteWithPrivileges(authorization, cmdPath, authFlags, args, NULL);
            
            NSZoneFree([self zone], args);
                                        
            if (errAuthorizationSuccess == status) {
                
                [self setFailed:NO];
                
                do {
                    /*
                     A long timeout should be okay here; incoming DO messages will wake up the runloop, and it's okay if canceling isn't instantaneous.  Originally used 0.1s timeout, but Herb S. noted that it was using significant CPU on a single processor system.  It's unlikely that anything tlmgr does will take such a short time, anyway.
                     */
                    NSDate *next = [[NSDate alloc] initWithTimeIntervalSinceNow:2.0];
                    [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:next];
                    [next release];
                    
                    // !!! FIXME: what if authorization expires before we get here?  That's pretty likely...
                    if ([self isCancelled] && _tlmgr_pid && _cwrapper_pid) {
                        TLMLog(nil, @"killing %d and %d", _tlmgr_pid, _cwrapper_pid);
                        const char *killPath = "/bin/kill";
                        char *killargs[4];
                        killargs[0] = "-KILL";
                        killargs[1] = (char *)[[NSString stringWithFormat:@"%d", _tlmgr_pid] UTF8String];
                        killargs[2] = (char *)[[NSString stringWithFormat:@"%d", _cwrapper_pid] UTF8String];
                        killargs[3] = NULL;
                        AuthorizationExecuteWithPrivileges(authorization, killPath, authFlags, killargs, NULL);     
                        _childFinished = YES;
                    }
                    
                } while (NO == _childFinished);                

            }
            else {
                NSMutableString *errorString = [NSMutableString string];
                [errorString appendString:NSLocalizedString(@"Failed to execute command:\n\t", @"")];
                [errorString appendString:_path];
                [errorString appendString:@" "];
                [errorString appendString:[_options componentsJoinedByString:@" "]];
                [errorString appendString:@"\n"];
                [self setErrorData:[errorString dataUsingEncoding:NSUTF8StringEncoding]];
                [self setFailed:YES];
            }            
        }
    }

    AuthorizationFree(authorization, kAuthorizationFlagDefaults);
    
    // ordinarily tlmgr_cwrapper won't pass anything back up to us
    if ([self errorMessages])
        TLMLog(@"TLMAuthorizedOperation", @"*** ERROR *** %@", [self errorMessages]);
    
    [pool release];
}

- (void)setWrapperPID:(pid_t)pid;
{
    _cwrapper_pid = pid;
    TLMLog(nil, @"tlmgr_cwrapper pid = %d", pid);
}

- (void)setTlmgrPID:(pid_t)pid;
{
    _tlmgr_pid = pid;
    TLMLog(nil, @"tlmgr pid = %d", pid);
}

// If the server is killed before the child detects a return, it will catch an exception while waiting for the reply.  Therefore, we should only access this variable from the worker thread.
- (void)childFinishedWithStatus:(NSInteger)status;
{
    _childFinished = YES;
    TLMLog(nil, @"tlmgr_cwrapper finished with status %d", status);
}

@end
