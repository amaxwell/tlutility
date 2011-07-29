//
//  TLMDatabase.h
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 09/13/10.
/*
 This software is Copyright (c) 2010-2011
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

typedef int32_t TLMDatabaseYear;

// returned as the year in case of an error
extern const TLMDatabaseYear TLMDatabaseUnknownYear;

extern NSString * const TLMDatabaseVersionCheckComplete;

@interface TLMDatabase : NSObject 
{
@private
    NSArray         *_packages;
    NSDate          *_loadDate;
    NSURL           *_mirrorURL;
    NSLock          *_downloadLock;
    TLMDatabaseYear  _year;
    BOOL             _isOfficial;
    NSMutableData   *_tlpdbData;
    BOOL             _failed;
    CFAbsoluteTime   _failureTime;
}

+ (TLMDatabase *)localDatabase;
+ (TLMDatabase *)databaseForMirrorURL:(NSURL *)aURL;

+ (NSArray *)packagesByMergingLocalWithMirror:(NSURL *)aURL;
- (void)reloadDatabaseFromPath:(NSString *)absolutePath;

@property (readonly) TLMDatabaseYear texliveYear;
@property (copy) NSArray *packages;
@property (copy) NSURL *mirrorURL;
@property (copy) NSDate *loadDate;
@property (readonly) BOOL failed;
@property (readonly) BOOL isOfficial;

@end
