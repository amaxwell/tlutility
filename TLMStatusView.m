//
//  TLMStatusView.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/21/08.
/*
 This software is Copyright (c) 2008
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

#import "TLMStatusView.h"


@implementation TLMStatusView

@synthesize attributedStatusString = _statusString;

- (void)dealloc
{
    [_statusString release];
    [super dealloc];
}

static void CenterRectInRect(NSRect *toCenter, NSRect enclosingRect)
{
    CGFloat halfWidth = NSWidth(*toCenter) / 2.0;
    CGFloat halfHeight = NSHeight(*toCenter) / 2.0;
    
    NSPoint centerPoint = NSMakePoint(NSMidX(enclosingRect), NSMidY(enclosingRect));
    centerPoint.x -= halfWidth;
    centerPoint.y -= halfHeight;
    toCenter->origin = centerPoint;
}

#define DRAW_OPTS (NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine)

- (void)_resetStringRect
{
    _stringRect = [_statusString boundingRectWithSize:NSMakeSize(NSWidth([self bounds]), 0) options:DRAW_OPTS];
    CenterRectInRect(&_stringRect, [self bounds]);
}    

- (void)resizeWithOldSuperviewSize:(NSSize)oldBoundsSize
{
    [super resizeWithOldSuperviewSize:oldBoundsSize];
    [self _resetStringRect];
}

- (void)viewDidMoveToSuperview
{
    [super viewDidMoveToSuperview];
    [self _resetStringRect];
}

- (void)setAttributedStatusString:(NSAttributedString *)attrString
{
    [_statusString autorelease];
    _statusString = [attrString copy];
    [self _resetStringRect];
    [self setNeedsDisplay:YES];
}

- (NSString *)statusString { return [_statusString string]; }

- (void)setStatusString:(NSString *)string
{
    NSMutableAttributedString *status = [[NSMutableAttributedString alloc] initWithString:string];
    NSRange rng = NSMakeRange(0, [status length]);
    [status addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:20.0] range:rng];
    [status addAttribute:NSForegroundColorAttributeName value:[NSColor whiteColor] range:rng];
    [self setAttributedStatusString:status];
    [status release];
}

- (BOOL)isOpaque { return NO; }

- (void)drawRect:(NSRect)dirtyRect 
{
    dirtyRect = [self bounds];
    
    [NSGraphicsContext saveGraphicsState];
    [[NSColor clearColor] setFill];
    NSRectFillUsingOperation(dirtyRect, NSCompositeSourceOver);
    
    [[NSColor lightGrayColor] setFill];
    CGFloat padding = NSHeight(_stringRect) / 3.0;
    NSRect fillRect = [self centerScanRect:NSInsetRect(_stringRect, -padding, -padding)];
    NSBezierPath *fillPath = [NSBezierPath bezierPathWithRoundedRect:fillRect xRadius:10.0 yRadius:10.0];
    [fillPath fill];
    
    [[NSColor grayColor] setStroke];
    [fillPath stroke];
    
    [NSGraphicsContext restoreGraphicsState];

    [_statusString drawWithRect:_stringRect options:DRAW_OPTS];
}

@end
