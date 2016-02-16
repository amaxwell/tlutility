//
//  TLMDatabasePackage.h
//  tlpdb_test
//
//  Created by Adam R. Maxwell on 06/08/11.
/*
 This software is Copyright (c) 2011-2016
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
#import "TLMOutputParser.h"

@interface TLMDatabasePackage : NSObject <TLMInfoOutput>
{
@private
    NSMutableDictionary *_dictionary;
}

- (TLMDatabasePackage *)initWithDictionary:(NSDictionary *)dict;

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *category;
@property (nonatomic, readonly) NSString *shortDescription;
@property (nonatomic, readonly) NSString *longDescription;
@property (nonatomic, readonly) NSString *catalogue;
@property (nonatomic, readonly) NSNumber *relocated;
@property (nonatomic, readonly) NSNumber *revision;
@property (nonatomic, readonly) NSArray *depends;
@property (nonatomic, readonly) NSString *catalogueVersion;

// underlying paths are modified to return file URLs
// only files that exist on disk are returned
@property (nonatomic, readonly) NSArray *runFiles;
@property (nonatomic, readonly) NSArray *sourceFiles;
@property (nonatomic, readonly) NSArray *docFiles;

@end
