//
//  TLMTabView.m
//  TabViewTest
//
//  Created by Adam Maxwell on 12/23/08.
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
    aRect = [self bounds];
    [[NSColor clearColor] setFill];
    NSRectFillUsingOperation(aRect, NSCompositeSourceOver);
    [[self image] drawInRect:aRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:[self imageAlphaValue]];
}

@end

@implementation TLMTabView

@synthesize delegate = _delegate;

- (void)_commonInit
{
    _tabControl = [[NSSegmentedControl allocWithZone:[self zone]] initWithFrame:NSZeroRect];
    
    // margin value is based on this segment style, unfortunately
#define TAB_CONTROL_MARGIN 1.0
    [_tabControl setSegmentStyle:NSSegmentStyleSmallSquare];
    
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

- (void)addTabNamed:(NSString *)tabName withView:(NSView *)aView;
{
    NSParameterAssert(tabName);
    NSParameterAssert(aView);
    [_tabControl setSegmentCount:([_tabControl segmentCount] + 1)];
    [_tabControl setLabel:tabName forSegment:([_tabControl segmentCount] - 1)];
    [_tabControl sizeToFit];
    NSRect frame = [_tabControl bounds];
    frame.origin.y = NSMaxY([self bounds]) - NSHeight(frame) + TAB_CONTROL_MARGIN;
    frame.origin.x = 0.5 * (NSWidth([self bounds]) - NSWidth(frame));
    [_tabControl setFrame:[self centerScanRect:frame]];
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
        [_transitionViews makeObjectsPerformSelector:@selector(removeFromSuperview)];     
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
    imageRep = [_currentView bitmapImageRepForCachingDisplayInRect:[_currentView bounds]];
    [_currentView cacheDisplayInRect:[_currentView bounds] toBitmapImageRep:imageRep];
    image = [[NSImage alloc] initWithSize:[_currentView bounds].size];
    [image addRepresentation:imageRep];
    [[_transitionViews objectAtIndex:0] setImage:image];
    [[_transitionViews objectAtIndex:1] setImageAlphaValue:1.0];
    [image release];
    
    // only remove after caching to bitmap
    [_currentView removeFromSuperviewWithoutNeedingDisplay];
    
    // now cache the next view to a bitmap and set it initially transparent
    imageRep = [nextView bitmapImageRepForCachingDisplayInRect:[nextView bounds]];
    [nextView cacheDisplayInRect:[nextView bounds] toBitmapImageRep:imageRep];
    image = [[NSImage alloc] initWithSize:[nextView bounds].size];
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
    
    // avoid an initial flash before the timer fires, since _currentView was removed
    [self displayRectIgnoringOpacity:[[_transitionViews objectAtIndex:0] frame]];
    
    // set now, since the timer callback needs it
    _currentView = nextView;
    
    // animate ~30 fps for 0.3 seconds, using NSAnimation to get the alpha curve
    NSAnimation *animation = [[NSAnimation alloc] initWithDuration:0.3 animationCurve:NSAnimationEaseInOut]; 
    [animation setAnimationBlockingMode:NSAnimationNonblockingThreaded];
    [NSTimer scheduledTimerWithTimeInterval:0.03 target:self selector:@selector(animationFired:) userInfo:animation repeats:YES];
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
    NSRect viewFrame = [self bounds];
    viewFrame.size.height -= (NSHeight([_tabControl frame]) - 3 * TAB_CONTROL_MARGIN);
    [nextView setFrame:viewFrame];
    
    NSParameterAssert([nextView isDescendantOf:self] == NO);
    [self addSubview:nextView];
    [self setNeedsDisplay:YES];

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

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor lightGrayColor] setFill];
    NSFrameRectWithWidth([self centerScanRect:[self bounds]], 0.0);
    [super drawRect:dirtyRect];
}

@end
