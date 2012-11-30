//
//  TLMRemoveOperation.m
//  TeX Live Utility
//
//  Created by Adam Maxwell on 12/25/08.
/*
 This software is Copyright (c) 2008-2012
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

#import "TLMRemoveOperation.h"
#import "TLMEnvironment.h"
#import "TLMLogServer.h"

@implementation TLMRemoveOperation

@synthesize packageNames = _packageNames;

- (id)initWithPackageNames:(NSArray *)packageNames force:(BOOL)force;
{
    NSParameterAssert(packageNames);
    NSString *cmd = [[TLMEnvironment currentEnvironment] tlmgrAbsolutePath]; 
    NSMutableArray *options = [NSMutableArray arrayWithObjects:@"remove", nil];
    if (force) [options addObject:@"--force"];
    [options addObjectsFromArray:packageNames];

    self = [self initWithCommand:cmd options:options];
    if (self) {
        _packageNames = [packageNames copy];        
    }
    return self;
}

- (void)dealloc
{
    [_packageNames release];
    [super dealloc];
}

- (void)appendRemoteMessage:(NSString *)msg
{
    NSMutableData *outputData = [NSMutableData data];
    [outputData appendData:[self outputData]];
    if ([outputData length])
        [outputData appendBytes:"\n" length:1];
    [outputData appendData:[msg dataUsingEncoding:NSUTF8StringEncoding]];
    [self setOutputData:outputData];
}

- (void)main
{
    /*
     
     Failed removal messages go to stderr:
     
	     $ tlmgr remove abstract >/dev/null
	     tlmgr: not removing abstract, needed by collection-latexextra
     
     Successful removal messages go to stdout:
     
	     $ tlmgr remove --force 12many a0poster
	     tlmgr: a0poster is needed by collection-latexextra
	     tlmgr: removing it anyway, due to --force
	     tlmgr: 12many is needed by collection-mathextra
	     tlmgr: removing it anyway, due to --force
	     remove 12many
	     remove a0poster
	     tlmgr: actually removed these packages: 12many a0poster
	     tlmgr: package log updated at /usr/local/texlive/2012/texmf-var/web2c/tlmgr.log
	     running mktexlsr ...
	     done running mktexlsr.
	     running mtxrun --generate ...
	     done running mtxrun --generate.
     
     This is a really fragile system, for multiple reasons:
     
     1) we are parsing standard output that is not machine-readable
     
     2) we pass the address of this object to tlu_ipctask and read it
        back over DO, then dereference it in TLMLogMessageServer
     
     3) appending to stderr is not thread-safe
     
     However, the only dangerous assumption is implicit in the second point above,
     namely that this operation object is still live when TLMLogMessageServer gets
     the incoming message. In general, that should always be a reasonable assumption,
     but it would be safer to have an external lookup table.
     
     Thread safety is a non-issue, since TLMAuthorizedOperation doesn't expect stdout,
     and TLMLogMessageServer is running in a dedicated thread.

     */
    
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [super main];
    NSString *outputString = [[[NSString alloc] initWithData:[self outputData] encoding:NSUTF8StringEncoding] autorelease];
    NSArray *errorLines = [outputString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableSet *unremovedPackages = [NSMutableSet setWithArray:[self packageNames]];

#define REMOVE_TOKEN @"remove "

    for (NSString *line in errorLines) {
        
        if ([line hasPrefix:REMOVE_TOKEN]) {
            NSString *package = [line substringFromIndex:[REMOVE_TOKEN length]];
            if ([unremovedPackages containsObject:package] == NO)
                TLMLog(__func__, @"ERROR: expected to see %@ in list of packages to remove", package);
            [unremovedPackages removeObject:package];
        }
        
    }
    
    if ([unremovedPackages count]) {
        [self setFailed:YES];
        TLMLog(__func__, @"ERROR: failed to remove packages %@ (requested removal of %@)", unremovedPackages, [self packageNames]);
    }

    [pool release];
}

@end
