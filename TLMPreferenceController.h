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

extern NSString * const TLMTexBinPathPreferenceKey;
extern NSString * const TLMUseRootHomePreferenceKey;
extern NSString * const TLMInfraPathPreferenceKey;
extern NSString * const TLMUseSyslogPreferenceKey;
extern NSString * const TLMFullServerURLPreferenceKey;

@interface TLMPreferenceController : NSWindowController 
{
@private
    NSPathControl       *_texbinPathControl;
    NSComboBox          *_serverComboBox;
    NSButton            *_rootHomeCheckBox;
    NSButton            *_useSyslogCheckBox;
    NSArray             *_servers;
    NSPanel             *_progressPanel;
    NSProgressIndicator *_progressIndicator;
    NSTextField         *_progressField;
    BOOL                 _hasPendingServerEdit;
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
@property (nonatomic, retain) IBOutlet NSPanel *_progressPanel;
@property (nonatomic, retain) IBOutlet NSProgressIndicator *_progressIndicator;
@property (nonatomic, retain) IBOutlet NSTextField *_progressField;

// composes TLMServerURLPreferenceKey and TLMServerPathPreferenceKey
@property (readonly) NSURL *defaultServerURL;

// returns the local tlpdb location, suitable for --location
@property (readonly) NSURL *offlineServerURL;

// adds tlmgr to TLMTexBinPathPreferenceKey, standardizes path
@property (readonly) NSString *tlmgrAbsolutePath;

// adds texdoc to TLMTexBinPathPreferenceKey, standardizes path
@property (readonly) NSString *texdocAbsolutePath;

@end
