//
//  BDSKTextViewCompletionController.h
//  Bibdesk
//
//  Created by Adam Maxwell on 01/08/06.
/*
 This software is Copyright (c) 2006-2010
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

// we implement some of the NSResponder methods, but not all; this class inherits from NSResponder in order to avoid declaring them

@interface BDSKTextViewCompletionController : NSResponder <NSTableViewDelegate, NSTableViewDataSource>
{
	NSWindow *completionWindow;
	NSArray *completions;
	NSString *originalString;
	NSInteger movement;
	NSTableView *tableView;
	NSTextView *textView;
	NSWindow *textViewWindow;
    BOOL shouldInsert;
}

+ (id)sharedController;

- (NSWindow *)completionWindow;
- (NSTextView *)currentTextView;
- (void)displayCompletions:(NSArray *)completions forPartialWordRange:(NSRange)partialWordRange originalString:(NSString *)origString atPoint:(NSPoint)point forTextView:(NSTextView *)textView;
- (void)displayCompletions:(NSArray *)completions indexOfSelectedItem:(NSInteger)indexOfSelectedItem forPartialWordRange:(NSRange)partialWordRange originalString:(NSString *)originalString atPoint:(NSPoint)point forTextView:(NSTextView *)textView;
- (void)endDisplay;
- (void)endDisplayAndComplete:(BOOL)complete;
- (void)endDisplayNoComplete;
- (void)tableAction:(id)sender;

@end

@interface NSTextView (BDSKExtensions)
- (NSPoint)locationForCompletionWindow;
@end

@protocol BDSKTextViewCompletionDelegate <NSTextViewDelegate>
@optional
- (NSPoint)locationForCompletionWindowInTextView:(NSTextView *)tv;
- (NSPoint)control:(NSControl *)control locationForCompletionWindowInTextView:(NSTextView *)tv;
@end
