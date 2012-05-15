//
//  TLMAutobackupController.m
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 09/26/10.
/*
 This software is Copyright (c) 2010-2012
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

#import "TLMAutobackupController.h"
#import "TLMLogServer.h"
#import "TLMTask.h"
#import "TLMEnvironment.h"

@implementation TLMAutobackupController

@synthesize _enableCheckbox;
@synthesize _countField;
@synthesize _pruneCheckbox;
@synthesize backupCount = _backupCount;
@synthesize initialBackupCount = _initialBackupCount;

#define TLM_INFINITY ((unichar)0x221e)

- (id)init
{
    self = [super initWithWindowNibName:[self windowNibName]];
    if (self) {
    }
    return self;
}

- (void)dealloc
{
    [_enableCheckbox release];
    [_countField release];
    [_pruneCheckbox release];
    [super dealloc];
}

- (NSString *)windowNibName { return @"AutobackupSheet"; }

- (void)updateUI
{
    [_countField setObjectValue:[NSNumber numberWithInteger:[self backupCount]]];    
        
    if ([self backupCount] != 0) {
        [_enableCheckbox setState:NSOnState];
        [_countField setEnabled:YES];
    }
    else {
        [_enableCheckbox setState:NSOffState];
        [_countField setEnabled:NO];
    }
}

- (void)awakeFromNib
{
    NSString *cmd = [[TLMEnvironment currentEnvironment] tlmgrAbsolutePath];
    
    // owner's responsiblity to validate this before showing the sheet
    NSParameterAssert([[NSFileManager defaultManager] isExecutableFileAtPath:cmd]);
    
    TLMTask *task = [[TLMTask new] autorelease];
    [task setLaunchPath:cmd];
    [task setArguments:[NSArray arrayWithObjects:@"option", @"autobackup", nil]];    
    [task launch];
    [task waitUntilExit];
    
    /*
     froude:~ amaxwell$ tlmgr option autobackup 2>/dev/null
     Number of backups to keep (autobackup): 
     froude:~ amaxwell$ sudo tlmgr option autobackup 1
     Password:
     tlmgr: setting option autobackup to 1.
     froude:~ amaxwell$ tlmgr option autobackup 2>/dev/null
     Number of backups to keep (autobackup): 1
    */
    
    NSInteger ret = [task terminationStatus];
    if (0 != ret) {
        TLMLog(__func__, @"Unable to determine autobackup state");
    }
    else if ([task outputString]) {
        NSScanner *scanner = [NSScanner scannerWithString:[task outputString]];
        [scanner scanUpToString:@":" intoString:NULL];
        [scanner scanString:@":" intoString:NULL];
        if ([scanner scanInteger:&_backupCount] == NO)
            [self setBackupCount:0];
    }
    else {
        [self setBackupCount:0];
    }

    TLMLog(__func__, @"Old autobackup setting: keep %ld backups", (long)_backupCount);
    _initialBackupCount = [self backupCount];
    
    // always off; see message from Karl Berry on 27 Sept 2010 (MacTeX mailing list)
    [_pruneCheckbox setState:NSOffState];
    
    [self updateUI];

}

- (IBAction)enableAction:(id)sender;
{
    switch ([sender state]) {
        case NSOnState:
            [self setBackupCount:1];
            break;
        case NSOffState:
            [self setBackupCount:0];
            break;
        default:
            break;
    }
    [self updateUI];
}

- (IBAction)changeCount:(id)sender;
{
    [self setBackupCount:[sender integerValue]];
    [self updateUI];
}

- (IBAction)cancel:(id)sender;
{
    [NSApp endSheet:[self window] returnCode:TLMAutobackupCancelled];
}

- (IBAction)accept:(id)sender;
{
    // try to commit editing before ending the sheet
    if ([[self window] makeFirstResponder:nil]) {
    
        TLMAutobackupReturnCode ret = TLMAutobackupUnchanged;
        
        // change is a change in count or requirement to prune
        if ([self backupCount] != [self initialBackupCount] || [_pruneCheckbox state] == NSOnState) {
            ret = TLMAutobackupChanged;
            
            if ([self backupCount] > [self initialBackupCount])
                ret |= TLMAutobackupIncreased;
            else if ([self backupCount] < [self initialBackupCount])
                ret |= TLMAutobackupDecreased;
            
            if ([self backupCount] == 0)
                ret |= TLMAutobackupDisabled;
            
            if ([_pruneCheckbox state] == NSOnState)
                ret |= TLMAutobackupPrune;
        }  
        [NSApp endSheet:[self window] returnCode:ret];
    }
    else {
        NSBeep();
    }
}

@end

@implementation TLMBackupCountFormatter

- (NSString *)stringForObjectValue:(id)obj;
{
    if ([obj isEqual:[NSNumber numberWithInteger:-1]])
        return [NSString stringWithFormat:@"%C", TLM_INFINITY]; // \infty
    else if ([obj respondsToSelector:@selector(stringValue)])
        return [obj stringValue];
    else
        return [obj description];    
}

- (NSString *)editingStringForObjectValue:(id)obj;
{        
    if ([obj isEqual:[NSNumber numberWithInteger:-1]])
        return [NSString stringWithFormat:@"%C", TLM_INFINITY]; // \infty
    else if ([obj respondsToSelector:@selector(stringValue)])
        return [obj stringValue];
    else
        return [obj description];
}

- (BOOL)getObjectValue:(out id *)obj forString:(NSString *)string errorDescription:(out NSString **)error;
{
    if ([string isEqualToString:@"-1"] || [string isEqualToString:[NSString stringWithFormat:@"%C", TLM_INFINITY]]) {
        *obj = [NSNumber numberWithInteger:-1];
        return YES;
    }
    return [super getObjectValue:obj forString:string errorDescription:error];
}

@end

