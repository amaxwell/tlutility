//
//  TLMTabView.m
//  TabViewTest
//
//  Created by Adam Maxwell on 12/23/08.
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

#import "TLMTabView.h"
#import <QuartzCore/QuartzCore.h>

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
    
    NSImageView *imageViews[2];
    imageViews[0] = [[NSImageView allocWithZone:[self zone]] initWithFrame:[self frame]];
    imageViews[1] = [[NSImageView allocWithZone:[self zone]] initWithFrame:[self frame]];
    _transitionViews = [[NSArray allocWithZone:[self zone]] initWithObjects:imageViews count:2];
    for (NSImageView *imageView in _transitionViews) {
        [imageView setWantsLayer:YES];
        [imageView setImageScaling:NSImageScaleProportionallyUpOrDown];
        [imageView setImageFrameStyle:NSImageFrameNone];
        [imageView setImageAlignment:NSImageAlignCenter];        
    }
    
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

- (void)animationDidStop:(CAPropertyAnimation *)anim finished:(BOOL)flag;
{
    if (flag) {
        [[[_transitionViews objectAtIndex:0] animationForKey:@"alphaValue"] setDelegate:nil];
        [[[_transitionViews objectAtIndex:1] animationForKey:@"alphaValue"] setDelegate:nil];
        [_transitionViews makeObjectsPerformSelector:@selector(removeFromSuperview)];     
        [self setWantsLayer:NO];
        
        NSParameterAssert([_currentView isDescendantOf:self]);
        if ([_currentView isHidden]) {
            [_currentView setHidden:NO];
            [self setNeedsDisplay:YES];
        }
    }
}

#define TRANSPARENT 0.0
#define OPAQUE 1.0

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

    if ([_currentView isDescendantOf:self]) {
        
        // will unhide when animation finishes
        [nextView setHidden:YES];
        [self setWantsLayer:YES];

        [[_transitionViews objectAtIndex:0] setFrame:viewFrame];
        [[_transitionViews objectAtIndex:1] setFrame:viewFrame];
        
        NSBitmapImageRep *imageRep;
        NSImage *image;
        
        // cache the currently displayed view to a bitmap
        imageRep = [_currentView bitmapImageRepForCachingDisplayInRect:[_currentView bounds]];
        [_currentView cacheDisplayInRect:[_currentView bounds] toBitmapImageRep:imageRep];
        image = [[NSImage alloc] initWithSize:[_currentView bounds].size];
        [image addRepresentation:imageRep];
        [[_transitionViews objectAtIndex:0] setImage:image];
        [[_transitionViews objectAtIndex:0] setAlphaValue:OPAQUE];
        [image release];
        
        // only remove after caching to bitmap
        [_currentView removeFromSuperviewWithoutNeedingDisplay];
        
        // now cache the final view to a bitmap
        imageRep = [nextView bitmapImageRepForCachingDisplayInRect:[nextView bounds]];
        [nextView cacheDisplayInRect:[nextView bounds] toBitmapImageRep:imageRep];
        image = [[NSImage alloc] initWithSize:[nextView bounds].size];
        [image addRepresentation:imageRep];
        [[_transitionViews objectAtIndex:1] setImage:image];
        [[_transitionViews objectAtIndex:1] setAlphaValue:TRANSPARENT];
        [image release];
        
        // add both image views as subviews
        [self addSubview:[_transitionViews objectAtIndex:0]];
        [self addSubview:[_transitionViews objectAtIndex:1]];      
        [self setNeedsDisplay:YES];
        
        // use the delegate method to find out when the animation is complete
        [[[_transitionViews objectAtIndex:0] animationForKey:@"alphaValue"] setDelegate:self];
        [[[_transitionViews objectAtIndex:1] animationForKey:@"alphaValue"] setDelegate:self];        
                
        [NSAnimationContext beginGrouping];
        // ??? why does [[NSAnimationContext currentContext] setDuration:] have no effect here?
        [[[_transitionViews objectAtIndex:0] animator] setAlphaValue:TRANSPARENT];
        [[[_transitionViews objectAtIndex:1] animator] setAlphaValue:OPAQUE];
        [NSAnimationContext endGrouping];        
    }

    _currentView = nextView;
    
    if ([[self delegate] respondsToSelector:@selector(tabView:didSelectViewAtIndex:)])
        [(id <TLMTabViewDelegate>)[self delegate] tabView:self didSelectViewAtIndex:anIndex];
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
