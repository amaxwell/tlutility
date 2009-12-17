//
//  TLMStatusWindow.m
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

#import "TLMStatusWindow.h"

@interface _TLMStatusView : NSView 
{
@private
    NSAttributedString *_statusString;
    NSRect              _stringRect;
}

@property(readwrite, copy) NSString *statusString;
@property(readwrite, copy) NSAttributedString *attributedStatusString;

@end

#pragma mark -

@implementation _TLMStatusView

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

- (void)drawRect:(NSRect)dirtyRect 
{                        
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

@end

@interface TLMStatusWindow ()
@property (nonatomic, retain) NSView *frameView;
@property (nonatomic, assign) _TLMStatusView *statusView;
@end


@implementation TLMStatusWindow

@synthesize statusView = _statusView;
@synthesize frameView = _frameView;

+ (TLMStatusWindow *)windowWithStatusString:(NSString *)statusString frameFromView:(NSView *)aView;
{
    TLMStatusWindow *window = [[self allocWithZone:[self zone]]
                               initWithContentRect:NSMakeRect(0,0,10,10) 
                                         styleMask:NSBorderlessWindowMask 
                                           backing:NSBackingStoreBuffered 
                                             defer:YES];
    [window setReleasedWhenClosed:NO];
    [window setBackgroundColor:[NSColor clearColor]];
    [window setOpaque:NO];
    [window setHasShadow:NO];
    [window setPreferredBackingLocation:NSWindowBackingLocationVideoMemory];
    
    _TLMStatusView *statusView = [[_TLMStatusView allocWithZone:[self zone]] 
                                                  initWithFrame:[[window contentView] frame]];
    [statusView setStatusString:statusString];
    [statusView setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable|NSViewMaxXMargin|NSViewMinXMargin|NSViewMaxYMargin|NSViewMinYMargin];
    [[window contentView] addSubview:statusView];
    [window setStatusView:statusView];
    [statusView release];
    
    // observe for frame changes
    [window setFrameView:aView];
    
    // initially transparent
    [window setAlphaValue:0.0];
    
    return [window autorelease];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_frameView release];
    [super dealloc];
}

- (void)parentFrameChanged:(NSNotification *)aNote
{
    NSParameterAssert([self parentWindow]);
    [self setFrame:[[self parentWindow] frame] display:YES];
}

- (void)setParentWindow:(NSWindow *)parent
{
    if (parent && nil == [self frameView]) {
        [self setFrame:[parent frame] display:NO];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(parentFrameChanged:)
                                                     name:NSWindowDidResizeNotification
                                                   object:parent];
    }
    // call after setting frame and registering; try #2 to fix issue 33
    [super setParentWindow:parent];
}

- (void)handleViewFrameChange:(NSNotification *)aNote
{
    NSParameterAssert(_frameView);
    NSRect frame = [_frameView convertRectToBase:[_frameView frame]];
    frame.origin = [[_frameView window] convertBaseToScreen:frame.origin];
    [self setFrame:frame display:YES];
}

- (void)orderWindow:(NSWindowOrderingMode)place relativeTo:(NSInteger)otherWin;
{
    [super orderWindow:place relativeTo:otherWin];
    // attempt to fix race when adding child window: http://code.google.com/p/mactlmgr/issues/detail?id=33
    if (_frameView) [self handleViewFrameChange:nil];
}

- (void)setFrameView:(NSView *)aView
{
    NSAssert(nil == _frameView, @"it is an error to reset the frame view");
    if (aView) {
        [aView setPostsFrameChangedNotifications:YES];
        [aView setPostsBoundsChangedNotifications:YES];
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self 
               selector:@selector(handleViewFrameChange:) 
                   name:NSViewFrameDidChangeNotification 
                 object:aView];
        [nc addObserver:self 
               selector:@selector(handleViewFrameChange:) 
                   name:NSViewBoundsDidChangeNotification 
                 object:aView];
        _frameView = [aView retain];
        
        // set initial size
        [self handleViewFrameChange:nil];
    }
}

- (void)fadeIn;
{
    [self orderFront:nil];
    [[self animator] setAlphaValue:1.0];
}

- (void)fadeOutAndRemove:(BOOL)remove;
{
    if (remove) {
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        [[self parentWindow] removeChildWindow:self];
        // this will orderOut parent as well if attached
        [self performSelector:@selector(orderOut:) withObject:nil afterDelay:1.0];
    }
    [[self animator] setAlphaValue:0.0];
}

@end

