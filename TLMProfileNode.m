//
//  TLMProfileNode.m
//  TeX Live Utility
//
//  Created by Adam Maxwell on 09/12/09.
/*
 This software is Copyright (c) 2009-2016
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

#import "TLMProfileNode.h"

@interface TLMProfileNode ()
@property (readwrite, copy) NSString *name;
@property (readwrite, copy) NSString *key;
@property (readwrite, copy) NSArray *children;
@property (readwrite) TLMProfileType type;
@end


@implementation TLMProfileNode

@synthesize name = _name;
@synthesize value = _value;
@synthesize key = _key;
@synthesize children = _children;
@synthesize type = _type;

+ (id)_leafNodeWithDictionary:(NSDictionary *)dict
{
    NSString *type = [dict objectForKey:@"type"];
    TLMProfileType profileType;
    if ([type isEqualToString:@"collection"]) {
        profileType = TLMProfileCollectionType;
    }
    else if ([type isEqualToString:@"documentation"]) {
        profileType = TLMProfileDocumentationType;
    }
    else if ([type isEqualToString:@"language"]) {
        profileType = TLMProfileLanguageType;
    }
    else if ([type isEqualToString:@"option"]) {
        profileType = TLMProfileOptionType;
    }
    else if ([type isEqualToString:@"variable"]) {
        profileType = TLMProfileVariableType;
    }
    else {
        return nil;
    }

    TLMProfileNode *node = [[self new] autorelease];
    [node setType:profileType];
    
    for (NSString *key in [NSArray arrayWithObjects:@"name", @"key", @"value", nil])
        [node setValue:[dict objectForKey:key] forKey:key];
    
    return node;
}

+ (TLMProfileNode *)newDefaultProfileWithMetadata:(NSDictionary **)metadata;
{
    NSDictionary *profile = [NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"texlive.profile" ofType:@"plist"]];
    if (metadata) *metadata = NULL;
    
    TLMProfileNode *rootNode = [TLMProfileNode new];
    [rootNode setType:TLMProfileRoot];
    NSMutableArray *groups = [NSMutableArray arrayWithCapacity:[profile count]];
    for (NSString *key in profile) {
        
        if ([key hasPrefix:@"com.googlecode.mactlmgr"]) {
            
            if (metadata)
                *metadata = [[[profile objectForKey:key] retain] autorelease];
            
            // don't add a node for this
            continue;
        }
        
        TLMProfileNode *groupNode = [TLMProfileNode new];
        [groupNode setName:key];
        TLMProfileType groupNodeType = TLMProfileRoot;
        
        NSArray *profileItems = [profile objectForKey:key];
        NSMutableArray *profileNodes = [NSMutableArray arrayWithCapacity:[profileItems count]];
        
        for (NSDictionary *item in profileItems) {
            TLMProfileNode *leaf = [self _leafNodeWithDictionary:item];
            if (leaf) {
                [profileNodes addObject:leaf];  
                groupNodeType |= [leaf type];
            }
        }
        
        [groupNode setChildren:profileNodes];
        [groupNode setType:groupNodeType];
        // skip empty ones (options)
        if ([profileNodes count])
            [groups addObject:groupNode];
        [groupNode release];
    }
    [rootNode setChildren:groups];
    return rootNode;
}

static TLMProfileNode * __findNodeForType(TLMProfileNode *rootNode, const TLMProfileType type)
{
    for (TLMProfileNode *node in [rootNode children])
        if ([node type] & type) return node;
    
    return nil;
}

+ (NSString *)profileStringWithRoot:(TLMProfileNode *)rootNode
{
    NSMutableString *string = [NSMutableString string];
    [string appendFormat:@"# texlive.profile written on %@ by %@\n", [NSDate date], NSUserName()];
    [string appendString:@"# selected_scheme scheme-full"];
    
    TLMProfileNode *node;
    
    node = __findNodeForType(rootNode, TLMProfileVariableType);
    [string appendFormat:@"%@\n", [node profileString]];
    
    [string appendString:@"binary-universal-darwin 1\n"];
    
    node = __findNodeForType(rootNode, TLMProfileCollectionType);
    [string appendFormat:@"%@\n", [node profileString]];
    
    node = __findNodeForType(rootNode, TLMProfileDocumentationType);
    [string appendFormat:@"%@\n", [node profileString]];

    node = __findNodeForType(rootNode, TLMProfileLanguageType);
    [string appendFormat:@"%@\n", [node profileString]];
    
    node = __findNodeForType(rootNode, TLMProfileOptionType);
    [string appendString:[node profileString]];

    return string;
}

- (NSString *)profileString
{
    // leaf node
    if ([self numberOfChildren] == 0)
        return [NSString stringWithFormat:@"%@ %@", [self key], [self value]];
    
    // parent node; walk the tree recursively and add a line for each
    NSMutableString *string = [NSMutableString string];
    for (TLMProfileNode *node in [self children])
        [string appendFormat:@"%@\n", [node profileString]];
    
    // trim the trailing newline
    CFStringTrimWhitespace((CFMutableStringRef)string);
    
    return string;
}

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (self) {
        _type = [coder decodeIntegerForKey:@"_type"];
        _name = [[coder decodeObjectForKey:@"_name"] retain];
        _key = [[coder decodeObjectForKey:@"_key"] retain];
        _children = [[coder decodeObjectForKey:@"_children"] retain];
        _value = [[coder decodeObjectForKey:@"_value"] retain];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInteger:_type forKey:@"_type"];
    [coder encodeObject:_name forKey:@"_name"];
    [coder encodeObject:_key forKey:@"_key"];
    [coder encodeObject:_children forKey:@"_children"];
    [coder encodeObject:_value forKey:@"_value"];
}

- (void)dealloc
{
    [_name release];
    [_key release];
    [_value release];
    [_children release];
    [super dealloc];
}

- (NSUInteger)numberOfChildren { return [_children count]; }

- (id)childAtIndex:(NSUInteger)anIndex { return [_children objectAtIndex:anIndex]; }

@end
