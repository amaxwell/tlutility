//
//  TLMRemoveOperation.m
//  TeX Live Utility
//
//  Created by Adam Maxwell on 12/25/08.
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

#import "TLMRemoveOperation.h"
#import "TLMEnvironment.h"

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
        _outputLines = [NSMutableArray new];
    }
    return self;
}

- (void)dealloc
{
    [_packageNames release];
    [_outputLines release];
    [super dealloc];
}

- (void)server:(TLMLogServer *)server receivedLine:(NSString *)msg;
{
    @synchronized(_outputLines) {
        if (msg) [_outputLines addObject:msg];
    }
}

// return nil if this line doesn't contain a package name (handles old and new stdout)
- (NSString *)_packageNameFromLine:(NSString *)line
{
#define REMOVE_TOKEN @"remove "
    
    NSString *package = nil;
    if ([line hasPrefix:REMOVE_TOKEN]) {
        /*
         remove 12many
         remove a0poster
         */
        package = [line substringFromIndex:[REMOVE_TOKEN length]];
    }
    else if ([line hasPrefix:@"["]) {
        /*
         [1/1, ??:??/??:??] remove: 12many
         [2/1, 00:00/00:00] remove: a0poster
         */
        NSScanner *scanner = [[NSScanner alloc] initWithString:line];
        // we already know it starts with an opening bracket, so just skip to the closing bracket
        if ([scanner scanUpToString:@"]" intoString:NULL]) {
            [scanner scanString:@"]" intoString:NULL];
            if ([scanner scanString:@"remove:" intoString:NULL] && [scanner isAtEnd] == NO)
                package = [line substringFromIndex:[scanner scanLocation] + 1];
        }
        [scanner release];
    }
    return package;
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
     
     This is a moderately fragile system, as we are parsing output that is
     not guaranteed to be machine-readable.
     
     At least as of TL 2021, the stdout format has changed:
     
         $ tlmgr remove --force 12many a0poster
         tlmgr: saving backups to /usr/local/texlive/2021/tlpkg/backups
         tlmgr: 12many is needed by collection-mathscience
         tlmgr: removing it anyway, due to --force
         tlmgr: a0poster is needed by collection-latexextra
         tlmgr: removing it anyway, due to --force
         [1/1, ??:??/??:??] remove: 12many
         [2/1, 00:00/00:00] remove: a0poster
         tlmgr: ultimately removed these packages: 12many a0poster
         running mktexlsr ...
         done running mktexlsr.
         running mtxrun --generate ...
         done running mtxrun --generate.
         tlmgr: package log updated: /usr/local/texlive/2021/texmf-var/web2c/tlmgr.log

     */
    
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    // stop receiving messages as soon as -main is completed
    [[TLMLogServer sharedServer] registerClient:self withIdentifier:(uintptr_t)self];
    [super main];
    [[TLMLogServer sharedServer] unregisterClientWithIdentifier:(uintptr_t)self];
    
    [self setOutputData:[[_outputLines componentsJoinedByString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];

    NSMutableSet *unremovedPackages = [NSMutableSet setWithArray:[self packageNames]];

    for (NSString *line in _outputLines) {
        
        NSString *package = [self _packageNameFromLine:line];
        if (package) {
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
