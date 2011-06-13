//
//  TLMLoadDatabaseOperation.m
//  TeX Live Manager
//
//  Created by Adam R. Maxwell on 06/10/11.
/*
 This software is Copyright (c) 2011
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

#import "TLMLoadDatabaseOperation.h"
#import "BDSKTask.h"
#import "TLMPreferenceController.h"
#import "TLMLogServer.h"
#import "TLMPackageNode.h"
#import "TLMDatabasePackage.h"
#import "TLMDatabase.h"

@interface TLMLoadDatabaseOperation()
@property (readwrite, copy) NSURL *updateURL;
@end

@implementation TLMLoadDatabaseOperation

@synthesize updateURL = _updateURL;

- (id)initWithLocation:(NSURL *)location offline:(BOOL)offline
{
    NSParameterAssert([location absoluteString]);
    self = [super init];
    if (self) {
        [self setUpdateURL:location];
        _offline = offline;
    }
    return self;
}

- (void)dealloc
{
    [_updateURL release];
    [_packageNodes release];
    [super dealloc];
}

- (void)main
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    NSString *tlmgrPath = [[TLMPreferenceController sharedPreferenceController] tlmgrAbsolutePath];
    BDSKTask *dumpTask = nil, *parseTask = nil;
    NSArray *arguments = nil;
    
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    NSString *temporaryPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[(id)CFUUIDCreateString(NULL, uuid) autorelease]];
    if (uuid) CFRelease(uuid);
            
    if (NO == _offline) {
        dumpTask = [[BDSKTask new] autorelease];
        [dumpTask setLaunchPath:tlmgrPath];
        arguments = [NSArray arrayWithObjects:@"--repository", [[self updateURL] absoluteString], @"dump-tlpdb", @"--remote", nil];
        [dumpTask setArguments:arguments];
        [dumpTask setStandardOutput:[NSPipe pipe]];
        [dumpTask launch];
        
        parseTask = [[BDSKTask new] autorelease];
        [parseTask setLaunchPath:[[NSBundle mainBundle] pathForAuxiliaryExecutable:@"parse_tlpdb.py"]];
        [parseTask setArguments:[NSArray arrayWithObjects:@"-o", temporaryPath, @"-f", @"plist", nil]];
        [parseTask setStandardInput:[[dumpTask standardOutput] fileHandleForReading]];
        [parseTask launch];
        
        [parseTask waitUntilExit];

        if ([parseTask terminationStatus] == EXIT_SUCCESS) {
            NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:temporaryPath];
            NSString *mirror = [dict objectForKey:@"mirror"];
            if (nil == mirror || [NSURL URLWithString:mirror] == nil)
                TLMLog(__func__, @"Unable to read mirror from tlpdb property list with keys %@", [dict allKeys]);
            else
                [self setUpdateURL:[NSURL URLWithString:mirror]];
            [[TLMDatabase databaseForURL:[self updateURL]] reloadDatabaseFromPath:temporaryPath];
        }
        else {
            TLMLog(__func__, @"Dumping tlpdb from mirror %@ failed", [self updateURL]);
        }        
    }
        
    dumpTask = [[BDSKTask new] autorelease];
    [dumpTask setLaunchPath:tlmgrPath];
    arguments = [NSArray arrayWithObjects:@"dump-tlpdb", @"--local", nil];
    [dumpTask setArguments:arguments];
    [dumpTask setStandardOutput:[NSPipe pipe]];
    [dumpTask launch];
    
    parseTask = [[BDSKTask new] autorelease];
    [parseTask setLaunchPath:[[NSBundle mainBundle] pathForAuxiliaryExecutable:@"parse_tlpdb.py"]];
    [parseTask setArguments:[NSArray arrayWithObjects:@"-o", temporaryPath, @"-f", @"plist", nil]];
    [parseTask setStandardInput:[[dumpTask standardOutput] fileHandleForReading]];
    [parseTask launch];
    
    [parseTask waitUntilExit];
    
    if ([parseTask terminationStatus] == EXIT_SUCCESS) {
        [[TLMDatabase localDatabase] reloadDatabaseFromPath:temporaryPath];
    }
    else {
        TLMLog(__func__, @"Dumping local tlpdb failed");
    }
    
    unlink([temporaryPath saneFileSystemRepresentation]);

    [pool release];
}

@end
