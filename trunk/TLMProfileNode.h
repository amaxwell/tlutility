//
//  TLMProfileNode.h
//  TeX Live Manager
//
//  Created by Adam Maxwell on 09/12/09.
/*
 This software is Copyright (c) 2009
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

#import <Cocoa/Cocoa.h>

enum {
    TLMProfileRoot              = (1 << 1),
    TLMProfileCollectionType    = (1 << 2),
    TLMProfileDocumentationType = (1 << 3),
    TLMProfileLanguageType      = (1 << 4),
    TLMProfileOptionType        = (1 << 5),
    TLMProfileVariableType      = (1 << 6),
    TLMProfileOtherType         = (1 << 7)
};
typedef NSUInteger TLMProfileType;

@interface TLMProfileNode : NSObject 
{
@private
    TLMProfileType  _type;
    NSString       *_name;
    NSString       *_key;
    NSArray        *_children;
    id              _value;
}

+ (TLMProfileNode *)newDefaultProfile;
+ (NSString *)profileStringWithRoot:(TLMProfileNode *)rootNode;

- (NSUInteger)numberOfChildren;
- (id)childAtIndex:(NSUInteger)anIndex;
- (NSString *)profileString;

@property (readonly) NSString *name;
@property (readonly) TLMProfileType type;
@property (readonly) id value;

@end
