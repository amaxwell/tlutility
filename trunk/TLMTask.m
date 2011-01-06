//
//  TLMTask.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 1/5/09.
/*
 This software is Copyright (c) 2009-2011
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
#import "TLMLogServer.h"
#include <sys/event.h>


#define TLM_KQ_INIT     0
#define TLM_KQ_SETUP    1
#define TLM_KQ_WAITING  2
#define TLM_KQ_FINISHED 3

@implementation TLMTask

+ (TLMTask *)launchedTaskWithLaunchPath:(NSString *)path arguments:(NSArray *)arguments;
{
    TLMTask *task = [[self new] autorelease];
    [task setLaunchPath:path];
    [task setArguments:arguments];
    [task launch];
    return task;
}

- (void)dealloc
{
    [_outputData release];
    [_errorData release];
    [_outputString release];
    [_errorString release];
    [_lock release];
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

- (void)_readOutputAndErrorChannels
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    [_lock lockWhenCondition:TLM_KQ_INIT];
    
    // We just set these to NSPipes and acquired the lock, so calling these accessors is safe
    int fdo = [[[self standardOutput] fileHandleForReading] fileDescriptor];
    int fde = [[[self standardError] fileHandleForReading] fileDescriptor];
    
    // hopefully this never happens...
    if (fdo < 0 || fde < 0) {
        TLMLog(__func__, @"invalid stdio channels in task %@", self);
        [pool release];
        return;
    }
    
    int kq_fd = kqueue();
#define TLM_EVENT_COUNT 2
    struct kevent events[TLM_EVENT_COUNT];
    memset(events, 0, sizeof(struct kevent) * TLM_EVENT_COUNT);
    
    EV_SET(&events[0], fdo, EVFILT_READ, EV_ADD, 0, 0, NULL);
    EV_SET(&events[1], fde, EVFILT_READ, EV_ADD, 0, 0, NULL);
    kevent(kq_fd, events, TLM_EVENT_COUNT, NULL, 0, NULL);
    
    // kqueue is set up now, so we can launch
    [_lock unlockWithCondition:TLM_KQ_SETUP];
    
    // wait until launch, then start running kevent loop
    [_lock lockWhenCondition:TLM_KQ_WAITING];

    struct timespec ts;
    // 1 second timeout
    ts.tv_sec = 1;
    ts.tv_nsec = 0;
    
    struct kevent event;
    
    NSMutableData *errBuffer = [NSMutableData data];
    NSMutableData *outBuffer = [NSMutableData data];
    
    int eventCount;
    bool errEOF = false, outEOF = false;
    
    // most of this code is copied directly from tlu_ipctask
    while ((eventCount = kevent(kq_fd, NULL, 0, &event, 1, &ts)) != -1) {
                        
        /*
         If still running, wait for the next timeout; this is basically insurance,
         since it's not clear if EV_EOF is always set.
         */
        if (0 == eventCount && [self isRunning])
            continue;
        
        size_t len = event.data;
        
        /*
         Receive zero-length on the last (non-timeout) pass, but it's not clear
         if this is sufficient cause to bail out of the loop.  It's safer to
         rely on EV_EOF and -isRunning, and just skip the read(2).  There actually
         is a flood of zero-length reads that was causing 100% CPU usage, before
         I added the EV_EOF check.
         */
        
        if (len > 0) {

            char sbuf[2048];
            char *buf = (len > sizeof(sbuf)) ? malloc(len) : sbuf;
            len = read(event.ident, buf, len);
                    
            if (event.ident == (unsigned)fdo) {
                [outBuffer appendBytes:buf length:len];
            }
            else if (event.ident == (unsigned)fde) {
                [errBuffer appendBytes:buf length:len];
            }

            if (buf != sbuf) free(buf);
        }
        
        // received independently for each descriptor
        if (event.flags & EV_EOF) {
            
            // tried modifying the event list here, but didn't do much
            if (event.ident == (unsigned)fdo) {
                outEOF = true;
            }
            else if (event.ident == (unsigned)fde) {
                errEOF = true;
            }
        }
                
        // if not running or both pipes are widowed, bail out
        if ((outEOF && errEOF) || [self isRunning] == NO)
            break;
                
    }
    
    if (-1 == eventCount)
        perror(__func__);
    
    events[0].flags = EV_DELETE;
    events[1].flags = EV_DELETE;
    kevent(kq_fd, events, TLM_EVENT_COUNT, NULL, 0, NULL);
    close(kq_fd);
    
    _outputData = [outBuffer copy];
    _errorData = [errBuffer copy];
    [_lock unlockWithCondition:TLM_KQ_FINISHED];
    
    [pool release];
}

- (void)launch
{
    // The point here is to keep NSTask's asynchronous execution semantics while removing the tedious pipe handling.

    [self setStandardOutput:[NSPipe pipe]];
    [self setStandardError:[NSPipe pipe]];
    
    // make sure to initialize this before entering the thread...
    _lock = [[NSConditionLock alloc] initWithCondition:TLM_KQ_INIT];
    
    /*
     Use a separate thread for each task, since NSFileHandle may use a single thread as a funnel point for all channels 
     in readToEndOfFileInBackgroundAndNotifyForModes:, in which case we get hosed when trying to run a TLMTask from 
     separate threads if the first one is blocking.  Not clear if this is a problem prior to 10.6, but I ran into it
     when one of the 2009 pretest mirrors was down.
     */
    [NSThread detachNewThreadSelector:@selector(_readOutputAndErrorChannels) toTarget:self withObject:nil];
    [_lock lockWhenCondition:TLM_KQ_SETUP];
    [super launch];
    
    // now we're waiting for stdout and stderr
    [_lock unlockWithCondition:TLM_KQ_WAITING];
}  

- (NSData *)outputData
{
    if ([_lock condition] != TLM_KQ_FINISHED) {
        [_lock lockWhenCondition:TLM_KQ_FINISHED];
        [_lock unlock];
    }
    return _outputData;
}

- (NSData *)errorData
{
    if ([_lock condition] != TLM_KQ_FINISHED) {
        [_lock lockWhenCondition:TLM_KQ_FINISHED];
        [_lock unlock];
    }
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
