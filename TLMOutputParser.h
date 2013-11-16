//
//  TLMOutputParser.h
//  TeX Live Utility
//
//  Created by Adam Maxwell on 12/6/08.
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

#import <Cocoa/Cocoa.h>
#import "TLMPackage.h"

@protocol TLMInfoOutput

- (NSAttributedString *)attributedString;

// arrays of NSURL objects; only files which exist are returned
- (NSArray *)runFiles;
- (NSArray *)sourceFiles;
- (NSArray *)docFiles;

@end


@interface TLMOutputParser : NSObject

// result is guaranteed non-nil, but raises if outputLine is nil
// for output of `tlmgr update --list`
+ (TLMPackage *)packageWithUpdateLine:(NSString *)outputLine;

// returns a plain string if parsing fails, raises if infoString is nil
// for output of `tlmgr show'
+ (id <TLMInfoOutput>)outputWithInfoString:(NSString *)infoString docURLs:(NSArray *)docURLs;

// returns an array of TLMPackageNodes, each of which may have child nodes
// for output of `tlmgr list`
+ (NSArray *)nodesWithListLines:(NSArray *)listLines;

+ (NSArray *)backupNodesWithListLines:(NSArray *)listLines;

@end
