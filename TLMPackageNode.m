//
//  TLMPackageNode.m
//  PackageOutline
//
//  Created by Adam Maxwell on 12/22/08.
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

#import "TLMPackageNode.h"
#import "TLMDatabasePackage.h"

@implementation TLMPackageNode

@synthesize name = _name;
@synthesize fullName = _fullName;
@synthesize installed = _installed;
@synthesize hasParent = _hasParent;
@synthesize hasMixedStatus = _hasMixedStatus;
@synthesize package = _package;
@synthesize shortDescription = _shortDescription;

static NSString *_separatorString = nil;

+ (void)initialize
{
    if (nil == _separatorString)
        _separatorString = [[NSString alloc] initWithFormat:@"%C", (unichar)0x271D];
}

+ (NSSet *)keyPathsForValuesAffectingStatus
{
    return [NSSet setWithObject:@"hasMixedStatus"];
}

- (BOOL)matchesSearchString:(NSString *)searchTerm
{
    NSMutableString *string = [NSMutableString new];
    [string appendString:_name];
    [string appendString:_separatorString];
    if ([self shortDescription])
        [string appendString:[self shortDescription]];
    
    for (TLMPackageNode *child in _children) {
        [string appendString:_separatorString];
        [string appendString:[child name]];
        [string appendString:_separatorString];
        if ([child shortDescription])
            [string appendString:[child shortDescription]];
    }
    
    BOOL matches = [string rangeOfString:searchTerm options:NSCaseInsensitiveSearch].length > 0;
    [string release];
    return matches;
}

- (void)dealloc
{
    [_name release];
    [_fullName release];
    [_children release];
    [_package release];
    [_shortDescription release];
    [super dealloc];
}

- (NSString *)infoName
{
    return [self fullName];
}

- (NSUInteger)numberOfChildren;
{
    return [_children count];
}

- (id)childAtIndex:(NSUInteger)anIndex;
{
    return [_children objectAtIndex:anIndex];
}

- (void)addChild:(id)aChild;
{
    NSParameterAssert(aChild);
    if (nil == _children) _children = [NSMutableArray new];
    [_children addObject:aChild];
    
    // many of the bin packages have multiple architectures, so only one may be installed
    NSUInteger installCount = 0;
    for (id child in _children) {
        if ([child isInstalled])
            installCount++;
    }
    
    if ([_children count] == installCount) {
        [self setInstalled:YES];
        _hasMixedStatus = NO;
    }
    else if (installCount) {
        [self setInstalled:NO];
        _hasMixedStatus = YES;
    }
    else {
        [self setInstalled:NO];
        _hasMixedStatus = NO;
    }

}

- (NSString *)status
{
    if ([self hasMixedStatus]) 
        return NSLocalizedString(@"Mixed", @"status for expandable outline row with installed and uninstalled packages");
    else if ([self isInstalled])
        return NSLocalizedString(@"Installed", @"status for package");
    else
        return NSLocalizedString(@"Not installed", @"status for package");
}

@end
