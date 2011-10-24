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
@synthesize progressValue = _progressValue;
@synthesize maximumProgressValue = _maximum;
@synthesize minimumProgressValue = _minimum;

static NSImage *_grayImage = nil;
static NSImage *_blueImage = nil;

+ (void)initialize
{
    if (nil == _grayImage) {
        _grayImage = [[NSImage imageNamed:@"LionGraphiteProgress.png"] retain];
        _blueImage = [[NSImage imageNamed:@"LionBlueProgress.png"] retain];
    }
}

- (void)commonInit
{
    [self setScrollable:YES];
    [self setLineBreakMode:NSLineBreakByTruncatingTail];
    [self setDrawsBackground:NO];
    [self setBordered:NO];
    _buttonCell = [[NSButtonCell alloc] initImageCell:[NSImage imageNamed:NSImageNameStopProgressFreestandingTemplate]];
    [_buttonCell setButtonType:NSMomentaryChangeButton];
    [_buttonCell setBordered:NO];
    [_buttonCell setImagePosition:NSImageOnly];
    [_buttonCell setImageScaling:NSImageScaleProportionallyUpOrDown];    
    [_buttonCell setControlSize:[self controlSize]];
    _maximum = 100;
    _minimum = 0;  
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

- (void)incrementProgressBy:(double)value;
{
    _progressValue += value;
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
    return NSInsetRect(buttonRect, 4, 4);
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
    NSImage *progressImage = nil;
    NSRect iconRect = [self iconRectForBounds:cellFrame];

    if (_progressValue > _minimum && _progressValue <= _maximum) {
        switch ([NSColor currentControlTint]) {
            case NSBlueControlTint:
                progressImage = [[controlView window] isKeyWindow] ? _blueImage : _grayImage;
                break;
            case NSGraphiteControlTint:
                progressImage = _grayImage;
                break;
            default:
                break;
        }
    }
    
    if (progressImage) {
        // full width is width of text rect; don't draw under the favicon or button cell
        NSRect imageBounds = [self textRectForBounds:cellFrame];
        imageBounds.size.width = _progressValue / (_maximum - _minimum) * NSWidth(imageBounds);
        imageBounds.size.height -= 4;
        imageBounds.origin.y += 2;
        [progressImage drawInRect:imageBounds fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
    }    
    
    if ([self icon]) {
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
    NSImage *leftCap = nil;
    NSImage *middle = nil;
    NSImage *rightCap = nil;
    
    if ([[controlView window] isKeyWindow]) {
        leftCap = [NSImage imageNamed:@"AddressFieldCapLeft.png"];
        middle = [NSImage imageNamed:@"TextFieldStretch.png"];
        rightCap = [NSImage imageNamed:@"AddressFieldCapRight.png"];
    }
    else {
        leftCap = [NSImage imageNamed:@"AddressFieldCapLeftInactive.png"];
        middle = [NSImage imageNamed:@"TextFieldStretchInactive.png"];
        rightCap = [NSImage imageNamed:@"AddressFieldCapRightInactive.png"];        
    }
    NSParameterAssert(leftCap && middle && rightCap);
    NSDrawThreePartImage(cellFrame, leftCap, middle, rightCap, NO, NSCompositeSourceOver, 1.0, [controlView isFlipped]);
    
    [super drawWithFrame:cellFrame inView:controlView];
}

- (NSFocusRingType)focusRingType { return floor(NSAppKitVersionNumber) < 1100 ? NSFocusRingTypeNone : [super focusRingType]; }

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

// adjustments to avoid text jumping when editing or selecting
static void __adjust_editor_rect(NSRect *textRect, NSView *controlView)
{
    textRect->origin.y += ([controlView isFlipped] ? 2 : -2);
    //textRect->origin.x += 1;
}

- (void)editWithFrame:(NSRect)cellFrame inView:(NSView *)controlView editor:(NSText *)textObj delegate:(id)anObject event:(NSEvent *)theEvent;
{
    NSRect textRect = [self textRectForBounds:cellFrame];
    __adjust_editor_rect(&textRect, controlView);
    [super editWithFrame:textRect inView:controlView editor:textObj delegate:anObject event:theEvent];
}

- (void)selectWithFrame:(NSRect)cellFrame inView:(NSView *)controlView editor:(NSText *)textObj delegate:(id)anObject start:(NSInteger)selStart length:(NSInteger)selLength;
{
    NSRect textRect = [self textRectForBounds:cellFrame];
    __adjust_editor_rect(&textRect, controlView);
    [super selectWithFrame:textRect inView:controlView editor:textObj delegate:anObject start:selStart length:selLength];
}

- (void)setButtonImage:(NSImage *)image { [_buttonCell setImage:image]; }
- (void)setButtonAction:(SEL)action { [_buttonCell setAction:action]; }
- (void)setButtonTarget:(id)target { [_buttonCell setTarget:target]; }

@end
