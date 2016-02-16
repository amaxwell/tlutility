//
//  TLMAutobackupController.h
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 09/26/10.
/*
 This software is Copyright (c) 2010-2016
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
    TLMAutobackupCancelled = 0,
    TLMAutobackupUnchanged = 1,
    TLMAutobackupChanged   = (1 << 1),
    TLMAutobackupIncreased = (1 << 2),
    TLMAutobackupDecreased = (1 << 3),
    TLMAutobackupPrune     = (1 << 4),
    TLMAutobackupDisabled  = (1 << 5)
};
typedef NSInteger TLMAutobackupReturnCode;

@interface TLMAutobackupController : NSWindowController 
{
@private
    NSButton    *_enableCheckbox;
    NSTextField *_countField;
    NSButton    *_pruneCheckbox;
    NSInteger    _initialBackupCount;
    NSInteger    _backupCount;
}

- (IBAction)enableAction:(id)sender;
- (IBAction)changeCount:(id)sender;
- (IBAction)cancel:(id)sender;
- (IBAction)accept:(id)sender;

@property (nonatomic, retain) IBOutlet NSButton *_enableCheckbox;
@property (nonatomic, retain) IBOutlet NSTextField *_countField;
@property (nonatomic, retain) IBOutlet NSButton *_pruneCheckbox;
@property (nonatomic) NSInteger backupCount;
@property (nonatomic, readonly) NSInteger initialBackupCount;

@end

@interface TLMBackupCountFormatter : NSNumberFormatter
@end

