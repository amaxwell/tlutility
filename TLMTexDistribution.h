//
//  TLMTexDistribution.h
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 04/30/15.
/*
 This software is Copyright (c) 2015
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

#import <Foundation/Foundation.h>

@interface TLMTexDistribution : NSObject
{
    NSString           *_name;
    NSArray            *_scripts;
    NSString           *_installPath;
    NSString           *_texdistPath;
    NSString           *_texdistVersion;
    NSAttributedString *_texdistDescription;
}

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSArray *scripts;
@property (nonatomic, readonly) NSString *installPath;
@property (nonatomic, readonly) NSString *texdistPath;
@property (nonatomic, readonly) NSString *texdistVersion;
@property (nonatomic, readonly) NSAttributedString *texdistDescription;

+ (NSArray *)knownDistributionsInLocalDomain;
- (id)initWithPath:(NSString *)absolutePath architecture:(NSString *)arch;
- (BOOL)isInstalled;
- (BOOL)isDefault;
- (NSString *)architecture;

@end
