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

#import "TLMAddressTextFieldCell.h"
#import <WebKit/WebKit.h>

@implementation TLMAddressTextFieldCell

#define FAVICON_INSET ((NSSize) { 2, 2 })

@synthesize icon = _icon;

- (void)commonInit
{
    [self setScrollable:YES];
    [self setLineBreakMode:NSLineBreakByTruncatingTail];
    _buttonCell = [[NSButtonCell alloc] initImageCell:[NSImage imageNamed:NSImageNameStopProgressFreestandingTemplate]];
    [_buttonCell setButtonType:NSMomentaryChangeButton];
    [_buttonCell setBordered:NO];
    [_buttonCell setImagePosition:NSImageOnly];
    [_buttonCell setImageScaling:NSImageScaleProportionallyUpOrDown];    
}

- (id)initTextCell:(NSString *)aString
{
    self = [super initTextCell:aString];
    [self commonInit];
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    [self commonInit];
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    TLMAddressTextFieldCell *copy = [super copyWithZone:zone];
    [copy->_icon retain];
    copy->_buttonCell = [_buttonCell copyWithZone:zone];
    return copy;
}

- (void)dealloc
{
    [_icon release];
    [_buttonCell release];
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
        icon = [self _iconForURL:[NSURL URLWithString:obj]];
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

- (NSRect)buttonRectForBounds:(NSRect)cellFrame
{
    NSRect buttonRect = cellFrame;
    buttonRect.origin.x = NSMaxX(cellFrame) - NSHeight(cellFrame);
    buttonRect.size.width = NSHeight(cellFrame);
    return NSInsetRect(buttonRect, 3, 3);
}

- (NSRect)textRectForBounds:(NSRect)cellFrame
{
    NSRect iconRect = [self iconRectForBounds:cellFrame];
    cellFrame.origin.x = NSMaxX(iconRect);
    cellFrame.size.width -= NSWidth(iconRect);
    cellFrame.size.width -= (NSWidth([self buttonRectForBounds:cellFrame]) + 2 /* padding */);
    return cellFrame;    
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    NSBezierPath *roundRect = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(cellFrame, 0.5, 0.5) xRadius:4 yRadius:4];
    [[NSColor blackColor] setStroke];
    [roundRect stroke];
    
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
    [_buttonCell drawWithFrame:[self buttonRectForBounds:cellFrame] inView:controlView];
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    cellFrame = NSInsetRect(cellFrame, 0.5, 0.5);
    
    [super drawWithFrame:cellFrame inView:controlView];
        
    [NSGraphicsContext saveGraphicsState];
    NSBezierPath *framePath = [NSBezierPath bezierPathWithRect:NSInsetRect(cellFrame, -0.5, -0.5)];
    [framePath setWindingRule:NSEvenOddWindingRule];
    
    NSBezierPath *roundRect = [NSBezierPath bezierPathWithRoundedRect:cellFrame xRadius:4 yRadius:4];
    [framePath appendBezierPath:roundRect];
    
    [[[controlView window] backgroundColor] setFill];
    [framePath fill];
    
    [[NSColor darkGrayColor] setStroke];
    [roundRect stroke];
    
    [NSGraphicsContext restoreGraphicsState];
    
#if 0
    /*
     Editing causes a white border to be drawn around the cell, and the focus ring doesn't
     entirely fill it.  Mail has the same issue, so it's not worth playing with the text rect
     to lessen the effect.  It's not drawn by super's drawWithFrame or drawInteriorWithFrame,
     so it's probably the outline view itself.
     */
    if ([self showsFirstResponder]) {
        [NSGraphicsContext saveGraphicsState];
        NSSetFocusRingStyle(NSFocusRingAbove);
        NSRectFill([self textRectForBounds:cellFrame]);
        [NSGraphicsContext restoreGraphicsState];
    }
#endif
}

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

- (BOOL)trackMouse:(NSEvent *)event inRect:(NSRect)cellFrame ofView:(NSView *)controlView untilMouseUp:(BOOL)flag;
{
    NSPoint mouseLoc = [controlView convertPoint:[event locationInWindow] fromView:nil];
    if ([self icon] && NSMouseInRect(mouseLoc, [self iconRectForBounds:cellFrame], [controlView isFlipped])) {
        
        if (NSLeftMouseDragged == [[NSApp nextEventMatchingMask:NSLeftMouseUpMask | NSLeftMouseDraggedMask untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:NO] type]) {        
            NSPasteboard *pboard = [NSPasteboard pasteboardWithName:NSDragPboard];
            [NSURL writeURLs:[NSArray arrayWithObject:[NSURL URLWithString:[self stringValue]]] toPasteboard:pboard];
            NSImage *dragImage = [[[self icon] copy] autorelease];
            NSSize dragImageSize = [self iconRectForBounds:cellFrame].size;
            dragImageSize.width -= FAVICON_INSET.width * 2;
            dragImageSize.height -= FAVICON_INSET.height * 2;
            [dragImage setSize:dragImageSize];
            NSPoint dragImageOrigin = [controlView convertPoint:[event locationInWindow] fromView:nil];
            dragImageOrigin.x -= dragImageSize.width / 2;
            dragImageOrigin.y = [controlView isFlipped] ? dragImageOrigin.y + dragImageSize.height / 2 : dragImageOrigin.y - dragImageSize.width / 2;
            [controlView dragImage:dragImage at:dragImageOrigin offset:NSZeroSize event:event pasteboard:pboard source:controlView slideBack:YES];
        }
        return YES;
    }
    else if (NSMouseInRect(mouseLoc, [self buttonRectForBounds:cellFrame], [controlView isFlipped])) {
        // NSButtonCell does not highlight itself, it tracks until a click or the mouse exits
        [_buttonCell highlight:YES withFrame:[self buttonRectForBounds:cellFrame] inView:controlView];
        [_buttonCell trackMouse:event inRect:[self buttonRectForBounds:cellFrame] ofView:controlView untilMouseUp:NO];
        [_buttonCell highlight:NO withFrame:[self buttonRectForBounds:cellFrame] inView:controlView];
        return YES;
    }
    return [super trackMouse:event inRect:cellFrame ofView:controlView untilMouseUp:flag];
}

- (NSFocusRingType)focusRingType { return NSFocusRingTypeNone; }

- (void)editWithFrame:(NSRect)cellFrame inView:(NSView *)controlView editor:(NSText *)textObj delegate:(id)anObject event:(NSEvent *)theEvent;
{
    [super editWithFrame:[self textRectForBounds:cellFrame] inView:controlView editor:textObj delegate:anObject event:theEvent];
}

- (void)selectWithFrame:(NSRect)cellFrame inView:(NSView *)controlView editor:(NSText *)textObj delegate:(id)anObject start:(NSInteger)selStart length:(NSInteger)selLength;
{
    [super selectWithFrame:[self textRectForBounds:cellFrame] inView:controlView editor:textObj delegate:anObject start:selStart length:selLength];
}

- (NSUInteger)hitTestForEvent:(NSEvent *)event inRect:(NSRect)cellFrame ofView:(NSView *)controlView
{
    NSUInteger hit = NSCellHitNone;
    NSPoint mouseLoc = [controlView convertPoint:[event locationInWindow] fromView:nil];
    if (NSMouseInRect(mouseLoc, cellFrame, [controlView isFlipped]))
        hit = NSCellHitContentArea;
    
    NSRect iconRect = [self iconRectForBounds:cellFrame];
    NSRect buttonRect = [self buttonRectForBounds:cellFrame];
    
    if (NSMouseInRect(mouseLoc, iconRect, [controlView isFlipped]) || NSMouseInRect(mouseLoc, buttonRect, [controlView isFlipped])) {
        hit |= NSCellHitTrackableArea;
    }
    else if (NSMouseInRect(mouseLoc, [self textRectForBounds:cellFrame], [controlView isFlipped])) {
        if ([self isEnabled]) hit |= NSCellHitEditableTextArea;
    }
    return hit;
}

@end

