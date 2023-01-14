//
//  TLMLaunchAgentController.h
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 10/07/10.
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
    TLMLaunchAgentCancelled   = 0,
    TLMLaunchAgentChanged     = (1 << 1),
    TLMLaunchAgentEnabled     = (1 << 2),
    TLMLaunchAgentDaily       = (1 << 3)
};
typedef NSInteger TLMLaunchAgentReturnCode;

@interface TLMLaunchAgentController : NSWindowController 
{
    NSMatrix                 *_scheduleMatrix;
    NSDatePicker             *_datePicker;
    NSTextField              *_dayField;
    TLMLaunchAgentReturnCode  _status;
    NSString                 *_propertyListPath;
    NSCalendar               *_gregorianCalendar;
}

+ (BOOL)agentInstalled;
+ (BOOL)scriptNeedsUpdate;

// need to call after +scriptNeedsUpdate
// returns nil if no update required
+ (NSString *)pathOfUpdatedAgentForVenturaStupidity;

// returns YES if migration was done (installs new agent & script)
+ (BOOL)migrateLocalToUserIfNeeded;

// absolute paths to bundle resources
+ (NSString *)agentInstallerScriptInBundle;
+ (NSString *)updatecheckerExecutableInBundle;

@property (nonatomic, retain) IBOutlet NSMatrix *_scheduleMatrix;
@property (nonatomic, retain) IBOutlet NSTextField *_dayField;
@property (nonatomic, retain) IBOutlet NSDatePicker *_datePicker;

@property (nonatomic, readonly, copy) NSString *propertyListPath;

- (IBAction)enableAction:(id)sender;
- (IBAction)changeDay:(id)sender;
- (IBAction)changeTime:(id)sender;
- (IBAction)cancel:(id)sender;
- (IBAction)accept:(id)sender;

@end
