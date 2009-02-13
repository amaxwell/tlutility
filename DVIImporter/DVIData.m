//
//  DVIData.m
//  DVIImporter
//
//  Created by Adam Maxwell on 05/01/05.
/*
 This software is Copyright (c) 2005
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

#import "DVIData.h"
#include <sys/ioctl.h>

@interface NSFileHandle (NonBlocking)
- (unsigned)availableByteCountNonBlocking;
@end

@implementation NSFileHandle (NonBlocking)

- (unsigned)availableByteCountNonBlocking { 
    int numBytes;
    int fd = [self fileDescriptor];
    if(ioctl(fd, FIONREAD, (char *) &numBytes) == -1)
        [NSException raise: NSFileHandleOperationException
                    format: @"ioctl() Err # %d", errno];

    return numBytes;
}

@end

@implementation DVIData

- (id)init{
    if(self = [super init]){
        theData = [[NSMutableData alloc] init];
    }
    return self;
}

- (void)dealloc{
    [theData release];
    [super dealloc];
}

- (NSData *)dataFromDVI:(NSString *)dviFilePath{

    // note: can't use -mainBundle for a plugin
    NSString *dvi2ttyPath = [[[NSBundle bundleWithIdentifier:@"com.mac.amaxwell.dviimporter"] resourcePath] stringByAppendingPathComponent:@"dvi2tty"];
    
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:dvi2ttyPath];
    //NSLog(@"dvi2ttyPath is %@", dvi2ttyPath);
    // NSLog(@"At %@ dviFilePath is %@", [NSDate date], dviFilePath);
    NSArray *args = [[NSArray alloc] initWithObjects:@"-q", dviFilePath, nil];
    [task setArguments:args];
    [args release];
    
    NSPipe *pipe = [[NSPipe alloc] init];
    
    if(!pipe){
        NSLog(@"%@ failed to create pipe", self);
        [task release];
        return nil;
    }
    
    [task setStandardOutput:pipe];
    
    NSFileHandle *handle = [pipe fileHandleForReading];
    
    volatile BOOL failed = NO;
    NSData *data = nil;
    
    NS_DURING
        // run task in exception handler
        [task launch];

        while((data = [handle availableData]) && [data length]){
            [theData appendData:data];
        }
        
    NS_HANDLER
        NSLog(@"discarding exception %@ which occurred while running dvi2tty", localException);
        failed = YES;
    NS_ENDHANDLER

    // even if we send -terminate immediately, we still need to waitUntilExit, or -terminationStatus may fail
    [task terminate];    
    [task waitUntilExit];
    
    // clean up the pipe
    [pipe release];

    int status = [task terminationStatus];
    if (status != 0)
        NSLog(@"%@ failed.", dvi2ttyPath);
    
    [task release];
    return (failed) ? nil : theData;
    
}

@end
