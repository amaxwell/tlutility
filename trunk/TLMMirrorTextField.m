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

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender{
	return NSDragOperationCopy;
}

- (BOOL)performDragOperation:(id < NSDraggingInfo >)sender
{
    fprintf(stderr, "%s\n", __func__);
    NSPasteboard *pboard = [sender draggingPasteboard];
    NSString *type = [pboard availableTypeFromArray:[NSArray arrayWithObjects:NSURLPboardType, (id)kUTTypeURL, NSStringPboardType, nil]];
    BOOL rv = NO;
    if ([type isEqualToString:NSURLPboardType]) {
        [self setString:[[NSURL URLFromPasteboard:pboard] absoluteString]];
        rv = YES;
    }
    else if ([type isEqualToString:(id)kUTTypeURL]) {
        [self setString:[pboard stringForType:type]];
        rv = YES;
    }
    else if ([type isEqualToString:NSStringPboardType]) {
        [self setString:[pboard stringForType:type]];
        rv = YES;
    }
    return rv;
}

- (BOOL)prepareForDragOperation:(id < NSDraggingInfo >)sender
{
    return YES;
}

@end



@implementation TLMMirrorTextField

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

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender{
	return NSDragOperationCopy;
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender;
{
    [self sendAction:[self action] to:[self target]];
}

- (BOOL)performDragOperation:(id < NSDraggingInfo >)sender
{
    fprintf(stderr, "%s\n", __func__);
    NSPasteboard *pboard = [sender draggingPasteboard];
    NSString *type = [pboard availableTypeFromArray:[NSArray arrayWithObjects:NSURLPboardType, (id)kUTTypeURL, NSStringPboardType, nil]];
    BOOL rv = NO;
    if ([type isEqualToString:NSURLPboardType]) {
        [self setStringValue:[[NSURL URLFromPasteboard:pboard] absoluteString]];
        rv = YES;
    }
    else if ([type isEqualToString:(id)kUTTypeURL]) {
        [self setStringValue:[pboard stringForType:type]];
        rv = YES;
    }
    else if ([type isEqualToString:NSStringPboardType]) {
        [self setStringValue:[pboard stringForType:type]];
        rv = YES;
    }
    return rv;
}

- (BOOL)prepareForDragOperation:(id < NSDraggingInfo >)sender
{
    return YES;
}

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)flag { return NSDragOperationCopy; }

- (void)textDidChange:(NSNotification *)notification
{
    [super textDidChange:notification];
    _changedText = YES;
}

- (void)textDidEndEditing:(NSNotification *)aNote
{
    if (_changedText) {
        [super textDidEndEditing:aNote];
        _changedText = NO;
    }
}

@end
