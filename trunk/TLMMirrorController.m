//
//  TLMMirrorController.m
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 11/18/10.
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

#import "TLMMirrorController.h"
#import "TLMMirrorNode.h"
#import "TLMMirrorCell.h"
#import "TLMLogServer.h"
#import "TLMDatabase.h"
#import "TLMAppController.h"
#import "TLMMainWindowController.h"
#import "TLMEnvironment.h"
#import "TLMURLFormatter.h"

#define MIRRORS_FILENAME @"Mirrors.plist"
#define USER_MIRRORS_KEY @"User mirrors"

@interface TLMMirrorController (Private)
- (void)_loadDefaultSites;
@end

@implementation TLMMirrorController

@synthesize _outlineView;
@synthesize _addRemoveControl;

static NSString * __TLMUserMirrorsPath()
{
    static NSString *archivePath = nil;
    if (nil == archivePath) {
        archivePath = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) lastObject];
        NSString *appname = [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString *)kCFBundleNameKey];
        archivePath = [archivePath stringByAppendingPathComponent:appname];
        [[NSFileManager defaultManager] createDirectoryAtPath:archivePath withIntermediateDirectories:YES attributes:nil error:NULL];
        archivePath = [[archivePath stringByAppendingPathComponent:MIRRORS_FILENAME] copy];
    }
    return archivePath;
}

- (id)init
{
    self = [self initWithWindowNibName:[self windowNibName]];
    if (self) {
        _textFieldCell = [[NSTextFieldCell alloc] initTextCell:@""];
        _mirrorCell = [[TLMMirrorCell alloc] initTextCell:@""];
        [self _loadDefaultSites];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_handleVersionCheckNotification:)
                                                     name:TLMDatabaseVersionCheckComplete
                                                   object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_mirrorRoot release];
    [_outlineView release];
    [_mirrorCell release];
    [_textFieldCell release];
    [_addRemoveControl release];
    [super dealloc];
}

- (NSString *)windowNibName { return @"Mirrors"; }

static NSURL *__TLMTLNetURL(NSString *mirrorURLString)
{
    return [NSURL TLNetURLForMirror:[NSURL URLWithString:mirrorURLString]];
}

- (TLMMirrorNode *)_customNode
{
    return [_mirrorRoot childAtIndex:0];
}

- (void)_archivePlist
{
    NSMutableArray *array = [NSMutableArray array];
    for (TLMMirrorNode *userNode in [self _customNode]) {
        if ([(NSURL *)[userNode value] isMultiplexer] == NO)
            [array addObject:[[userNode value] absoluteString]];
    }
    NSDictionary *plist = [NSDictionary dictionaryWithObject:array forKey:USER_MIRRORS_KEY];
    [plist writeToFile:__TLMUserMirrorsPath() atomically:YES];
}

- (void)_loadDefaultSites
{
    if (_mirrorRoot)
        return;
    
    NSString *sitesFile = [[NSBundle mainBundle] pathForResource:@"CTAN.sites" ofType:@"plist"];
    NSDictionary *sites = [[NSDictionary dictionaryWithContentsOfFile:sitesFile] objectForKey:@"sites"];
    
    [_mirrorRoot autorelease];
    _mirrorRoot = [TLMMirrorNode new];
    
    TLMMirrorNode *customNode = [TLMMirrorNode new];
    [customNode setValue:[NSLocalizedString(@"Other Mirrors", @"mirror group title") uppercaseString]];
    [customNode setType:TLMMirrorNodeContinent];
    [_mirrorRoot addChild:customNode];
    [customNode release];
    
    TLMMirrorNode *multiplexorNode = [TLMMirrorNode new];
    [multiplexorNode setType:TLMMirrorNodeURL];
    [multiplexorNode setValue:__TLMTLNetURL(@"http://mirror.ctan.org/")];
    [customNode addChild:multiplexorNode];
    [multiplexorNode release];
    
    NSDictionary *userPlist = [NSDictionary dictionaryWithContentsOfFile:__TLMUserMirrorsPath()];
    for (NSString *URLString in [userPlist objectForKey:USER_MIRRORS_KEY]) {
        TLMMirrorNode *userNode = [TLMMirrorNode new];
        [userNode setType:TLMMirrorNodeURL];
        [userNode setValue:[NSURL URLWithString:URLString]];
        [[self _customNode] addChild:userNode];
        [userNode release];
    }
    
    for (NSString *continent in sites) {
        
        TLMMirrorNode *continentNode = [TLMMirrorNode new];
        [continentNode setValue:[continent uppercaseString]];
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
                [URLNode setValue:__TLMTLNetURL(URLString)];
                [URLNode setType:TLMMirrorNodeURL];
                [countryNode addChild:URLNode];
                [URLNode release];
            }
                        
        }
        
        for (NSString *countryName in countryNodes)
            [continentNode addChild:[countryNodes objectForKey:countryName]];
        
        [_mirrorRoot addChild:continentNode];
        [continentNode release];
    }    
}

- (void)awakeFromNib
{        
    [_outlineView reloadData];
    [_outlineView registerForDraggedTypes:[NSArray arrayWithObjects:(id)kUTTypeURL, NSURLPboardType, nil]];
    [_outlineView setDoubleAction:@selector(doubleClickAction:)];
    [_outlineView setTarget:self];
}

- (TLMMirrorNode *)_mirrorForURL:(NSURL *)aURL
{
    for (TLMMirrorNode *continentNode in _mirrorRoot) {
        
        for (TLMMirrorNode *countryNode in continentNode) {
            
            for (TLMMirrorNode *URLNode in countryNode) {
                
                NSParameterAssert([URLNode type] == TLMMirrorNodeURL);
                if ([[URLNode value] isEqual:aURL])
                    return URLNode;
            }
        }
    }
    return nil;
}

- (void)_handleVersionCheckNotification:(NSNotification *)aNote
{
    TLMLog(__func__, @"%@", [aNote userInfo]);
    TLMLog(__func__, @"mirror = %@", [self _mirrorForURL:[[aNote userInfo] objectForKey:@"URL"]]);
}

- (void)doubleClickAction:(id)sender
{
    NSInteger row = [_outlineView clickedRow];
    if (row >= 0) {
        TLMMirrorNode *clickedNode = [_outlineView itemAtRow:row];
        if ([clickedNode type] == TLMMirrorNodeURL)
            [[[NSApp delegate] mainWindowController] refreshUpdatedPackageListWithURL:[clickedNode value]];
        else
            NSBeep();
    }
}

- (NSArray *)mirrorsMatchingSearchString:(NSString *)aString;
{
    NSMutableArray *array = [NSMutableArray array];
    for (TLMMirrorNode *continentNode in _mirrorRoot) {
        
        // if the search string is a particular continent, add all of its mirrors
        if ([continentNode type] != TLMMirrorNodeURL && [[continentNode value] caseInsensitiveCompare:aString] == NSOrderedSame) {
            
            for (TLMMirrorNode *countryNode in continentNode) {
                
                for (TLMMirrorNode *URLNode in countryNode) {
                    
                    NSParameterAssert([URLNode type] == TLMMirrorNodeURL);
                    [array addObject:[[URLNode value] absoluteString]];
                }
            }
        }
        else {
        
            for (TLMMirrorNode *countryNode in continentNode) {
                
                // if the search string is a particular country, add all of its mirrors
                if ([countryNode type] != TLMMirrorNodeURL && [[countryNode value] caseInsensitiveCompare:aString] == NSOrderedSame) {
                                         
                    for (TLMMirrorNode *URLNode in countryNode) {
                        
                        NSParameterAssert([URLNode type] == TLMMirrorNodeURL);
                        [array addObject:[[URLNode value] absoluteString]];
                    }
                }
                else {
                
                    // add specific mirrors from any continent
                    for (TLMMirrorNode *URLNode in countryNode) {
                        
                        NSParameterAssert([URLNode type] == TLMMirrorNodeURL);
                        NSString *urlString = [[URLNode value] absoluteString];
                        if ([urlString rangeOfString:aString].length)
                            [array addObject:urlString];
                    }
                }
            }
        }
    }
    return array;
}

#pragma mark NSOutlineView datasource

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)anIndex ofItem:(TLMMirrorNode *)item;
{
    return nil == item ? [_mirrorRoot childAtIndex:anIndex] : [item childAtIndex:anIndex];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(TLMMirrorNode *)item;
{
    return [item numberOfChildren];
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(TLMMirrorNode *)item;
{
    return nil == item ? [_mirrorRoot numberOfChildren] : [item numberOfChildren];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(TLMMirrorNode *)item;
{
    return [item valueForKey:[tableColumn identifier]];
}

static bool __isdefaultserver(TLMMirrorNode *node)
{
    return [node type] == TLMMirrorNodeURL && [[node value] isEqual:[[TLMEnvironment currentEnvironment] defaultServerURL]];
}

- (void)outlineView:(NSOutlineView *)outlineView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn byItem:(TLMMirrorNode *)item;
{
    // could assert these conditions
    if ([_outlineView parentForItem:item] != [self _customNode])
        return NSBeep();
    
    if (__isdefaultserver(item))
        return NSBeep();
    
    if ([item type] == TLMMirrorNodeURL) {
        [item setValue:([object isKindOfClass:[NSURL class]] ? object : [NSURL URLWithString:object])];
        [self performSelector:@selector(_archivePlist) withObject:nil afterDelay:0];
    }
}

#pragma mark NSOutlineView delegate

- (void)outlineView:(TLMOutlineView *)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(TLMMirrorNode *)item;
{
    NSFont *defaultFont = [outlineView defaultFont];
    const bool defaultServer = __isdefaultserver(item);
    
    if (defaultServer) {
        [cell setFont:[NSFont boldSystemFontOfSize:[defaultFont pointSize]]];
    }
    else if (defaultFont) {
        [cell setFont:defaultFont];
    }
    
    if ([_outlineView parentForItem:item] == [self _customNode] && defaultServer == false) {
        [cell setEditable:YES];
        [cell setFormatter:[[TLMURLFormatter new] autorelease]];
    }
    else {
        [cell setEditable:NO];
    }

}

- (NSCell *)outlineView:(NSOutlineView *)outlineView dataCellForTableColumn:(NSTableColumn *)tableColumn item:(TLMMirrorNode *)item
{
    if (nil == tableColumn) return nil;
    return [item type] == TLMMirrorNodeURL ? _mirrorCell : _textFieldCell;
}

- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(TLMMirrorNode *)item
{
    return [item type] == TLMMirrorNodeURL ? 21.0 : 17.0;
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

#pragma mark User interaction

- (BOOL)outlineView:(TLMOutlineView *)outlineView writeItems:(NSArray *)items toPasteboard:(NSPasteboard *)pasteboard;
{
    NSMutableArray *URLs = [NSMutableArray array];
        
    for (TLMMirrorNode *node in items) {
        
        if ([node type] != TLMMirrorNodeURL)
            continue;
        
        [URLs addObject:[node value]];
    }

    return [NSURL writeURLs:URLs toPasteboard:pasteboard];
}

- (void)outlineView:(TLMOutlineView *)outlineView writeSelectedRowsToPasteboard:(NSPasteboard *)pboard;
{
    NSMutableArray *URLs = [NSMutableArray array];
    
    for (TLMMirrorNode *node in [outlineView selectedItems]) {
        
        if ([node type] != TLMMirrorNodeURL)
            continue;
        
        [URLs addObject:[node value]];
    }
    
    if ([NSURL writeURLs:URLs toPasteboard:[NSPasteboard pasteboardWithName:NSGeneralPboard]] == NO)
        NSBeep();
}

- (NSDragOperation)outlineView:(NSOutlineView *)outlineView validateDrop:(id <NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)index;
{
    NSArray *URLs = [NSURL URLsFromPasteboard:[info draggingPasteboard]];
    if ([URLs count] == 0) return NSDragOperationNone;
    // originally checked isFileURL here, but you can have a file: based repo
    return ([item isEqual:[self _customNode]]) ? NSDragOperationCopy : NSDragOperationNone;    
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification;
{
    // only allow removal of custom node children, except for the multiplexer
    NSArray *selectedItems = [_outlineView selectedItems];
    [_addRemoveControl setEnabled:([selectedItems count] > 0) forSegment:1];
    // only allow adding if there's a single selection
    [_addRemoveControl setEnabled:([selectedItems count] == 1) forSegment:0];
    for (id item in selectedItems) {
        if ([_outlineView parentForItem:item] != [self _customNode]) {
            [_addRemoveControl setEnabled:NO forSegment:1];
            [_addRemoveControl setEnabled:NO forSegment:0];
            // may still be able to add if the custom node parent is selected
        }
        else if ([(NSURL *)[item value] isMultiplexer]) {
            [_addRemoveControl setEnabled:NO forSegment:1];
            [_addRemoveControl setEnabled:([selectedItems count] == 1) forSegment:0];
        }
        else if (item == [self _customNode]) {
            [_addRemoveControl setEnabled:([selectedItems count] == 1) forSegment:0];
        }
        else {
            // parent is custom node
            [_addRemoveControl setEnabled:([selectedItems count] == 1) forSegment:0];
        }
    }
}

- (void)_removeSelectedItems
{
    NSArray *selectedItems = [[[_outlineView selectedItems] copy] autorelease];
    for (TLMMirrorNode *node in selectedItems) {
        if ([node type] == TLMMirrorNodeURL)
            [[self _customNode] removeChild:node];
    }
    [_outlineView reloadData];
    [self _archivePlist];
}

- (void)addRemoveAction:(id)sender
{
    switch ([_addRemoveControl selectedSegment]) {
        case 0:
            TLMLog(__func__, @"Should allow add/edit here or something");
            break;
        case 1:
            [self _removeSelectedItems];
            break;
        default:
            break;
    }
}

- (BOOL)outlineView:(NSOutlineView *)outlineView acceptDrop:(id <NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)index;
{
    NSArray *URLs = [NSURL URLsFromPasteboard:[info draggingPasteboard]];
    NSParameterAssert([item isEqual:[self _customNode]]);
    for (NSURL *aURL in URLs) {
        TLMMirrorNode *userNode = [TLMMirrorNode new];
        [userNode setType:TLMMirrorNodeURL];
        [userNode setValue:aURL];
        [[self _customNode] addChild:userNode];
        [userNode release];
    }
    [_outlineView reloadData];
    [self performSelector:@selector(_archivePlist) withObject:nil afterDelay:0];
    return [URLs count] > 0;
}

- (BOOL)control:(NSControl *)control didFailToFormatString:(NSString *)string errorDescription:(NSString *)error
{
    if (control == _outlineView) {
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"Invalid URL", @"alert title")];
        [alert setInformativeText:error];
        [alert beginSheetModalForWindow:[self window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
    }
    return NO;
}

@end
