//
//  TLMPreferenceController.h
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/08/08.
/*
 This software is Copyright (c) 2008-2009
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

extern NSString * const TLMServerURLPreferenceKey;
extern NSString * const TLMTexBinPathPreferenceKey;
extern NSString * const TLMServerPathPreferenceKey;
extern NSString * const TLMUseRootHomePreferenceKey;
extern NSString * const TLMInfraPathPreferenceKey;
extern NSString * const TLMUseSyslogPreferenceKey;

@interface TLMPreferenceController : NSWindowController 
{
@private
    NSPathControl *_texbinPathControl;
    NSComboBox    *_serverComboBox;
    NSButton      *_rootHomeCheckBox;
    NSButton      *_useSyslogCheckBox;
    NSArray       *_servers;
}

+ (id)sharedPreferenceController;
- (IBAction)changeTexBinPath:(id)sender;
- (IBAction)changeServerURL:(id)sender;
- (IBAction)toggleUseRootHome:(id)sender;
- (IBAction)toggleUseSyslog:(id)sender;

@property (nonatomic, retain) IBOutlet NSPathControl *_texbinPathControl;
@property (nonatomic, retain) IBOutlet NSComboBox *_serverComboBox;
@property (nonatomic, retain) IBOutlet NSButton *_rootHomeCheckBox;
@property (nonatomic, retain) IBOutlet NSButton *_useSyslogCheckBox;

// composes TLMServerURLPreferenceKey and TLMServerPathPreferenceKey
@property (readonly) NSURL *defaultServerURL;

// adds tlmgr to TLMTexBinPathPreferenceKey, standardizes path
@property (readonly) NSString *tlmgrAbsolutePath;

// adds texdoc to TLMTexBinPathPreferenceKey, standardizes path
@property (readonly) NSString *texdocAbsolutePath;

@end
