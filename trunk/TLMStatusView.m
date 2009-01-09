//
//  TLMStatusView.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/21/08.
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

#import "TLMStatusView.h"

@implementation TLMStatusView

@synthesize attributedStatusString = _statusString;

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // start out as transparent
        _contextAlphaValue = 0.0;
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super initWithCoder:decoder];
    if (self) {
        // start out as transparent
        _contextAlphaValue = 0.0;
    }
    return self;
}

- (void)dealloc
{
    [_statusString release];
    [_background release];
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
    [self setNeedsDisplay:YES];
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

- (void)animationFired:(NSTimer *)timer
{    
    NSAnimation *animation = [timer userInfo];
    CGFloat value = [animation currentValue];
    if (value > 0.99) {
        [animation stopAnimation];
        [timer invalidate];
        _isFading = NO;
        
        // only remove when fading out
        if (_fadeOut)
            [self removeFromSuperview];     
    }
    else {
        _contextAlphaValue = _fadeOut ? (1 - value) : value;
        [self displayRectIgnoringOpacity:[self bounds]];
    }
}

- (void)startAnimation
{    
    _isFading = YES;
    
    // animate ~30 fps for 0.3 seconds, using NSAnimation to get the alpha curve
    NSAnimation *animation = [[NSAnimation alloc] initWithDuration:0.3 animationCurve:NSAnimationEaseInOut]; 
    // runloop mode is irrelevant for non-blocking threaded
    [animation setAnimationBlockingMode:NSAnimationNonblockingThreaded];
    // explicitly alloc/init so it can be added to all the common modes instead of the default mode
    NSTimer *timer = [[NSTimer alloc] initWithFireDate:[NSDate date]
                                              interval:0.03
                                                target:self 
                                              selector:@selector(animationFired:)
                                              userInfo:animation
                                               repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    [timer release];
    [animation startAnimation];
    [animation release];  
}

- (void)_setBackground:(NSImage *)anImage
{
    if (anImage != _background) {
        [_background release];
        _background = [anImage retain];
    }
}

- (void)_prepareBackgroundImage
{
    // since we can't use layers to handle compositing, use a snapshot of the current view content
    NSBitmapImageRep *imageRep = [[self superview] bitmapImageRepForCachingDisplayInRect:[self frame]];
    
    // set a flag so drawRect: does nothing when this is called
    _preparingBackground = YES;
    [[self superview] cacheDisplayInRect:[self frame] toBitmapImageRep:imageRep];
    _preparingBackground = NO;
    
    NSImage *image = [[NSImage alloc] initWithSize:[self frame].size];
    [image addRepresentation:imageRep];
    [self _setBackground:image];        
}

- (void)fadeOut;
{
    _fadeOut = YES;
    [self _prepareBackgroundImage];
    [self startAnimation];
}

- (void)fadeIn;
{
    _fadeOut = NO;
    [self _prepareBackgroundImage];
    [self startAnimation];
}

- (void)drawRect:(NSRect)dirtyRect 
{
    if (NO == _preparingBackground) {
                
        // draw the superview and its descendants, and composite our content of top of it
        if (_isFading) {
            [_background drawInRect:[self bounds] fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
            CGContextSetAlpha([[NSGraphicsContext currentContext] graphicsPort], _contextAlphaValue);
        }
        
        // fill and stroke the path
        [NSGraphicsContext saveGraphicsState];    
        
        CGFloat padding = NSHeight(_stringRect) / 3.0;
        NSRect fillRect = [self centerScanRect:NSInsetRect(_stringRect, -padding, -padding)];
        NSBezierPath *fillPath = [NSBezierPath bezierPathWithRoundedRect:fillRect xRadius:10.0 yRadius:10.0];        
        
        [[NSColor lightGrayColor] setFill];
        [fillPath fill];
        
        [[NSColor grayColor] setStroke];
        [fillPath setLineWidth:1.0];
        [fillPath stroke];
        
        [NSGraphicsContext restoreGraphicsState];
        
        // draw text on top of the path
        [_statusString drawWithRect:_stringRect options:DRAW_OPTS];
    }
}

@end
