//
//  TLMMirrorCell.m
//  TeX Live Manager
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

@implementation TLMMirrorCell

static NSMutableDictionary *_iconsByURLScheme = nil;

+ (void)initialize
{
    if (nil == _iconsByURLScheme)
        _iconsByURLScheme = [NSMutableDictionary new];
}

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
    self = [super copyWithZone:zone];
    [self->_icon retain];
    return self;
}

- (void)dealloc
{
    [_icon release];
    [super dealloc];
}

- (NSImage *)_iconForURL:(NSURL *)aURL
{
    // !!! early return
    if (nil == aURL) return nil;
    
    NSString *scheme = [aURL scheme];
    NSImage *icon = [_iconsByURLScheme objectForKey:scheme];
    if (nil == icon) {
        
        OSType iconType = kInternetLocationGenericIcon;
        if ([scheme hasPrefix:@"http"])
            iconType = kInternetLocationHTTPIcon;
        else if ([scheme isEqualToString:@"ftp"])
            iconType = kInternetLocationFTPIcon;
        else if ([scheme isEqualToString:@"file"])
            iconType = kInternetLocationFileIcon;
        else if ([scheme isEqualToString:@"afp"])
            iconType = kInternetLocationAppleShareIcon;
        
        IconRef iconRef;
        if (noErr == GetIconRef(kOnSystemDisk, kSystemIconsCreator, iconType, &iconRef)) {
            icon = [[[NSImage alloc] initWithIconRef:iconRef] autorelease];
            ReleaseIconRef(iconRef);
        }

        [_iconsByURLScheme setObject:icon forKey:scheme];
    }
    NSParameterAssert(icon);
    return icon;
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

- (NSRect)textRectForBounds:(NSRect)cellFrame
{
    NSRect iconRect = [self iconRectForBounds:cellFrame];
    cellFrame.origin.x = NSMaxX(iconRect);
    cellFrame.size.width -= NSWidth(iconRect);
    return cellFrame;    
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    
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
        [[self icon] drawInRect:NSInsetRect(iconRect, 1, 1) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
        CGContextRestoreGState(ctxt);
    }
    
    [super drawInteriorWithFrame:[self textRectForBounds:cellFrame] inView:controlView];
}

- (void)drawWithFrame:(NSRect)aRect inView:(NSView *)controlView
{
    [super drawWithFrame:aRect inView:controlView];
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
        NSRectFill([self textRectForBounds:aRect]);
        [NSGraphicsContext restoreGraphicsState];
    }
#endif
}

- (NSRect)expansionFrameWithFrame:(NSRect)cellFrame inView:(NSView *)view;
{
    // see if constrained text width is less than the ideal text rect
    if (NSWidth([self textRectForBounds:cellFrame]) < [super cellSize].width) {
        // set width to constrained text width, and let super figure out the required frame since [self cellSize].width isn't quite enough
        cellFrame.size.width = NSWidth([self textRectForBounds:cellFrame]);
        NSRect expansionFrame = [super expansionFrameWithFrame:cellFrame inView:view];
        // SL needs this?
        expansionFrame.size.height = NSHeight(cellFrame);
        return expansionFrame;
    }
    return NSZeroRect;
}

- (BOOL)trackMouse:(NSEvent *)event inRect:(NSRect)cellFrame ofView:(NSView *)controlView untilMouseUp:(BOOL)flag;
{
    NSPoint mouseLoc = [controlView convertPoint:[event locationInWindow] fromView:nil];
    if ([self icon] && NSMouseInRect(mouseLoc, [self iconRectForBounds:cellFrame], [controlView isFlipped])) {
        
        if (NSLeftMouseDragged == [[NSApp nextEventMatchingMask:NSLeftMouseUpMask | NSLeftMouseDraggedMask untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:NO] type]) {        
            NSPasteboard *pboard = [NSPasteboard pasteboardWithName:NSDragPboard];
            [NSURL writeURLs:[NSArray arrayWithObject:[NSURL URLWithString:[self stringValue]]] toPasteboard:pboard];
            NSImage *dragImage = [[[self icon] copy] autorelease];
            [dragImage setSize:[self iconRectForBounds:cellFrame].size];
            NSPoint dragImageOrigin = [controlView convertPoint:[event locationInWindow] fromView:nil];
            dragImageOrigin.x -= [dragImage size].width / 2;
            dragImageOrigin.y = [controlView isFlipped] ? dragImageOrigin.y + [dragImage size].height / 2 : dragImageOrigin.y - [dragImage size].width / 2;
            [controlView dragImage:dragImage at:dragImageOrigin offset:NSZeroSize event:event pasteboard:pboard source:controlView slideBack:YES];
        }
    }
    else {
        return [super trackMouse:event inRect:cellFrame ofView:controlView untilMouseUp:flag];
    }
    return YES;
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

#if 0
- (NSUInteger)hitTestForEvent:(NSEvent *)event inRect:(NSRect)cellFrame ofView:(NSView *)controlView
{
    NSUInteger hit = NSCellHitNone;
    NSPoint mouseLoc = [controlView convertPoint:[event locationInWindow] fromView:nil];
    if (NSMouseInRect(mouseLoc, cellFrame, [controlView isFlipped]))
        hit = NSCellHitContentArea;
    
    NSRect iconRect = [self iconRectForBounds:cellFrame];
    
    if (NSMouseInRect(mouseLoc, iconRect, [controlView isFlipped])) {
        hit |= NSCellHitTrackableArea;
    }
    else if (NSMouseInRect(mouseLoc, [self textRectForBounds:cellFrame], [controlView isFlipped])) {
        if ([self isEnabled]) hit |= NSCellHitEditableTextArea;
    }
    return hit;
}
#endif

@end
