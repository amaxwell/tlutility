//
//  TLMBackupNode.m
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 10/14/10.
/*
 This software is Copyright (c) 2010-2016
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

#import "TLMBackupNode.h"

@implementation TLMBackupNode

@synthesize name = _name;
@synthesize version = _version;
@synthesize date = _date;

- (id)init
{
    self = [super init];
    if (self) {
        _children = [NSMutableArray new];
    }
    return self;
}

- (void)dealloc
{
    [_name release];
    [_children release];
    [_version release];
    [_date release];
    [super dealloc];
}

- (BOOL)matchesSearchString:(NSString *)searchTerm
{
    return [[self name] rangeOfString:searchTerm options:NSCaseInsensitiveSearch].length > 0;
}

- (NSString *)infoName { return [self name]; }

- (NSUInteger)numberOfVersions;
{
    return [_children count];
}

- (NSComparisonResult)compareVersions:(TLMBackupNode *)other
{
    return [[self version] compare:[other version]];
}

- (id)versionAtIndex:(NSUInteger)anIndex;
{
    return [_children objectAtIndex:anIndex];
}

- (void)addChildWithVersion:(NSNumber *)aVersion;
{
    NSParameterAssert(aVersion);
    /*
     Some versions of tlmgr repeat the available backup version numbers, so check
     for duplicates here and bail out if this version already exists.
     */
    for (TLMBackupNode *child in _children) {
        // !!! early return
        if ([[child version] isEqualToNumber:aVersion])
            return;
    }
    
    TLMBackupNode *child = [TLMBackupNode new];
    [child setName:[self name]];
    [child setVersion:aVersion];
    [_children addObject:child];
    // maintain strict sorting by version, which is a proxy for date
    [_children sortUsingSelector:@selector(compareVersions:)];
    [child release];
}

@end
