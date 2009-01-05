//
//  TLMInfoController.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/7/08.
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

#import "TLMInfoController.h"
#import "TLMInfoOperation.h"
#import "TLMPackage.h"
#import "TLMOutputParser.h"
#import "TLMLogServer.h"

@implementation TLMInfoController

@synthesize _textView;
@synthesize _spinner;
@synthesize _tabView;

+ (id)sharedInstance
{
    static id sharedInstance = nil;
    if (nil == sharedInstance)
        sharedInstance = [[self alloc] init];
    return sharedInstance;
}

- (id)init
{
    self = [super initWithWindowNibName:[self windowNibName]];
    if (self) {
        _infoQueue = [NSOperationQueue new];
        [_infoQueue setMaxConcurrentOperationCount:1];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_infoQueue cancelAllOperations];
    [_infoQueue release];
    [_textView release];
    [_spinner release];
    [_tabView release];
    [super dealloc];
}

- (void)_recenterSpinner
{
    NSRect windowFrame = [[self window] frame];
    windowFrame.origin = [[self window] convertScreenToBase:windowFrame.origin];
    NSRect bounds = [[_spinner superview] convertRect:windowFrame fromView:nil];
    NSSize spinnerSize = [_spinner bounds].size;
    NSPoint origin = NSMakePoint(NSMidX(bounds), NSMidY(bounds));
    origin.x -= (spinnerSize.width / 2);
    origin.y -= (spinnerSize.height / 2);
    NSRect spinnerFrame;
    spinnerFrame.size = spinnerSize;
    spinnerFrame.origin = origin;
    [_spinner setFrame:spinnerFrame];
    [[_spinner superview] setNeedsDisplay:YES];
}    

- (void)handleContentViewBoundsChanged:(NSNotification *)aNote
{
    [self _recenterSpinner];
}

- (void)awakeFromNib
{
    [(NSPanel *)[self window] setBecomesKeyOnlyIfNeeded:YES];
    
    // I was not able to get the resizing struts to keep the spinner centered, so gave up on IB and resorted to code
    [[[self window] contentView] setPostsBoundsChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleContentViewBoundsChanged:) 
                                                 name:NSViewBoundsDidChangeNotification 
                                               object:[[self window] contentView]];
    
    [_spinner setUsesThreadedAnimation:YES];
}

- (NSString *)windowNibName { return @"InfoPanel"; }

// why is setting this in IB ignored for panels?
- (NSString *)windowFrameAutosaveName { return @"Info Panel"; }

- (void)_handleInfoOperationFinishedNotification:(NSNotification *)aNote
{
    TLMInfoOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    
    // do nothing for cancelled ops, since they're only cancelled if we're going to be showing info for another package
    if ([op isCancelled] == NO) {
        NSString *result = [op infoString];
        if (result) {
            NSArray *docURLs = [op documentationURLs];
            // let texdoc handle the sort order (if any)
            if ([docURLs count]) [[self window] setRepresentedURL:[docURLs objectAtIndex:0]];
            [[self window] setTitle:[op packageName]];
            [_textView setSelectedRange:NSMakeRange(0, 0)];
            [[_textView textStorage] setAttributedString:[TLMOutputParser attributedStringWithInfoString:result docURLs:docURLs]];
        }
        else {
            [_textView setString:[NSString stringWithFormat:NSLocalizedString(@"Unable to find info for %@", @"error message for info panel"), [op packageName]]];
        }
        // only change tabs if we have something to show
        [_tabView selectFirstTabViewItem:nil];
        
        // let the spinner keep going if the op was cancelled, since this notification may be delivered after queueing another one
        [_spinner stopAnimation:nil];
    }
}

- (void)showInfoForPackage:(id <TLMInfo>)package
{
    // always clear the queue; this will trigger notifications for any cancelled operations
    [_infoQueue cancelAllOperations]; 
    
    if (nil != package) {
        
        TLMInfoOperation *op = [[TLMInfoOperation alloc] initWithPackageName:[package name]];
        if (op) {
            
            // clear previous title and file proxy icon
            [[self window] setTitle:[NSString stringWithFormat:NSLocalizedString(@"Searching%C", @"info panel title"), 0x2026]];
            [[self window] setRepresentedURL:nil];
            
            [_tabView selectLastTabViewItem:nil];
            [self _recenterSpinner];
            [_spinner startAnimation:nil];
            
            [[NSNotificationCenter defaultCenter] addObserver:self 
                                                     selector:@selector(_handleInfoOperationFinishedNotification:) 
                                                         name:TLMOperationFinishedNotification 
                                                       object:op];
            [_infoQueue addOperation:op];
            [op release];
            
            if ([[self window] isVisible] == NO)
                [self showWindow:self];
        }
    }
    else {
        [[self window] setTitle:NSLocalizedString(@"Nothing Selected", @"info panel title")];
        [[self window] setRepresentedURL:nil];
        [_textView setSelectedRange:NSMakeRange(0, 0)];
        [_textView setString:@""];
        [_spinner stopAnimation:nil];
        [_tabView selectFirstTabViewItem:nil];
    }        
}

- (BOOL)textView:(NSTextView *)aTextView clickedOnLink:(id)link atIndex:(NSUInteger)charIndex
{
    if ([link isKindOfClass:[NSURL class]])
        return [[NSWorkspace sharedWorkspace] openURL:link];
    else if ([link isKindOfClass:[NSString class]] && (link = [NSURL URLWithString:link]) != nil)
        return [[NSWorkspace sharedWorkspace] openURL:link];
    return NO;
}


@end
