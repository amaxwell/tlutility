//
//  TLMUpdateOperation.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/7/08.
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

#import "TLMUpdateOperation.h"
#import "TLMPreferenceController.h"
#include <Security/Authorization.h>
#include <Security/AuthorizationTags.h>

@implementation TLMUpdateOperation

@synthesize packageNames = _packageNames;

- (id)init
{
    return [self initWithPackageNames:nil];
}

- (id)initWithPackageNames:(NSArray *)packageNames;
{
    self = [super init];
    if (self) {
        _path = [[[NSBundle mainBundle] pathForAuxiliaryExecutable:@"tlmgr_cwrapper"] copy];
        NSParameterAssert(_path);
        _packageNames = [packageNames copy];
        
        NSString *useRoot = ([[NSUserDefaults standardUserDefaults] boolForKey:TLMUseRootHomePreferenceKey]) ? @"y" : @"n";
        NSString *location = [[[TLMPreferenceController sharedPreferenceController] serverURL] absoluteString];
        NSString *cmd = [[TLMPreferenceController sharedPreferenceController] tlmgrAbsolutePath];        
        NSMutableArray *options = [NSMutableArray arrayWithObjects:useRoot, cmd, @"--location", location, @"update", nil];
        
        if (nil == packageNames) {
            [options addObject:@"--all"];
        }
        else {
            [options addObjectsFromArray:packageNames];
        }
        _options = [options copy];
    }
    return self;
}

- (void)dealloc
{
    [_path release];
    [_options release];
    [_packageNames release];
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
            [self setErrorData:[NSLocalizedString(@"User cancelled installation", @"") dataUsingEncoding:NSUTF8StringEncoding]];
            // this isn't a failure, so the owner may need to check -isCancelled
            [self setFailed:NO];
            [self cancel];
        } else if (errAuthorizationSuccess != status) {
            [self setErrorData:[NSLocalizedString(@"Failed to authorize installation", @"") dataUsingEncoding:NSUTF8StringEncoding]];
            [self setFailed:YES];
        }
        else {
            const char *cmdPath = [_path fileSystemRepresentation];
            
            // add an extra arg and use calloc to zero the arg vector
            char **args = NSZoneCalloc([self zone], ([_options count] + 1), sizeof(char *));
            int i = 0;
            
            // fill with autoreleased C-strings
            for (NSString *option in _options) {
                args[i++] = (char *)[option fileSystemRepresentation];
            }

            FILE *communicationPipe = NULL;
            
            // TODO: this sucks, since AEWP provides no way to cancel the underlying task.  Maybe the tlmgr_cwrapper could call back with its PID?  That means setting up some sort of IPC and dealing with privileges...
            authFlags = kAuthorizationFlagDefaults;
            status = AuthorizationExecuteWithPrivileges(authorization, cmdPath, authFlags, args, &communicationPipe);
            
            NSZoneFree([self zone], args);
            NSMutableData *outputData = [NSMutableData data];
            char buffer[128];

            if (status == errAuthorizationSuccess) {
                
                // communicationsPipe is only valid if the call succeeded, which is a major wtf
                ssize_t bytesRead;
                while ((bytesRead = read(fileno(communicationPipe), buffer, sizeof(buffer))) > 0) {
                    [outputData appendBytes:buffer length:bytesRead];
                }
                [self setFailed:NO];
            }
            else {
                NSMutableString *errorString = [NSMutableString string];
                [errorString appendString:NSLocalizedString(@"Failed to execute install command:\n\t", @"")];
                [errorString appendString:_path];
                [errorString appendString:@" "];
                [errorString appendString:[_options componentsJoinedByString:@" "]];
                [errorString appendString:@"\n"];
                [outputData appendData:[errorString dataUsingEncoding:NSUTF8StringEncoding]];
                [self setFailed:YES];
            }
            

            [self setErrorData:outputData];
        }
    }
    
    AuthorizationFree(authorization, kAuthorizationFlagDefaults);// 17
    
    [pool release];
}

@end
