//
//  TLMMirrorController.m
//  TeX Live Manager
//
//  Created by Adam R. Maxwell on 11/18/10.
/*
 This software is Copyright (c) 2010
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

#import "TLMMirrorController.h"
#import "TLMMirrorNode.h"

@interface TLMMirrorCell : NSTextFieldCell
{
@private
    NSImage *_icon;
}

@property (nonatomic, retain) NSImage *icon;

@end

@implementation TLMMirrorCell

static NSMutableDictionary *_iconsByURLScheme = nil;

+ (void)initialize
{
    if (nil == _iconsByURLScheme)
        _iconsByURLScheme = [NSMutableDictionary new];
}

@synthesize icon = _icon;

- (id)copyWithZone:(NSZone *)zone
{
    self = [super copyWithZone:zone];
    self->_icon = [self->_icon retain];
    return self;
}

- (void)dealloc
{
    [_icon release];
    [super dealloc];
}

- (NSImage *)_iconForURL:(NSURL *)aURL
{
    NSString *scheme = [aURL scheme];
    NSImage *icon = [_iconsByURLScheme objectForKey:scheme];
    if (nil == icon) {
        
        OSType iconType = kInternetLocationGenericIcon;
        if ([scheme hasPrefix:@"http"])
            iconType = kInternetLocationHTTPIcon;
        else if ([scheme hasPrefix:@"ftp"])
            iconType = kInternetLocationFTPIcon;
        else if ([scheme hasPrefix:@"file"])
            iconType = kInternetLocationFileIcon;
        
        icon = [[NSWorkspace sharedWorkspace] iconForFileType:NSFileTypeForHFSTypeCode(iconType)];
        [_iconsByURLScheme setObject:icon forKey:scheme];
    }
    return icon;
}

- (void)setObjectValue:(id <NSObject, NSCopying>)obj
{
    NSImage *icon = [obj respondsToSelector:@selector(scheme)] ? [self _iconForURL:obj] : nil;
    [self setIcon:icon];
    [super setObjectValue:obj];
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    
    NSRect iconRect = cellFrame;
    iconRect.size.width = NSHeight(cellFrame);
    if ([controlView isFlipped] && [self icon]) {
        CGContextRef ctxt = [[NSGraphicsContext currentContext] graphicsPort];
        CGContextSaveGState(ctxt);
        CGContextSetInterpolationQuality(ctxt, kCGInterpolationHigh);
        CGContextSetShouldAntialias(ctxt, true);
        CGContextTranslateCTM(ctxt, 0, NSMaxY(iconRect));
        CGContextScaleCTM(ctxt, 1, -1);
        iconRect.origin.y = 0;
        [[self icon] drawInRect:iconRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
        CGContextRestoreGState(ctxt);
    }
    
    cellFrame.origin.x = NSMaxX(iconRect);
    cellFrame.size.width -= NSWidth(iconRect);
    [super drawInteriorWithFrame:cellFrame inView:controlView];
}

@end



@implementation TLMMirrorController

@synthesize _outlineView;

- (id)init { return [self initWithWindowNibName:[self windowNibName]]; }

- (void)dealloc
{
    [_mirrors release];
    [_outlineView release];
    [_mirrorCell release];
    [super dealloc];
}

- (NSString *)windowNibName { return @"Mirrors"; }

- (void)_loadDefaultSites
{
    if ([_mirrors count])
        return;
    
    NSString *sitesFile = [[NSBundle mainBundle] pathForResource:@"CTAN.sites" ofType:@"plist"];
    NSDictionary *sites = [[NSDictionary dictionaryWithContentsOfFile:sitesFile] objectForKey:@"sites"];
    
    [_mirrors autorelease];
    _mirrors = [NSMutableArray new];
    
    for (NSString *continent in sites) {
        
        TLMMirrorNode *continentNode = [TLMMirrorNode new];
        [continentNode setValue:continent];
        [continentNode setType:TLMMirrorNodeContinent];
        
        NSMutableDictionary *countryNodes = [NSMutableDictionary dictionary];
        
        for (NSDictionary *mirrorInfo in [sites objectForKey:continent]) {
            
            NSString *countryName = [mirrorInfo objectForKey:@"country"];
            TLMMirrorNode *countryNode = [countryNodes objectForKey:countryName];
            if (nil == countryNode) {
                countryNode = [TLMMirrorNode new];
                [countryNode setType:TLMMirrorNodeCountry];
                [countryNode setValue:[mirrorInfo objectForKey:@"country"]];
                [countryNodes setObject:countryNode forKey:countryName];
                [countryNode release];
            }
            
            TLMMirrorNode *mirrorSite = [TLMMirrorNode new];
            [mirrorSite setValue:[mirrorInfo objectForKey:@"name"]];
            [mirrorSite setType:TLMMirrorNodeSite];
            for (NSString *URLString in [mirrorInfo objectForKey:@"urls"]) {
                TLMMirrorNode *URLNode = [TLMMirrorNode new];
                [URLNode setValue:[NSURL URLWithString:URLString]];
                [URLNode setType:TLMMirrorNodeURL];
                [mirrorSite addChild:URLNode];
                [URLNode release];
            }
            
            [countryNode addChild:mirrorSite];
            [mirrorSite release];
            
        }
        
        for (NSString *countryName in countryNodes)
            [continentNode addChild:[countryNodes objectForKey:countryName]];
        
        [_mirrors addObject:continentNode];
        [continentNode release];
    }    
}

- (void)awakeFromNib
{        
    [self _loadDefaultSites];
    if (nil == _mirrorCell)
        _mirrorCell = [[TLMMirrorCell alloc] initTextCell:@""];
    [_outlineView reloadData];
}

#pragma mark NSOutlineView datasource

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)anIndex ofItem:(TLMMirrorNode *)item;
{
    return nil == item ? [_mirrors objectAtIndex:anIndex] : [item childAtIndex:anIndex];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(TLMMirrorNode *)item;
{
    return [item numberOfChildren];
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(TLMMirrorNode *)item;
{
    return nil == item ? [_mirrors count] : [item numberOfChildren];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(TLMMirrorNode *)item;
{
    return [item valueForKey:[tableColumn identifier]];
}

- (void)outlineView:(TLMOutlineView *)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(TLMMirrorNode *)item;
{
    NSFont *defaultFont = [outlineView defaultFont];
    
    if ([item type] == TLMMirrorNodeCountry) {
        [cell setFont:[NSFont boldSystemFontOfSize:[defaultFont pointSize]]];
    }
    else if (defaultFont) {
        [cell setFont:defaultFont];
    }
}

- (NSCell *)outlineView:(NSOutlineView *)outlineView dataCellForTableColumn:(NSTableColumn *)tableColumn item:(TLMMirrorNode *)item
{
    if (nil == tableColumn) return nil;
    if ([item type] == TLMMirrorNodeURL) {
        return _mirrorCell;
    }
    return [[[NSTextFieldCell alloc] initTextCell:@""] autorelease];
}

- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(TLMMirrorNode *)item
{
    return [item type] == TLMMirrorNodeURL ? 24.0 : 17.0;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(TLMMirrorNode *)item
{
    return [item type] == TLMMirrorNodeContinent;
}

- (id)outlineView:(NSOutlineView *)outlineView itemForPersistentObject:(id)object;
{
    [self _loadDefaultSites];
    return [NSKeyedUnarchiver unarchiveObjectWithData:object];
}

- (id)outlineView:(NSOutlineView *)outlineView persistentObjectForItem:(TLMMirrorNode *)item;
{
    return [NSKeyedArchiver archivedDataWithRootObject:item];
}
/*
- (void)outlineView:(TLMOutlineView *)outlineView writeSelectedRowsToPasteboard:(NSPasteboard *)pboard;
{
    if ([outlineView numberOfRows] != [outlineView numberOfSelectedRows])
        return NSBeep();
    
    NSString *profileString = [TLMMirrorNode profileStringWithRoot:_rootNode];
    [pboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    [pboard setString:profileString forType:NSStringPboardType];
}
 
 */

@end
