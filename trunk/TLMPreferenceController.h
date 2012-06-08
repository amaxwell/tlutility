//
//  TLMPreferenceController.h
//  TeX Live Utility
//
//  Created by Adam Maxwell on 12/08/08.
/*
 This software is Copyright (c) 2008-2012
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
extern NSString * const TLMInfraPathPreferenceKey;
extern NSString * const TLMUseSyslogPreferenceKey;
extern NSString * const TLMFullServerURLPreferenceKey;
extern NSString * const TLMDisableVersionMismatchWarningKey;
extern NSString * const TLMAutoInstallPreferenceKey;
extern NSString * const TLMAutoRemovePreferenceKey;
extern NSString * const TLMNetInstallerPathPreferenceKey;
extern NSString * const TLMShouldListTLCritical;
extern NSString * const TLMTLCriticalRepository;
extern NSString * const TLMEnableNetInstall;
extern NSString * const TLMShowLogWindowPreferenceKey;
extern NSString * const TLMLastUpdmapVersionShownKey;
extern NSString * const TLMEnableUserUpdmapPreferenceKey;
extern NSString * const TLMDisableUpdmapAlertPreferenceKey;

@interface TLMPreferenceController : NSWindowController <NSComboBoxDataSource, NSOpenSavePanelDelegate>
{
@private
    NSPathControl       *_texbinPathControl;
    NSButton            *_useSyslogCheckBox;
    NSButton            *_autoinstallCheckBox;
    NSButton            *_autoremoveCheckBox;
}

+ (TLMPreferenceController *)sharedPreferenceController;
- (IBAction)changeTexBinPath:(id)sender;
- (IBAction)toggleUseSyslog:(id)sender;
- (IBAction)toggleAutoinstall:(id)sender;
- (IBAction)toggleAutoremove:(id)sender;

@property (nonatomic, retain) IBOutlet NSPathControl *_texbinPathControl;
@property (nonatomic, retain) IBOutlet NSButton *_useSyslogCheckBox;
@property (nonatomic, retain) IBOutlet NSButton *_autoinstallCheckBox;
@property (nonatomic, retain) IBOutlet NSButton *_autoremoveCheckBox;

@end
