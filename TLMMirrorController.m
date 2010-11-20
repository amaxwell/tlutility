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
#import "TLMMirrorCell.h"
#import "TLMLogServer.h"

@interface TLMMirrorController (Private)
- (void)_loadDefaultSites;
@end


@implementation TLMMirrorController

@synthesize _outlineView;

- (id)init
{
    self = [self initWithWindowNibName:[self windowNibName]];
    if (self) {
        _textFieldCell = [[NSTextFieldCell alloc] initTextCell:@""];
        _mirrorCell = [[TLMMirrorCell alloc] initTextCell:@""];
        [self _loadDefaultSites];
    }
    return self;
}

- (void)dealloc
{
    [_mirrors release];
    [_outlineView release];
    [_mirrorCell release];
    [_textFieldCell release];
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
                [countryNode setValue:countryName];
                [countryNodes setObject:countryNode forKey:countryName];
                [countryNode release];
            }
            
            for (NSString *URLString in [mirrorInfo objectForKey:@"urls"]) {
                TLMMirrorNode *URLNode = [TLMMirrorNode new];
                [URLNode setValue:[NSURL URLWithString:URLString]];
                [URLNode setType:TLMMirrorNodeURL];
                [countryNode addChild:URLNode];
                [URLNode release];
            }
                        
        }
        
        for (NSString *countryName in countryNodes)
            [continentNode addChild:[countryNodes objectForKey:countryName]];
        
        [_mirrors addObject:continentNode];
        [continentNode release];
    }    
}

- (void)awakeFromNib
{        
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
    return [item type] == TLMMirrorNodeURL ? _mirrorCell : _textFieldCell;
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

- (BOOL)outlineView:(NSOutlineView *)outlineView writeItems:(NSArray *)items toPasteboard:(NSPasteboard *)pasteboard;
{
    OSStatus err;
        
    PasteboardRef carbonPboard;
    err = PasteboardCreate((CFStringRef)[pasteboard name], &carbonPboard);
    
    if (noErr == err)
        err = PasteboardClear(carbonPboard);
    
    if (noErr == err)
        (void)PasteboardSynchronize(carbonPboard);
    
    if (noErr != err) {
        TLMLog(__func__, @"failed to setup pboard %@: %s", [pasteboard name], GetMacOSStatusErrorString(err));
        return NO;
    }
        
    for (TLMMirrorNode *node in items) {
        
        if ([node type] != TLMMirrorNodeURL)
            continue;
        
        NSString *string = [[node value] absoluteString];
        CFDataRef utf8Data = (CFDataRef)[string dataUsingEncoding:NSUTF8StringEncoding];
        
        // any pointer type; private to the creating application
        PasteboardItemID itemID = (void *)node;
        
        // Finder adds a file URL and destination URL for weblocs, but only a file URL for regular files
        // could also put a string representation of the URL, but Finder doesn't do that
        
        if ([[node value] isFileURL]) {
            err = PasteboardPutItemFlavor(carbonPboard, itemID, kUTTypeFileURL, utf8Data, kPasteboardFlavorNoFlags);
        }
        else {
            err = PasteboardPutItemFlavor(carbonPboard, itemID, kUTTypeURL, utf8Data, kPasteboardFlavorNoFlags);
        }
        
        if (noErr != err)
            TLMLog(__func__, @"failed to write to pboard %@: %s", [pasteboard name], GetMacOSStatusErrorString(err));
    }
    
    ItemCount itemCount;
    err = PasteboardGetItemCount(carbonPboard, &itemCount);
    
    if (carbonPboard) 
        CFRelease(carbonPboard);

    return noErr == err && itemCount > 0;
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
