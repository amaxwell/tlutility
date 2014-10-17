//
//  TLMPapersizeController.m
//  TeX Live Utility
//
//  Created by Adam Maxwell on 12/19/08.
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

#import "TLMPapersizeController.h"
#import "TLMLogServer.h"
#import "TLMTask.h"
#import "TLMEnvironment.h"

@implementation TLMPapersizeController

@synthesize _sizeMatrix;
@synthesize paperSize = _paperSize;

- (id)init
{
    return [self initWithWindowNibName:[self windowNibName]];
}

- (NSString *)windowNibName { return @"PapersizeSheet"; }

- (void)awakeFromNib
{
    /*
     froude:tmp amaxwell$ tlmgr pdftex paper --list
     letter
     a4
     froude:tmp amaxwell$ 
     */
    NSString *cmd = [[TLMEnvironment currentEnvironment] tlmgrAbsolutePath];
    
    // owner's responsiblity to validate this before showing the sheet
    NSParameterAssert([[NSFileManager defaultManager] isExecutableFileAtPath:cmd]);

    TLMTask *task = [[TLMTask new] autorelease];
    [task setLaunchPath:cmd];
    [task setEnvironment:[[TLMEnvironment currentEnvironment] taskEnvironment]];
    [task setArguments:[NSArray arrayWithObjects:@"pdftex", @"paper", @"--list", nil]];

    // output won't fill the pipe's buffer
    [task launch];
    [task waitUntilExit];

    NSString *currentSize = nil;
    NSInteger ret = [task terminationStatus];
    if (0 != ret) {
        TLMLog(__func__, @"Unable to determine current paper size for pdftex");
    }
    else if ([task outputString]) {
        NSArray *sizes = [[task outputString] componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        if ([sizes count])
            currentSize = [sizes objectAtIndex:0];
    }
    
    // in TL 2009, tlmgr returns 0 when auth is required, but prints an error message
    if ([task errorString])
        TLMLog(__func__, @"stderr from `%@ %@`: %@", [task launchPath], [[task arguments] componentsJoinedByString:@" "], [task errorString]);
    
    [self setPaperSize:currentSize];
    
    if ([currentSize isEqualToString:@"letter"]) {
        [_sizeMatrix selectCellWithTag:0];
    }
    else if ([currentSize isEqualToString:@"a4"]) {
        [_sizeMatrix selectCellWithTag:1];
    }
    else {        
        // set to allow this in the nib
        [_sizeMatrix deselectAllCells];
        TLMLog(__func__, @"Unknown paper size \"%@\"", currentSize);
    }
}

- (void)dealloc
{
    [_paperSize release];
    [_sizeMatrix release];
    [super dealloc];
}

- (IBAction)changeSize:(id)sender;
{
    NSParameterAssert([sender selectedCell]);
    switch ([[sender selectedCell] tag]) {
        case 0:
            [self setPaperSize:@"letter"];
            break;
        case 1:
            [self setPaperSize:@"a4"];
            break;
        default:
            NSAssert1(0, @"Invalid tag %ld", (long)[sender tag]);
            break;
    }
}

- (IBAction)cancel:(id)sender;
{
    [NSApp endSheet:[self window] returnCode:TLMPapersizeCancelled];
}

- (IBAction)accept:(id)sender;
{
    [NSApp endSheet:[self window] returnCode:TLMPapersizeChanged];
}

@end
