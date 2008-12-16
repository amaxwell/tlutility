//
//  TLMOperations.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/6/08.
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

#import "TLMOperation.h"
#import "BDSKTask.h"
#import "TLMPreferenceController.h"
#import "TLMLogServer.h"

NSString * const TLMOperationFinishedNotification = @"TLMOperationFinishedNotification";

static char _TLMOperationFinishedContext;

@implementation TLMOperation

@synthesize outputData = _outputData;
@synthesize errorData = _errorData;
@synthesize failed = _failed;

+ (void)initialize
{
    static bool didInit = false;
    if (true == didInit) return;
    didInit = true;
    const char *path = getenv("PATH");
    
    // if we don't add this to the path, tlmgr falls all over itself when it tries to run kpsewhich
    if (path) {
        NSString *texbinPath = [[NSUserDefaults standardUserDefaults] objectForKey:TLMTexBinPathPreferenceKey];
        NSString *newPath = [[NSString stringWithUTF8String:path] stringByAppendingFormat:@":%@", texbinPath];
        setenv("PATH", [newPath fileSystemRepresentation], 1);
    }
}

- (id)init
{
    self = [super init];
    if (self) {
        [self setFailed:NO];
        [self addObserver:self forKeyPath:@"isFinished" options:0 context:&_TLMOperationFinishedContext];
    }
    return self;
}

- (id)initWithCommand:(NSString *)absolutePath options:(NSArray *)options
{
    NSParameterAssert(absolutePath);
    NSParameterAssert(options);
    
    NSFileManager *fm = [NSFileManager new];
    BOOL exists = [fm isExecutableFileAtPath:absolutePath];
    [fm release];

    if (NO == exists) {
        TLMLog(@"TLMOperation", @"No executable file at %@", absolutePath);
        [self release];
        self = nil;
    }
    else if ((self = [super init])) {
        _task = [BDSKTask new];
        [_task setLaunchPath:absolutePath];
        [_task setArguments:options];
        [self setFailed:NO];
        [self addObserver:self forKeyPath:@"isFinished" options:0 context:&_TLMOperationFinishedContext];
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

- (void)_stdoutDataAvailable:(NSNotification *)aNote
{
    NSData *outputData = [[aNote userInfo] objectForKey:NSFileHandleNotificationDataItem];
    if ([outputData length])
         [self setOutputData:outputData];    
}

- (void)_stderrDataAvailable:(NSNotification *)aNote
{
    NSData *outputData = [[aNote userInfo] objectForKey:NSFileHandleNotificationDataItem];
    if ([outputData length]) {
        [self setErrorData:outputData];    
        TLMLog(@"TLMOperation", @"%@", [self errorMessages]);
    }
}

- (NSString *)errorMessages
{
    @synchronized(self) {
        if (nil == _errorMessages && [_errorData length]) {
            _errorMessages = [[NSString alloc] initWithData:_errorData encoding:NSUTF8StringEncoding];
            if (nil == _errorMessages)
                _errorMessages = [[NSString alloc] initWithData:_errorData encoding:NSMacOSRomanStringEncoding];
        }
    }
    return _errorMessages;
}

- (void)main
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
   
    NSParameterAssert(nil != _task);
    
    sig_t previousSignalMask = signal(SIGPIPE, SIG_IGN);
    
    [_task setStandardOutput:[NSPipe pipe]];
    [_task setStandardError:[NSPipe pipe]];
    NSFileHandle *outfh = [[_task standardOutput] fileHandleForReading];
    NSFileHandle *errfh = [[_task standardError] fileHandleForReading];
    
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(_stdoutDataAvailable:) name:NSFileHandleReadToEndOfFileCompletionNotification object:outfh];
    [nc addObserver:self selector:@selector(_stderrDataAvailable:) name:NSFileHandleReadToEndOfFileCompletionNotification object:errfh];

    NSString *rlmode = @"TLMOperationRunLoopMode";
    [outfh readToEndOfFileInBackgroundAndNotifyForModes:[NSArray arrayWithObject:rlmode]];
    [errfh readToEndOfFileInBackgroundAndNotifyForModes:[NSArray arrayWithObject:rlmode]];
    
    int status = -1;
    [_task launch];
    if ([_task isRunning]) {
        
        // Reimplement -[NSTask waitUntilExit] so we can handle -[NSOperation cancel]
        while ([_task isRunning] && [self isCancelled] == NO) {
            // using +dateWithTimeIntervalSinceNow: can cause the autorelease pool to blow up
            NSDate *expireDate = [[NSDate alloc] initWithTimeIntervalSinceNow:0.1];
            [[NSRunLoop currentRunLoop] runMode:rlmode beforeDate:expireDate];
            [expireDate release];
        }
        
        if ([self isCancelled]) {
            [_task terminate];
        }
        else {
            // not cancelled, but make sure it's really done before calling -terminationStatus
            [_task waitUntilExit];
            status = [_task terminationStatus];
        }
    }

    signal(SIGPIPE, previousSignalMask);

    [nc removeObserver:self name:NSFileHandleReadToEndOfFileCompletionNotification object:outfh];
    [nc removeObserver:self name:NSFileHandleReadToEndOfFileCompletionNotification object:errfh];
    
    // don't try dealing with partial text data
    if ([self isCancelled]) {
        [self setOutputData:nil];
    } else if (0 != status) {
        TLMLog(@"TLMOperation", @"termination status of task %@ was %d", [_task launchPath], status);
        [self setFailed:YES];
    }
    
    [pool release];
}

@end
