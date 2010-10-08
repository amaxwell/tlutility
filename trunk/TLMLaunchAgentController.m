//
//  TLMLaunchAgentController.m
//  TeX Live Manager
//
//  Created by Adam R. Maxwell on 10/07/10.
/*
 This software is Copyright (c) 2010
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

#import "TLMLaunchAgentController.h"


@implementation TLMLaunchAgentController

@synthesize _enableCheckbox;
@synthesize _allUsersCheckbox;
@synthesize _datePicker;

#define PLIST_NAME @"com.googlecode.mactlmgr.update_check"

static NSString *__TLMPlistPath(NSSearchPathDomainMask domain)
{
    NSString *baseDir = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, domain, YES) lastObject];
    return [[[baseDir stringByAppendingPathComponent:@"LaunchAgents"] stringByAppendingPathComponent:PLIST_NAME] stringByAppendingPathExtension:@"plist"];
}

static NSDictionary * __TLMGetPlist(BOOL *isInstalled, BOOL *allUsers)
{
    if ([[NSFileManager defaultManager] fileExistsAtPath:__TLMPlistPath(NSLocalDomainMask)]) {
        if (isInstalled) *isInstalled = YES;
        if (allUsers) *allUsers = YES;
        return [NSDictionary dictionaryWithContentsOfFile:__TLMPlistPath(NSLocalDomainMask)];
    }
    else if ([[NSFileManager defaultManager] fileExistsAtPath:__TLMPlistPath(NSUserDomainMask)]) {
        if (isInstalled) *isInstalled = YES;
        if (allUsers) *allUsers = NO;
        return [NSDictionary dictionaryWithContentsOfFile:__TLMPlistPath(NSUserDomainMask)];
    }
    if (isInstalled) *isInstalled = NO;
    if (allUsers) *allUsers = NO;
    return [NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:PLIST_NAME ofType:@"plist"]];
}

- (id)init { return [self initWithWindowNibName:[self windowNibName]]; }

- (void)dealloc
{
    [_enableCheckbox release];
    [_allUsersCheckbox release];
    [_datePicker release];
    [super dealloc];
}

- (NSString *)windowNibName { return @"LaunchAgentSheet"; }

- (void)_updateUI
{
    [_enableCheckbox setState:((_status & TLMLaunchAgentEnabled) != 0)];
    [_allUsersCheckbox setState:((_status & TLMLaunchAgentAllUsers) != 0)];
    [_allUsersCheckbox setEnabled:((_status & TLMLaunchAgentEnabled) != 0)];
    [_datePicker setEnabled:((_status & TLMLaunchAgentEnabled) != 0)];
}

- (void)awakeFromNib
{
    BOOL isInstalled, allUsers;
    NSDictionary *plist = __TLMGetPlist(&isInstalled, &allUsers);
    // user could have disabled with launchctl, but that's not my problem (yet)
    if (isInstalled) _status |= TLMLaunchAgentEnabled;
    if (allUsers) _status |= TLMLaunchAgentAllUsers;
    
    NSDateComponents *comps = [[NSDateComponents new] autorelease];
    [comps setHour:[[[plist objectForKey:@"StartCalendarInterval"] objectForKey:@"Hour"] integerValue]];
    [comps setMinute:[[[plist objectForKey:@"StartCalendarInterval"] objectForKey:@"Minute"] integerValue]];
    [_datePicker setDateValue:[[NSCalendar currentCalendar] dateFromComponents:comps]];
    
    [self _updateUI];
}

- (IBAction)enableAction:(id)sender;
{
    _status |= TLMLaunchAgentChanged;
    switch ([_enableCheckbox state]) {
        case NSOnState:
            _status |= TLMLaunchAgentEnabled;
            break;
        case NSOffState:
            _status &= ~TLMLaunchAgentEnabled;
            break;
        default:
            break;
    }
    [self _updateUI];
}

- (IBAction)allUsersAction:(id)sender;
{
    _status |= TLMLaunchAgentChanged;
    switch ([_allUsersCheckbox state]) {
        case NSOnState:
            _status |= TLMLaunchAgentAllUsers;
            break;
        case NSOffState:
            _status &= ~TLMLaunchAgentAllUsers;
            break;
        default:
            break;
    }
    [self _updateUI];
}

- (IBAction)changeDate:(id)sender;
{
    _status |= TLMLaunchAgentChanged;    
}

- (IBAction)cancel:(id)sender;
{
    [NSApp endSheet:[self window] returnCode:TLMLaunchAgentCancelled];
}

- (IBAction)accept:(id)sender;
{
    if ([[self window] makeFirstResponder:nil])
        [NSApp endSheet:[self window] returnCode:_status];
    else
        NSBeep();
}

@end
