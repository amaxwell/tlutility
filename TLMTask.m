//
//  TLMTask.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 1/5/09.
/*
 This software is Copyright (c) 2009
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

#import "TLMTask.h"

static NSString * const _TLMTaskRunLoopMode = @"_TLMTaskRunLoopMode";

@interface TLMTask()
@property (readwrite, copy) NSData *errorData;
@property (readwrite, copy) NSData *outputData;
@end


@implementation TLMTask

@synthesize outputData = _outputData;
@synthesize errorData = _errorData;


- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_readThread release];
    [_outputData release];
    [_errorData release];
    [_outputString release];
    [_errorString release];
    [super dealloc];
}

- (void)setStandardOutput:(id)output;
{
    NSParameterAssert([output isKindOfClass:[NSPipe class]]);
    if ([self standardOutput])
        [NSException raise:NSInternalInconsistencyException format:@"%@ manages its own stdio channels", [self class]];
    [super setStandardOutput:output];
}

- (void)setStandardError:(id)error;
{
    NSParameterAssert([error isKindOfClass:[NSPipe class]]);
    if ([self standardError])
        [NSException raise:NSInternalInconsistencyException format:@"%@ manages its own stdio channels", [self class]];
    [super setStandardError:error];
}

- (void)_stdoutDataAvailable:(NSNotification *)aNote
{
    [self setOutputData:[[aNote userInfo] objectForKey:NSFileHandleNotificationDataItem]];    
}

- (void)_stderrDataAvailable:(NSNotification *)aNote
{
    [self setErrorData:[[aNote userInfo] objectForKey:NSFileHandleNotificationDataItem]];    
}

- (void)launch
{
    // The point here is to keep NSTask's asynchronous execution semantics while removing the tedious pipe handling.

    [self setStandardOutput:[NSPipe pipe]];
    [self setStandardError:[NSPipe pipe]];
    NSFileHandle *outfh = [[self standardOutput] fileHandleForReading];
    NSFileHandle *errfh = [[self standardError] fileHandleForReading];
    
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(_stdoutDataAvailable:) name:NSFileHandleReadToEndOfFileCompletionNotification object:outfh];
    [nc addObserver:self selector:@selector(_stderrDataAvailable:) name:NSFileHandleReadToEndOfFileCompletionNotification object:errfh];
    
    [outfh readToEndOfFileInBackgroundAndNotifyForModes:[NSArray arrayWithObject:_TLMTaskRunLoopMode]];
    [errfh readToEndOfFileInBackgroundAndNotifyForModes:[NSArray arrayWithObject:_TLMTaskRunLoopMode]];  
    
    /*
     Need to run this thread's runloop to pick up the pipe notifications, so we keep track
     of the thread that registered.  Doing this in -launch allows you to -init on one thread, then
     call -launch on another thread.     
     */
    _readThread = [[NSThread currentThread] retain];
    
    [super launch];
}

- (void)_readDataFromPipes
{
    NSParameterAssert([[NSThread currentThread] isEqual:_readThread]);
    
    // now that the task is finished, run the special runloop mode (only two sources in this mode)
    SInt32 ret;
    
    do {
        
        // handle both sources in this mode immediately
        // any nonzero timeout should be sufficient, since the task has completed and flushed the pipe
        ret = CFRunLoopRunInMode((CFStringRef)_TLMTaskRunLoopMode, 0.1, FALSE);
        
        // should get this immediately
        if (kCFRunLoopRunFinished == ret || kCFRunLoopRunStopped == ret) {
            break;
        }
        
        // hard timeout, since all I get when a task is terminated is kCFRunLoopRunTimedOut
        if (kCFRunLoopRunTimedOut == ret) {
            break;
        }
        
    } while (kCFRunLoopRunHandledSource == ret);
    
    NSFileHandle *outfh = [[self standardOutput] fileHandleForReading];
    NSFileHandle *errfh = [[self standardError] fileHandleForReading];
    
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    
    [nc removeObserver:self name:NSFileHandleReadToEndOfFileCompletionNotification object:outfh];
    [nc removeObserver:self name:NSFileHandleReadToEndOfFileCompletionNotification object:errfh];
    
    _readData = YES;
}   

- (NSData *)outputData
{
    if (NO == _readData)
        [self performSelector:@selector(_readDataFromPipes) onThread:_readThread withObject:nil waitUntilDone:YES];
    return _outputData;
}

- (NSData *)errorData
{
    if (NO == _readData)
        [self performSelector:@selector(_readDataFromPipes) onThread:_readThread withObject:nil waitUntilDone:YES];
    return _errorData;
}

- (NSString *)errorString
{
    if (nil == _errorString && [[self errorData] length])
        _errorString = [[NSString alloc] initWithData:[self errorData] encoding:NSUTF8StringEncoding];
    return _errorString;    
}

- (NSString *)outputString
{
    if (nil == _outputString && [[self outputData] length])
        _outputString = [[NSString alloc] initWithData:[self outputData] encoding:NSUTF8StringEncoding];
    return _outputString;        
}

@end
