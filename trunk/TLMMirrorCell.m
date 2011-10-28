//
//  TLMMirrorCell.m
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 11/20/10.
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

#import "TLMMirrorCell.h"
#import <WebKit/WebKit.h>

@implementation TLMMirrorCell

#define FAVICON_INSET ((NSSize) { 2, 2 })

@synthesize icon = _icon;

- (id)initTextCell:(NSString *)aString
{
    self = [super initTextCell:aString];
    if (self) {
        [self setScrollable:YES];
        [self setLineBreakMode:NSLineBreakByTruncatingTail];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    TLMMirrorCell *copy = [super copyWithZone:zone];
    [copy->_icon retain];
    return copy;
}

- (void)dealloc
{
    [_icon release];
    [super dealloc];
}

- (void)iconCache:(TLMFaviconCache *)cache downloadedIcon:(NSImage *)anIcon forURL:(NSURL *)aURL;
{
    [self setIcon:anIcon];
    [[self controlView] setNeedsDisplay:YES];
}

- (NSImage *)_iconForURL:(NSURL *)aURL
{
    return aURL ? [[TLMFaviconCache sharedCache] downloadIconForURL:aURL delegate:self] : nil;
}

- (void)setObjectValue:(id <NSCopying>)obj
{
    NSImage *icon = nil;
    if ([(id)obj isKindOfClass:[NSURL class]])
        icon = [self _iconForURL:(NSURL *)obj];
    else if ([(id)obj isKindOfClass:[NSString class]] && [(NSString *)obj isEqualToString:@""] == NO)
        icon = [self _iconForURL:[NSURL URLWithString:(NSString *)obj]];
    [self setIcon:icon];
    [super setObjectValue:obj];
}

- (void)setStringValue:(NSString *)aString
{
    NSURL *aURL = nil;
    if (aString && [aString isEqualToString:@""] == NO)
        aURL = [NSURL URLWithString:aString];
    [self setIcon:[self _iconForURL:aURL]];
    [super setStringValue:aString];
}

- (NSRect)drawingRectForBounds:(NSRect)theRect
{
    NSRect drawingRect = [super drawingRectForBounds:theRect];
    NSSize cellSize = [self cellSizeForBounds:theRect];
        
    CGFloat offset = NSHeight(drawingRect) - cellSize.height;      
    if (offset > 0.5) {
        drawingRect.size.height -= offset;
        drawingRect.origin.y += (offset / 2);
    }
    
    return drawingRect;
}

- (NSRect)iconRectForBounds:(NSRect)cellFrame
{
    NSRect iconRect = cellFrame;
    iconRect.size.width = NSHeight(cellFrame);
    return iconRect;
}

- (NSRect)textRectForBounds:(NSRect)cellFrame
{
    NSRect iconRect = [self iconRectForBounds:cellFrame];
    cellFrame.origin.x = NSMaxX(iconRect);
    cellFrame.size.width -= NSWidth(iconRect);
    return cellFrame;    
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    if ([self drawsBackground]) {
        [NSGraphicsContext saveGraphicsState];
        [[self backgroundColor] setFill];
        NSRectFillUsingOperation(cellFrame, NSCompositeSourceOver);
        [NSGraphicsContext restoreGraphicsState];
    }    

    if ([self icon]) {
        NSRect iconRect = [self iconRectForBounds:cellFrame];
        CGContextRef ctxt = [[NSGraphicsContext currentContext] graphicsPort];
        CGContextSaveGState(ctxt);
        CGContextSetInterpolationQuality(ctxt, kCGInterpolationHigh);
        CGContextSetShouldAntialias(ctxt, true);
        if ([controlView isFlipped]) {
            CGContextTranslateCTM(ctxt, 0, NSMaxY(iconRect));
            CGContextScaleCTM(ctxt, 1, -1);
            iconRect.origin.y = 0;
        }
        [[self icon] drawInRect:NSInsetRect(iconRect, FAVICON_INSET.width, FAVICON_INSET.height) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
        CGContextRestoreGState(ctxt);
    }
    
    [super drawInteriorWithFrame:[self textRectForBounds:cellFrame] inView:controlView];
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    [super drawWithFrame:cellFrame inView:controlView];
    if ([self showsFirstResponder]) {
        [NSGraphicsContext saveGraphicsState];
        NSSetFocusRingStyle(NSFocusRingAbove);
        NSRectFill([self textRectForBounds:cellFrame]);
        [NSGraphicsContext restoreGraphicsState];
    }
}

- (NSFocusRingType)focusRingType { return NSFocusRingTypeNone; }

- (NSSize)cellSize;
{
    NSSize cellSize = [super cellSize];
    // cellSize.height approximates the icon size
    cellSize.width += cellSize.height;
    return cellSize;
}

#if 0
- (NSRect)expansionFrameWithFrame:(NSRect)cellFrame inView:(NSView *)view;
{
    NSRect expansionFrame = [super expansionFrameWithFrame:cellFrame inView:view];
    if (NSEqualRects(expansionFrame, NSZeroRect) == NO) {
        expansionFrame.size = [self cellSize];
        expansionFrame.size.height = NSHeight(cellFrame);
    }
    return expansionFrame;
}
#endif

- (void)editWithFrame:(NSRect)cellFrame inView:(NSView *)controlView editor:(NSText *)textObj delegate:(id)anObject event:(NSEvent *)theEvent;
{
    [super editWithFrame:[self textRectForBounds:cellFrame] inView:controlView editor:textObj delegate:anObject event:theEvent];
}

- (void)selectWithFrame:(NSRect)cellFrame inView:(NSView *)controlView editor:(NSText *)textObj delegate:(id)anObject start:(NSInteger)selStart length:(NSInteger)selLength;
{
    [super selectWithFrame:[self textRectForBounds:cellFrame] inView:controlView editor:textObj delegate:anObject start:selStart length:selLength];
}

@end
