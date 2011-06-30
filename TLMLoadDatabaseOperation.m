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
#import "TLMEnvironment.h"
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
        _dumpError = [NSMutableData new];
        _parseError = [NSMutableData new];
    }
    return self;
}

- (void)dealloc
{
    [_updateURL release];
    [_packageNodes release];
    [_dumpError release];
    [_parseError release];
    [super dealloc];
}

- (void)_dumpDataAvailable:(NSNotification *)aNote
{
    NSData *data = [[aNote userInfo] objectForKey:NSFileHandleNotificationDataItem];
    if ([data length])
        [_dumpError appendData:data];
    [[aNote object] readInBackgroundAndNotify];
}

- (void)_parseDataAvailable:(NSNotification *)aNote
{
    NSData *data = [[aNote userInfo] objectForKey:NSFileHandleNotificationDataItem];
    if ([data length])
        [_parseError appendData:data];
    [[aNote object] readInBackgroundAndNotify];    
}

// nil URL indicates the local db
- (BOOL)_dumpDatabaseAtURL:(NSURL *)aURL asPropertyList:(NSString *)absolutePath
{
    NSString *tlmgrPath = [[TLMEnvironment currentEnvironment] tlmgrAbsolutePath];

    BDSKTask *dumpTask = [[BDSKTask new] autorelease];
    [dumpTask setLaunchPath:tlmgrPath];
    NSArray *arguments = nil;
    if (aURL)
        arguments = [NSArray arrayWithObjects:@"--repository", [[self updateURL] absoluteString], @"dump-tlpdb", @"--remote", nil];
    else
        arguments = [NSArray arrayWithObjects:@"dump-tlpdb", @"--local", nil];
    
    [dumpTask setArguments:arguments];
    [dumpTask setStandardOutput:[NSPipe pipe]];
    [dumpTask setStandardError:[NSPipe pipe]];
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(_dumpDataAvailable:) 
                                                 name:NSFileHandleDataAvailableNotification 
                                               object:[[dumpTask standardError] fileHandleForReading]];
    [[[dumpTask standardError] fileHandleForReading] readInBackgroundAndNotify];
    [dumpTask launch];
    
    BDSKTask *parseTask = [[BDSKTask new] autorelease];
    [parseTask setLaunchPath:[[NSBundle mainBundle] pathForAuxiliaryExecutable:@"parse_tlpdb.py"]];
    [parseTask setArguments:[NSArray arrayWithObjects:@"-o", absolutePath, @"-f", @"plist", nil]];
    [parseTask setStandardInput:[[dumpTask standardOutput] fileHandleForReading]];
    [parseTask setStandardError:[NSPipe pipe]];
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(_parseDataAvailable:) 
                                                 name:NSFileHandleDataAvailableNotification 
                                               object:[[parseTask standardError] fileHandleForReading]];
    [[[parseTask standardError] fileHandleForReading] readInBackgroundAndNotify];
    [parseTask launch];
    
    [parseTask waitUntilExit];
    
    // no more runloop running, so won't be picking these up
    [[NSNotificationCenter defaultCenter] removeObserver:self 
                                                    name:NSFileHandleDataAvailableNotification 
                                                  object:[[parseTask standardError] fileHandleForReading]];
    [[NSNotificationCenter defaultCenter] removeObserver:self 
                                                    name:NSFileHandleDataAvailableNotification 
                                                  object:[[dumpTask standardError] fileHandleForReading]];       
    
    // get any residual data
    [_parseError appendData:[[[parseTask standardError] fileHandleForReading] availableData]];
    [_dumpError appendData:[[[dumpTask standardError] fileHandleForReading] availableData]];
    
    if ([_parseError length]) {
        TLMLog(__func__, @"Parse error: %@",[[[NSString alloc] initWithData:_parseError encoding:NSUTF8StringEncoding] autorelease]);
        [_parseError setData:[NSData data]];
    }
    if ([_dumpError length]) {
        TLMLog(__func__, @"Dump error: %@",[[[NSString alloc] initWithData:_dumpError encoding:NSUTF8StringEncoding] autorelease]);
        [_dumpError setData:[NSData data]];
    }
    
    return ([parseTask terminationStatus] == EXIT_SUCCESS);
}

#define DEBUG_TLPDB 0

- (void)main
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
#if DEBUG_TLPDB
    NSString *temporaryPath = [NSString stringWithFormat:@"/tmp/TLMLoadDatabaseOperation_%p.tlpdb", self];
#else
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    NSString *temporaryPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[(id)CFUUIDCreateString(NULL, uuid) autorelease]];
    if (uuid) CFRelease(uuid);
#endif
        
    // can only dump the remote db if we're not in offline mode
    if (NO == _offline) {
                
        if ([self _dumpDatabaseAtURL:[self updateURL] asPropertyList:temporaryPath]) {
            NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:temporaryPath];
            NSString *mirror = [dict objectForKey:@"mirror"];
            if (nil == mirror || [NSURL URLWithString:mirror] == nil)
                TLMLog(__func__, @"Unable to read mirror from tlpdb property list with keys %@", [dict allKeys]);
            else
                [self setUpdateURL:[NSURL URLWithString:mirror]];
            [[TLMDatabase databaseForMirrorURL:[self updateURL]] reloadDatabaseFromPath:temporaryPath];
        }
        else {
            TLMLog(__func__, @"Dumping tlpdb from mirror %@ failed", [self updateURL]);
        } 
    }
    
    // always dump the local db
    if ([self _dumpDatabaseAtURL:nil asPropertyList:temporaryPath]) {
        [[TLMDatabase localDatabase] reloadDatabaseFromPath:temporaryPath];
    }
    else {
        TLMLog(__func__, @"Dumping local tlpdb failed");
    }
    
#if !(DEBUG_TLPDB)
    unlink([temporaryPath saneFileSystemRepresentation]);
#endif

    [pool release];
}

@end
