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

#define USE_LAYERS 0

@implementation TLMTabView

@synthesize tabControl = _tabControl;
@synthesize delegate = _delegate;

- (void)_commonInit
{
    _tabControl = [[NSSegmentedControl allocWithZone:[self zone]] initWithFrame:NSZeroRect];
    [_tabControl setSegmentStyle:NSSegmentStyleSmallSquare];
    [self addSubview:_tabControl];
    [_tabControl setSegmentCount:0];
    [_tabControl setTarget:self];
    [_tabControl setAction:@selector(changeView:)];
    [_tabControl setAutoresizingMask:NSViewMinYMargin | NSViewMinXMargin | NSViewMaxXMargin];
    _views = [NSMutableArray new];    
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
    _delegate = nil;
    _currentView = nil;
    [_tabControl release];
    [_views release];
    [super dealloc];
}

#define TAB_CONTROL_MARGIN 1.0

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
    
    if ([_tabControl selectedSegment] == -1)
        [self selectViewAtIndex:0];
}

- (NSView *)viewAtIndex:(NSUInteger)anIndex;
{
    return [_views objectAtIndex:anIndex];
}

- (void)animationDidStop:(CAPropertyAnimation *)anim finished:(BOOL)flag;
{
    [[_previousView animationForKey:@"alphaValue"] setDelegate:nil];
    if (flag && [_previousView isDescendantOf:self])
        [_previousView removeFromSuperview];
    _previousView = nil;
#if USE_LAYERS
    if (flag && [self wantsLayer])
        [self setWantsLayer:NO];
#endif
}

- (void)selectViewAtIndex:(NSUInteger)anIndex;
{
    NSParameterAssert(anIndex < [_views count]);
    [_tabControl setSelectedSegment:anIndex];
    NSView *nextView = [_views objectAtIndex:anIndex];
    NSRect viewFrame = [self bounds];
    viewFrame.size.height -= (NSHeight([_tabControl frame]) - 3 * TAB_CONTROL_MARGIN);
    [nextView setFrame:viewFrame];
    // only set transparent if there's actually something to animate
    if (_currentView) {
        [nextView setAlphaValue:0.0];
    }
    [self addSubview:nextView];
#if USE_LAYERS
    [self setWantsLayer:YES];
#endif
    [NSAnimationContext beginGrouping];
    // only set delegate on alpha animation, since we only need the delegate callback once
    [[_currentView animationForKey:@"alphaValue"] setDelegate:self];
    [[_currentView animator] setAlphaValue:0.0];
    [[nextView animator] setAlphaValue:1.0];
    [NSAnimationContext endGrouping];
    _previousView = _currentView;
    _currentView = nextView;
    if ([[self delegate] respondsToSelector:@selector(tabView:didSelectViewAtIndex:)])
        [(id <TLMTabViewDelegate>)[self delegate] tabView:self didSelectViewAtIndex:anIndex];
}

- (IBAction)changeView:(id)sender
{
    NSParameterAssert([_tabControl segmentCount]);
    [self selectViewAtIndex:[_tabControl selectedSegment]];
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor lightGrayColor] setFill];
    NSFrameRectWithWidth([self centerScanRect:[self bounds]], 0.0);
    [super drawRect:dirtyRect];
}

@end
