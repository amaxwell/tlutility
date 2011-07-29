//
//  TLMSplitView.m
//  TeX Live Utility
//
//  Created by Adam Maxwell on 12/7/08.
/*
 This software is Copyright (c) 2008-2011
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

#import "TLMSplitView.h"

@implementation TLMSplitView

// arm: mouseDown: swallows mouseDragged: needlessly
- (void)mouseDown:(NSEvent *)theEvent {
    BOOL inDivider = NO;
    NSPoint mouseLoc = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    NSArray *subviews = [self subviews];
    int i, count = [subviews count];
    id view;
    NSRect divRect;
    
    for (i = 0; i < count - 1; i++) {
        view = [subviews objectAtIndex:i];
        divRect = [view frame];
        if ([self isVertical]) {
            divRect.origin.x = NSMaxX(divRect);
            divRect.size.width = [self dividerThickness];
            if (divRect.size.width < 3.0) {
                divRect.origin.x -= 1.5;
                divRect.size.width = 3.0;
            }
        } else {
            divRect.origin.y = NSMaxY(divRect);
            divRect.size.height = [self dividerThickness];
            if (divRect.size.height < 3.0) {
                divRect.origin.y -= 1.5;
                divRect.size.height = 3.0;
            }
        }
        
        if (NSMouseInRect(mouseLoc, divRect, [self isFlipped])) {
            inDivider = YES;
            break;
        }
    }
    
    if (inDivider) {
        if ([theEvent clickCount] > 1 && [[self delegate] respondsToSelector:@selector(splitView:doubleClickedDividerAt:)])
            [(id <TLMSplitViewDelegate>)[self delegate] splitView:self doubleClickedDividerAt:i];
        else
            [super mouseDown:theEvent];
    } else {
        [[self nextResponder] mouseDown:theEvent];
    }
}

@end

@implementation TLMThinSplitView

- (CGFloat)dividerThickness { return 1; }

- (void)drawDividerInRect:(NSRect)aRect
{
    [NSGraphicsContext saveGraphicsState];
    [[NSColor darkGrayColor] set];
    
    NSBezierPath *path = [NSBezierPath bezierPath];
    if ([self isVertical]) {
        const CGFloat x = floor(NSMidX(aRect)) + 0.5;
        [path moveToPoint:NSMakePoint(x, NSMinY(aRect))];
        [path lineToPoint:NSMakePoint(x, NSMaxY(aRect))];
    }
    else {
        const CGFloat y = floor(NSMidY(aRect)) + 0.5;
        [path moveToPoint:NSMakePoint(NSMinX(aRect), y)];
        [path moveToPoint:NSMakePoint(NSMaxX(aRect), y)];
    }
    [path setLineWidth:0.0];
    [path stroke];
    [NSGraphicsContext restoreGraphicsState];
}


@end

