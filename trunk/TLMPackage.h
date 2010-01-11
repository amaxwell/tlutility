//
//  TLMPackage.h
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/6/08.
/*
 This software is Copyright (c) 2008-2010
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

@protocol TLMInfo <NSObject>
@property (readonly, copy) NSString *infoName;
@end

@interface TLMPackage : NSObject <TLMInfo>
{
@private
    NSString   *_name;
    NSString   *_status;
    NSString   *_remoteVersion;
    NSString   *_localVersion;
    NSNumber   *_size;
    
    BOOL        _willBeRemoved;
    BOOL        _installed;
    BOOL        _needsUpdate;
    BOOL        _failedToParse;
    BOOL        _wasForciblyRemoved;
}

+ (TLMPackage *)package;
- (BOOL)matchesSearchString:(NSString *)searchTerm;

@property (copy, readwrite) NSString *name;
@property (copy, readwrite) NSString *status;
@property (copy, readwrite) NSString *remoteVersion;
@property (copy, readwrite) NSString *localVersion;
@property (copy, readwrite) NSNumber *size;

// true if no longer present on the server
@property (readwrite) BOOL willBeRemoved;

// true if currently installed on the local system
@property (readwrite, getter = isInstalled) BOOL installed;

// true if currently installed and has an update available
@property (readwrite) BOOL needsUpdate;

// true if tlmgr remove was used, or update was cancelled (failed)
@property (readwrite) BOOL wasForciblyRemoved;

// true if the tlmgr output was not recognizable
@property(readwrite) BOOL failedToParse;

@end
