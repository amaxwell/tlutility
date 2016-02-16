//
//  BDSKTask.h
//  Bibdesk
//
//  Created by Adam Maxwell on 8/25/08.
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

#import <Cocoa/Cocoa.h>

/** @brief Concrete subclass of NSTask.
 
 NSTask is not listed as thread safe in Apple's documentation.  At least in 10.4 and prior, its implementation allows the parent/child relationship to be lost (somehow), possibly by observing SIGCHLD in a thread-unsafe way.  Among other problems, this causes unexpected exceptions to be raised, and termination to not work correctly.  
 
 BDSKTask is designed to be thread safe insofar as instances can be created and launched from threads other than the AppKit thread.  If the task is accessed from multiple threads, use a lock to protect it.
 
 BDSKTask guarantees that NSTaskDidTerminateNotification will be posted on the thread that called BDSKTask::launch.
 
 Exceptions should only be raised for violation of the API contract (e.g. calling BDSKTask::terminationStatus while the task is still running, or setting the launch path after the task has launched).
 
 */

#ifndef MAC_OS_X_VERSION_10_6
enum {
    NSTaskTerminationReasonExit = 1,
    NSTaskTerminationReasonUncaughtSignal = 2
};
typedef NSInteger NSTaskTerminationReason;
#endif


@interface BDSKTask : NSTask {
@private
    NSString                *_launchPath;
    NSArray                 *_arguments;
    NSDictionary            *_environment;
    NSString                *_currentDirectoryPath;
    id                       _standardInput;
    id                       _standardOutput;
    id                       _standardError;
    pid_t                    _processIdentifier;    
    int32_t                  _terminationStatus;
    NSTaskTerminationReason  _terminationReason;
    int32_t                  _running;
    int32_t                  _launched;
    struct BDSKTaskInternal *_internal;
}

+ (BDSKTask *)launchedTaskWithLaunchPath:(NSString *)path arguments:(NSArray *)arguments;

@end

#ifndef HANDLE_EINTR
// http://src.chromium.org/svn/trunk/src/base/eintr_wrapper.h
#define HANDLE_EINTR(x) ({ \
    typeof(x) __eintr_result__; \
    do { \
        __eintr_result__ = x; \
    } while (__eintr_result__ == -1 && errno == EINTR); \
    __eintr_result__;\
})
#endif
