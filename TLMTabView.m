//
//  TLMTabView.m
//  TabViewTest
//
//  Created by Adam Maxwell on 12/23/08.
/*
 This software is Copyright (c) 2008-2016
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

#import "TLMTabView.h"
#import <QuartzCore/QuartzCore.h>

@interface _TLMImageView : NSView
{
    NSImage *_image;
    CGFloat  _imageAlphaValue;
}
@property (readwrite) CGFloat imageAlphaValue;
@property (readwrite, retain) NSImage *image;
@end

@implementation _TLMImageView

@synthesize imageAlphaValue = _imageAlphaValue;
@synthesize image = _image;

- (void)dealloc
{
    [_image release];
    [super dealloc];
}

- (BOOL)isOpaque { return NO; }

- (void)drawRect:(NSRect)aRect
{
    [[self image] drawInRect:[self bounds] fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:[self imageAlphaValue]];
}

@end

@implementation TLMTabView

@synthesize delegate = _delegate;

- (void)_commonInit
{
    _tabControl = [[NSSegmentedControl allocWithZone:[self zone]] initWithFrame:NSZeroRect];
    
#define TAB_CONTROL_MARGIN -3
    [_tabControl setSegmentStyle:NSSegmentStyleTexturedRounded];
    
    [self addSubview:_tabControl];
    [_tabControl setSegmentCount:0];
    [_tabControl setTarget:self];
    [_tabControl setAction:@selector(changeView:)];
    [_tabControl setAutoresizingMask:NSViewMinYMargin | NSViewMinXMargin | NSViewMaxXMargin];
    _views = [NSMutableArray new];    
    
    NSMutableArray *transitionViews = [NSMutableArray array];
    for (int i = 0; i < 2; i++) {
        _TLMImageView *imageView = [[_TLMImageView allocWithZone:[self zone]] initWithFrame:[self frame]];
        [transitionViews addObject:imageView];
        [imageView release];
    }
    _transitionViews = [transitionViews copy];
    
    _selectedIndex = -1;
}

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self _commonInit];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super initWithCoder:decoder];
    if (self) {
        [self _commonInit];
    }
    return self;
}

- (void)dealloc
{
    [_transitionViews release];
    _delegate = nil;
    _currentView = nil;
    [_tabControl release];
    [_views release];
    [super dealloc];
}

- (void)setTabControl:(NSSegmentedControl *)tabControl
{
    // if explicitly set, only do the target/action setup
    if (_tabControl != tabControl) {
        [_tabControl removeFromSuperview];
        [_tabControl release];
        _tabControl = [tabControl retain];
        [_tabControl setSegmentCount:0];
        [_tabControl setTarget:self];
        [_tabControl setAction:@selector(changeView:)];
        _externalTabControl = YES;
    }
}

- (NSSegmentedControl *)tabControl { return _tabControl; }

// subview frame in receiver's coordinates
- (NSRect)contentRect
{    
    NSRect viewFrame = [self bounds];
    if (NO == _externalTabControl) {
        viewFrame.size.height -= (NSHeight([_tabControl frame]) - 3 * TAB_CONTROL_MARGIN);
    }
    else {
        viewFrame = NSInsetRect(viewFrame, 0, 1);
    }

    return viewFrame;
}

- (void)_adjustTabs
{
    NSRect tabFrame = [_tabControl frame];
    tabFrame.origin.x = 0.5 * (NSWidth([[_tabControl superview] bounds]) - NSWidth(tabFrame));
    if (NO == _externalTabControl)
        tabFrame.origin.y = NSMaxY([self bounds]) - NSHeight(tabFrame) + TAB_CONTROL_MARGIN;
    [_tabControl setFrame:[[_tabControl superview] centerScanRect:tabFrame]];          
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize;
{
    [super resizeSubviewsWithOldSize:oldSize];
    [self _adjustTabs];
    [_currentView setFrame:[self contentRect]];
}

- (void)addTabNamed:(NSString *)tabName withView:(NSView *)aView;
{
    NSParameterAssert(tabName);
    NSParameterAssert(aView);
    [_tabControl setSegmentCount:([_tabControl segmentCount] + 1)];
    [_tabControl setLabel:tabName forSegment:([_tabControl segmentCount] - 1)];
    [_tabControl sizeToFit];
    [self _adjustTabs];
    [_views addObject:aView];
            
    if (-1 == _selectedIndex)
        [self selectViewAtIndex:0];
}

- (NSView *)viewAtIndex:(NSUInteger)anIndex;
{
    return [_views objectAtIndex:anIndex];
}

- (void)animationFired:(NSTimer *)timer
{
    NSAnimation *animation = [timer userInfo];
    CGFloat value = [animation currentValue];
    if (value > 0.99) {
        [animation stopAnimation];
        [timer invalidate];
        [_transitionViews makeObjectsPerformSelector:@selector(removeFromSuperviewWithoutNeedingDisplay)];     
        NSParameterAssert([_currentView isDescendantOf:self]);
        [_currentView setHidden:NO];
        [self setNeedsDisplay:YES];
    }
    else {
        [[_transitionViews objectAtIndex:0] setImageAlphaValue:(1 - value)];
        [[_transitionViews objectAtIndex:1] setImageAlphaValue:value];    
        [self displayRectIgnoringOpacity:[[_transitionViews objectAtIndex:0] frame]];
    }
}

- (void)_transitionToView:(NSView *)nextView
{
    // will unhide when animation finishes
    [nextView setHidden:YES];
        
    // use the same frame; no autoresizing needed for these
    [[_transitionViews objectAtIndex:0] setFrame:[nextView frame]];
    [[_transitionViews objectAtIndex:1] setFrame:[nextView frame]];
    
    NSBitmapImageRep *imageRep;
    NSImage *image;
    
    // cache the currently displayed view to a bitmap and set it initially opaque
    NSRect bitmapBounds = [_currentView bounds];
    imageRep = [_currentView bitmapImageRepForCachingDisplayInRect:bitmapBounds];
    [_currentView cacheDisplayInRect:bitmapBounds toBitmapImageRep:imageRep];
    image = [[NSImage alloc] initWithSize:bitmapBounds.size];
    [image addRepresentation:imageRep];
    [[_transitionViews objectAtIndex:0] setImage:image];
    [[_transitionViews objectAtIndex:0] setImageAlphaValue:1.0];
    [image release];
    
    // only remove after caching to bitmap
    [_currentView removeFromSuperviewWithoutNeedingDisplay];
    
    // now cache the next view to a bitmap and set it initially transparent
    NSParameterAssert(NSEqualRects([_currentView bounds], [nextView bounds]));
    imageRep = [nextView bitmapImageRepForCachingDisplayInRect:bitmapBounds];
    [nextView cacheDisplayInRect:bitmapBounds toBitmapImageRep:imageRep];
    image = [[NSImage alloc] initWithSize:bitmapBounds.size];
    [image addRepresentation:imageRep];
    [[_transitionViews objectAtIndex:1] setImage:image];
    [[_transitionViews objectAtIndex:1] setImageAlphaValue:0.0];
    [image release];
    
    // add both image views as subviews
    [self addSubview:[_transitionViews objectAtIndex:0]];
    [self addSubview:[_transitionViews objectAtIndex:1]];  
    
    // in case they were hidden by the animator (not at present)
    [[_transitionViews objectAtIndex:0] setHidden:NO];
    [[_transitionViews objectAtIndex:1] setHidden:NO];
    
    // set now, since the timer callback needs it
    _currentView = nextView;
        
#define DURATION 0.3
    
    // animate ~30 fps for 0.3 seconds, using NSAnimation to get the alpha curve
    NSAnimation *animation = [[NSAnimation alloc] initWithDuration:DURATION animationCurve:NSAnimationEaseInOut]; 
    // runloop mode is irrelevant for non-blocking threaded
    [animation setAnimationBlockingMode:NSAnimationNonblockingThreaded];
    // explicitly alloc/init so it can be added to all the common modes instead of the default mode
    NSTimer *timer = [[NSTimer alloc] initWithFireDate:[NSDate date]
                                              interval:(DURATION / 10.0)
                                                target:self 
                                              selector:@selector(animationFired:)
                                              userInfo:animation
                                               repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    [timer release];
    [animation startAnimation];
    [animation release];    
}

- (void)selectViewAtIndex:(NSUInteger)anIndex;
{
    NSParameterAssert(anIndex < [_views count]);

    // !!! early return if this view is already selected, or else it gets faded out of existence...
    if ((NSInteger)anIndex == _selectedIndex)
        return;
    
    _selectedIndex = anIndex;
    [_tabControl setSelectedSegment:anIndex];
    
    NSView *nextView = [self viewAtIndex:anIndex];
    [nextView setFrame:[self contentRect]];
    
    NSParameterAssert([nextView isDescendantOf:self] == NO);
    [self addSubview:nextView];

    // if this is the initial display, we don't want to animate anything
    if ([_currentView isDescendantOf:self]) {
        [self _transitionToView:nextView];
    }
    else {
        _currentView = nextView;
    }
    
    if ([[self delegate] respondsToSelector:@selector(tabView:didSelectViewAtIndex:)])
        [[self delegate] tabView:self didSelectViewAtIndex:anIndex];
}

- (IBAction)changeView:(id)sender
{
    NSParameterAssert([_tabControl segmentCount]);
    if ([_tabControl selectedSegment] != _selectedIndex)
        [self selectViewAtIndex:[_tabControl selectedSegment]];
}

- (BOOL)isOpaque { return YES; }

- (void)drawRect:(NSRect)dirtyRect
{
    [NSGraphicsContext saveGraphicsState];
    NSRectClip(dirtyRect);
    
    [[[self window] backgroundColor] set];
    NSRectFillUsingOperation(dirtyRect, NSCompositeCopy);

    // flashes to window background on initial transition
    [[NSColor whiteColor] set];
    NSRectFillUsingOperation([self contentRect], NSCompositeCopy);
 
    NSRect bezelRect = [self bounds];
    bezelRect.size.height = NSMidY([_tabControl frame]);
    [[NSColor colorWithDeviceWhite:0.9 alpha:1.0] set];
    NSRectFillUsingOperation(bezelRect, NSCompositeCopy);
    
    [NSGraphicsContext restoreGraphicsState];
    
    [NSGraphicsContext saveGraphicsState];

    NSShadow *lineShadow = [[NSShadow new] autorelease];
    [lineShadow setShadowColor:[NSColor colorWithDeviceWhite:0.8 alpha:1.0]];
    [lineShadow setShadowOffset:NSMakeSize(0, -1)];
    [lineShadow setShadowBlurRadius:2.0];
    [lineShadow set];
    
    NSBezierPath *path = [NSBezierPath bezierPath];
    NSPoint pathStart, pathEnd;
    
    pathStart.y = pathEnd.y = NSMaxY(bezelRect);
    pathStart.x = -1;
    pathEnd.x = NSMinX([_tabControl frame]);
    [path moveToPoint:pathStart];
    [path lineToPoint:pathEnd];
    
    pathStart.x = NSMaxX([_tabControl frame]);
    pathEnd.x = NSMaxX([self bounds]) + 1;
    [path moveToPoint:pathStart];
    [path lineToPoint:pathEnd];
    
    [[NSColor colorWithDeviceWhite:0.67 alpha:1.0] setStroke];
    [path setLineWidth:1.0];
    [path stroke];

    [NSGraphicsContext restoreGraphicsState];
    
    [super drawRect:dirtyRect];

#if 0
    [[NSColor grayColor] set];

    NSRect bottomRect = [self bounds];
    bottomRect.size.height = 1;
    NSFrameRectWithWidth(bottomRect, 1.0);
    
    NSRect topRect = [self contentRect];
    topRect.origin.y = NSMaxY(topRect) - 1;
    topRect.size.height = 1;
    NSFrameRectWithWidth(topRect, 1.0);
#endif
}

@end
