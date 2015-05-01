//
//  TLMPackage.m
//  TeX Live Utility
//
//  Created by Adam Maxwell on 12/6/08.
/*
 This software is Copyright (c) 2008-2015
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

#import "TLMPackage.h"

@implementation TLMPackage

@synthesize name = _name;
@synthesize status = _status;
@synthesize remoteVersion = _remoteVersion;
@synthesize localVersion = _localVersion;
@synthesize willBeRemoved = _willBeRemoved;
@synthesize installed = _installed;
@synthesize needsUpdate = _needsUpdate;
@synthesize failedToParse = _failedToParse;
@synthesize size = _size;
@synthesize localCatalogueVersion = _localCatalogueVersion;
@synthesize remoteCatalogueVersion = _remoteCatalogueVersion;
@synthesize wasForciblyRemoved = _wasForciblyRemoved;
@synthesize pinned = _pinned;

+ (TLMPackage *)package;
{
    return [[self new] autorelease];
}

static NSString *_separatorString = nil;

+ (void)initialize
{
    if (nil == _separatorString)
        _separatorString = [[NSString alloc] initWithFormat:@"%C", (unichar)0x271D];
}

- (BOOL)matchesSearchString:(NSString *)searchTerm
{
    NSMutableString *string = [NSMutableString new];
    [string appendString:_name];
    [string appendString:_separatorString];
    [string appendString:_status];
    [string appendString:_separatorString];
    // not guaranteed to have these
    if (_remoteVersion) [string appendString:_remoteVersion];
    [string appendString:_separatorString];
    if (_localVersion) [string appendString:_localVersion];
    [string appendString:_separatorString];
    if (_size)[string appendString:[_size description]];
    
    BOOL matches = [string rangeOfString:searchTerm options:NSCaseInsensitiveSearch].length > 0;
    [string release];
    return matches;
}

- (id)copyWithZone:(NSZone *)zone
{
    TLMPackage *new = [TLMPackage new];
    
    new->_name = [_name copyWithZone:zone];
    new->_status = [_status copyWithZone:zone];
    new->_remoteVersion = [_remoteVersion copyWithZone:zone];
    new->_localVersion = [_localVersion copyWithZone:zone];
    new->_size = [_size retain];
    new->_localCatalogueVersion = [_localCatalogueVersion copyWithZone:zone];
    new->_remoteCatalogueVersion = [_remoteCatalogueVersion copyWithZone:zone];
    
    new->_willBeRemoved = _willBeRemoved;
    new->_installed = _installed;
    new->_needsUpdate = _needsUpdate;
    new->_failedToParse = _failedToParse;
    new->_wasForciblyRemoved = _wasForciblyRemoved;
    
    return new;
    
}

- (void)dealloc
{
    [_status release];
    [_name release];
    [_remoteVersion release];
    [_localVersion release];
    [_size release];
    [_localCatalogueVersion release];
    [_remoteCatalogueVersion release];
    [super dealloc];
}

- (NSString *)infoName
{
    return [self name];
}

@end
