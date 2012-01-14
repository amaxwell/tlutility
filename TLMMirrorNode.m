//
//  TLMMirrorNode.m
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 11/19/10.
/*
 This software is Copyright (c) 2010-2012
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

#import "TLMMirrorNode.h"


@implementation TLMMirrorNode

@synthesize value = _value;
@synthesize type = _type;
@synthesize status = _status;

- (id)init
{
    self = [super init];
    if (self) {
        _type = -1;
    }
    return self;
}

- (void)dealloc
{
    [_value release];
    [_children release];
    [super dealloc];
}

- (NSString *)description
{
    // ASCII plist description
    NSMutableString *desc = [NSMutableString string];
    [desc appendFormat:@"{\n\ttype = %d;\n\tvalue = \"%@\";", _type, _value];
    if (_children) [desc appendFormat:@"\n\tchildren = %@", _children];
    [desc appendString:@"\n}"];
    return desc;
}

- (NSUInteger)hash { return [_value hash]; }

- (BOOL)isEqual:(id)object
{
    if ([object isKindOfClass:[self class]] == NO)
        return NO;
    
    TLMMirrorNode *other = object;
    
    if (_type != other->_type)
        return NO;
    
    if ((_value != other->_value) && [_value isEqual:other->_value] == NO)
        return NO;

    if ((_children != other->_children) && [_children isEqualToArray:other->_children] == NO)
        return NO;
    
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_value forKey:@"_value"];
    [aCoder encodeInteger:_type forKey:@"_type"];
    [aCoder encodeObject:_children forKey:@"_children"];
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self) {
        _value = [[aDecoder decodeObjectForKey:@"_value"] retain];
        _type = [aDecoder decodeIntegerForKey:@"_type"];
        _children = [[aDecoder decodeObjectForKey:@"_children"] retain];
    }
    return self;
}

- (NSUInteger)numberOfChildren
{
    return [_children count];
}

- (void)addChild:(id)child
{
    NSParameterAssert(child);
    if (nil == _children)
        _children = [NSMutableArray new];
    [_children addObject:child];
}

- (id)childAtIndex:(NSUInteger)idx
{
    return [_children objectAtIndex:idx];
}

- (void)removeChild:(TLMMirrorNode *)child;
{
    [_children removeObject:child];
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)stackbuf count:(NSUInteger)len;
{
    return [_children countByEnumeratingWithState:state objects:stackbuf count:len];
}   

@end
