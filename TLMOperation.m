//
//  TLMOperations.m
//  TeX Live Utility
//
//  Created by Adam Maxwell on 12/6/08.
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

#import "TLMOperation.h"
#import "TLMTask.h"
#import "TLMPreferenceController.h"
#import "TLMLogServer.h"
#import "TLMEnvironment.h"

NSString * const TLMOperationFinishedNotification = @"TLMOperationFinishedNotification";

static char _TLMOperationFinishedContext;

@implementation TLMOperation

@synthesize outputData = _outputData;
@synthesize errorData = _errorData;
@synthesize failed = _failed;

- (void)_commonInit
{
    [self setFailed:NO];
    [self addObserver:self forKeyPath:@"isFinished" options:0 context:&_TLMOperationFinishedContext];
}

- (id)init
{
    self = [super init];
    if (self) {
        [self _commonInit];
    }
    return self;
}

- (id)initWithCommand:(NSString *)absolutePath options:(NSArray *)options
{
    NSParameterAssert(absolutePath);
    NSParameterAssert(options);
    
    // call super init, or subclasses can't override init and call this initWithCommand:options:
    self = [super init];
    if (self) {
        [self _commonInit];
        _task = [TLMTask new];
        [_task setLaunchPath:absolutePath];
        [_task setArguments:options];
    }
    return self;
}

- (void)dealloc
{
    [self removeObserver:self forKeyPath:@"isFinished"];
    [_task release];
    [_outputData release];
    [_errorData release];
    [_errorMessages release];
    [super dealloc];
}

- (BOOL)isWriter { return NO; }

- (void)_postFinishedNotification
{
    NSParameterAssert([NSThread isMainThread]);
    [[NSNotificationCenter defaultCenter] postNotificationName:TLMOperationFinishedNotification object:self];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == &_TLMOperationFinishedContext) {
        [self performSelectorOnMainThread:@selector(_postFinishedNotification) withObject:nil waitUntilDone:NO];
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (NSString *)errorMessages
{
    @synchronized(self) {
        if (nil == _errorMessages && [[self errorData] length]) {
            _errorMessages = [[NSString alloc] initWithData:[self errorData] encoding:NSUTF8StringEncoding];
        }
    }
    return _errorMessages;
}

- (NSString *)_taskDescription 
{ 
    return [NSString stringWithFormat:@"`%@ %@`", [_task launchPath], [[_task arguments] componentsJoinedByString:@" "]];
}

- (void)main
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
   
    NSAssert(nil != _task, @"No task, probably due to using incorrect initializer");
        
    int status = -1;
    [_task launch];
    
    // Reimplement -[NSTask waitUntilExit] so we can handle -[NSOperation cancel].
    while ([_task isRunning] && [self isCancelled] == NO) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, TRUE);
    }
        
    if ([self isCancelled]) {
        [_task terminate];
    }
    else {
        // not cancelled, but make sure it's really done before calling -terminationStatus
        [_task waitUntilExit];
        status = [_task terminationStatus];
    }
            
    // don't try dealing with partial text data
    if ([self isCancelled]) {
        TLMLog(__func__, @"Cancelled %@", [self _taskDescription]);
        [self setOutputData:nil];
        [self setErrorData:nil];
    // force an immediate read of the pipes
    } else if (EXIT_SUCCESS == status) {
        TLMLog(__func__, @"Successfully executed %@", [self _taskDescription]);
        [self setErrorData:[_task errorData]];
        [self setOutputData:[_task outputData]];
    } else if (0 != status) {
        TLMLog(__func__, @"Failed executing %@ (error %ld)", [self _taskDescription], (long)status);
        [self setErrorData:[_task errorData]];
        [self setFailed:YES];
    }
    
    /*
     It would be nice to show this in the UI in an alert, but it's not always clear enough, and
     always has output even in case of success.  I used to prefix this with "Standard error ..."
     but that confused users; now we have to determine the task and exit status from preceding lines.
     */
    if ([self errorMessages])
        TLMLog(__func__, @"%@", [[self errorMessages] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);
        
    [pool release];
}

@end
