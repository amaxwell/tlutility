//
//  TLMBackupCell.m
//  TeX Live Manager
//
//  Created by Adam R. Maxwell on 10/15/10.
/*
 This software is Copyright (c) 2010-2011
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

#import "TLMBackupCell.h"

@implementation TLMBackupCell

+ (BOOL)prefersTrackingUntilMouseUp { return YES; }

- (id)initTextCell:(NSString *)aString
{
    self = [super initTextCell:aString];
    if (self) {
        _buttonCell = [[NSButtonCell alloc] initTextCell:NSLocalizedString(@"Restore", @"small button title")];
        [_buttonCell setControlSize:NSMiniControlSize];
        [_buttonCell setButtonType:NSMomentaryLightButton];
        [_buttonCell setBordered:YES];
        [_buttonCell setBezelStyle:NSRoundRectBezelStyle];
        [_buttonCell setFont:[NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:[_buttonCell controlSize]]]];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)aZone
{
    TLMBackupCell *cell = [super copyWithZone:aZone];
    cell->_buttonCell = [_buttonCell copyWithZone:aZone];
    return cell;
}

- (void)dealloc
{
    [_buttonCell release];
    [super dealloc];
}

- (void)setControlView:(NSView*)view;
{
    [super setControlView:view];
    [_buttonCell setControlView:view];
}

- (void)setAction:(SEL)aSelector
{
    [_buttonCell setAction:aSelector];
}

- (void)setTarget:(id)anObject
{
    [_buttonCell setTarget:anObject];
}

- (void)setBackgroundStyle:(NSBackgroundStyle)style;
{
    [super setBackgroundStyle:style];
    [_buttonCell setBackgroundStyle:style];
}

#define BUTTON_MARGIN   10.0
#define BUTTON_FRACTION  0.3

- (NSRect)buttonRectForBounds:(NSRect)theRect 
{
	NSRect buttonRect = NSZeroRect;    
    buttonRect.size = [_buttonCell cellSize];
    buttonRect.size.height = NSHeight(theRect) * BUTTON_FRACTION;
    buttonRect.origin.x = NSMinX(theRect);
    buttonRect.origin.y = NSMidY(theRect) - 0.5 * buttonRect.size.height;
    return buttonRect;
}

- (BOOL)trackMouse:(NSEvent *)theEvent inRect:(NSRect)cellFrame ofView:(NSView *)controlView untilMouseUp:(BOOL)untilMouseUp {
    NSRect buttonRect = [self buttonRectForBounds:cellFrame];
    NSPoint mouseLoc = [controlView convertPoint:[theEvent locationInWindow] fromView:nil];
    BOOL insideButton = NSMouseInRect(mouseLoc, buttonRect, [controlView isFlipped]);
    if (insideButton) {
		BOOL keepOn = YES;
		while (keepOn) {
            if (insideButton) {
                // NSButtonCell does not highlight itself, it tracks until a click or the mouse exits
                [_buttonCell highlight:YES withFrame:buttonRect inView:controlView];
                if ([_buttonCell trackMouse:theEvent inRect:buttonRect ofView:controlView untilMouseUp:NO])
                    keepOn = NO;
                [_buttonCell highlight:NO withFrame:buttonRect inView:controlView];
            }
            if (keepOn) {
                // we're dragging outside the button, wait for a mouseup or move back inside
                theEvent = [[controlView window] nextEventMatchingMask: NSLeftMouseUpMask | NSLeftMouseDraggedMask];
                mouseLoc = [controlView convertPoint:[theEvent locationInWindow] fromView:nil];
                insideButton = NSMouseInRect(mouseLoc, buttonRect, [controlView isFlipped]);
                keepOn = ([theEvent type] == NSLeftMouseDragged);
            }
		}
        return YES;
    } else 
        return [super trackMouse:theEvent inRect:cellFrame ofView:controlView untilMouseUp:untilMouseUp];
}

- (NSUInteger)hitTestForEvent:(NSEvent *)event inRect:(NSRect)cellFrame ofView:(NSView *)controlView
{
    NSUInteger hit = [super hitTestForEvent:event inRect:cellFrame ofView:controlView];
    // super returns 0 for button clicks, so -[NSTableView mouseDown:] doesn't track the cell
    NSRect buttonRect = [self buttonRectForBounds:cellFrame];
    NSPoint mouseLoc = [controlView convertPoint:[event locationInWindow] fromView:nil];
    if (NSMouseInRect(mouseLoc, buttonRect, [controlView isFlipped]))
        hit = NSCellHitContentArea | NSCellHitTrackableArea;
    return hit;
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView;
{
    NSRect interiorFrame = cellFrame;
    NSRect buttonFrame = [self buttonRectForBounds:cellFrame];
    interiorFrame.origin.x = NSMaxX(buttonFrame) + BUTTON_MARGIN;
    [super drawInteriorWithFrame:interiorFrame inView:controlView];
    [_buttonCell drawWithFrame:buttonFrame inView:controlView];
}

@end
