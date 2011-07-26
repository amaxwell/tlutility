//
//  TLMMirrorTextField.m
//  TeX Live Manager
//
//  Created by Adam R. Maxwell on 07/24/11.
/*
 This software is Copyright (c) 2011
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

#import "TLMMirrorTextField.h"
#import "TLMMirrorCell.h"

@implementation TLMMirrorFieldEditor

- (void)viewWillMoveToWindow:(NSWindow *)newWindow
{
    [super viewWillMoveToWindow:newWindow];
    if (newWindow) {
        [self registerForDraggedTypes:[NSArray arrayWithObjects:NSURLPboardType, (id)kUTTypeURL, NSStringPboardType, nil]];
    }
    else {
        [self unregisterDraggedTypes];
    }
}

- (BOOL)isFieldEditor { return YES; }

- (BOOL)dragChangedText { return _dragChangedText; }

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender { 
    _dragChangedText = NO;
    return [sender draggingSource] == [self delegate] ? NSDragOperationNone : NSDragOperationCopy; 
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender { 
    [[self window] makeFirstResponder:nil];
    _dragChangedText = NO;
}

- (BOOL)setStringFromDragOperation:(NSString *)aString
{
    if ([[self string] isEqualToString:aString])
        return NO;

    [self setString:aString];
    _dragChangedText = YES;
    return YES;
}

- (BOOL)performDragOperation:(id < NSDraggingInfo >)sender
{
    NSPasteboard *pboard = [sender draggingPasteboard];
    NSString *type = [pboard availableTypeFromArray:[NSArray arrayWithObjects:NSURLPboardType, (id)kUTTypeURL, NSStringPboardType, nil]];
    BOOL rv = NO;
    if ([type isEqualToString:NSURLPboardType]) {
        rv = [self setStringFromDragOperation:[[NSURL URLFromPasteboard:pboard] absoluteString]];
    }
    else if ([type isEqualToString:(id)kUTTypeURL]) {
        rv = [self setStringFromDragOperation:[pboard stringForType:type]];
    }
    else if ([type isEqualToString:NSStringPboardType]) {
        rv = [self setStringFromDragOperation:[pboard stringForType:type]];
    }
    return rv;
}

- (BOOL)prepareForDragOperation:(id < NSDraggingInfo >)sender { return YES; }

@end



@implementation TLMMirrorTextField

/*
 I tried NSTrackingArea, but it only works on the fringes of the icon, or if you enter the
 icon area from inside the cell.  Entering from the bottom, left, or top of the icon did
 not work.  Since this works and is a single line of code instead of multiple overrides
 and an ivar to get something partially functional...I say NSTrackingArea officially sucks.
 */
- (void)resetCursorRects
{
    [self addCursorRect:[[self cell] iconRectForBounds:[self bounds]] cursor:[NSCursor arrowCursor]];
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow
{
    [super viewWillMoveToWindow:newWindow];
    if (newWindow) {
        [self registerForDraggedTypes:[NSArray arrayWithObjects:NSURLPboardType, (id)kUTTypeURL, NSStringPboardType, nil]];
    }
    else {
        [self unregisterDraggedTypes];
    }
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender { 
    _dragChangedText = NO;
    return [sender draggingSource] == self ? NSDragOperationNone : NSDragOperationCopy; 
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender { 
    if ([[self window] makeFirstResponder:nil])
        [self sendAction:[self action] to:[self target]];
    _dragChangedText = NO;
}

- (BOOL)setStringFromDragOperation:(NSString *)aString
{
    if ([[self stringValue] isEqualToString:aString])
        return NO;
    
    [self setStringValue:aString];
    _dragChangedText = YES;
    return YES;
}

- (BOOL)performDragOperation:(id < NSDraggingInfo >)sender
{
    NSPasteboard *pboard = [sender draggingPasteboard];
    NSString *type = [pboard availableTypeFromArray:[NSArray arrayWithObjects:NSURLPboardType, (id)kUTTypeURL, NSStringPboardType, nil]];
    BOOL rv = NO;
    if ([type isEqualToString:NSURLPboardType]) {
        rv = [self setStringFromDragOperation:[[NSURL URLFromPasteboard:pboard] absoluteString]];
    }
    else if ([type isEqualToString:(id)kUTTypeURL]) {
        rv = [self setStringFromDragOperation:[pboard stringForType:type]];
    }
    else if ([type isEqualToString:NSStringPboardType]) {
        rv = [self setStringFromDragOperation:[pboard stringForType:type]];
    }
    return rv;
}

- (BOOL)prepareForDragOperation:(id < NSDraggingInfo >)sender { return YES; }

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)flag { return NSDragOperationCopy; }

- (void)textDidChange:(NSNotification *)notification
{
    [super textDidChange:notification];
    _dragChangedText = YES;
}

/*
 The _dragChangedText business is to avoid sending spurious action messages
 when text hasn't actually changed due to drag-and-drop or direct editing.
 By default, it sends it every time you click on the icon, which is a bit
 much if the action does anything nontrivial.
 */
- (void)textDidEndEditing:(NSNotification *)notification
{
    TLMMirrorFieldEditor *editor = [notification object];
    if ([editor dragChangedText] || _dragChangedText)
        [super textDidEndEditing:notification];
}

@end
