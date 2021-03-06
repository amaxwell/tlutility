//
//  TLMMirrorController.m
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 11/18/10.
/*
 This software is Copyright (c) 2010-2016
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
#import "TLMPreferenceController.h"
#import "NSStupid.h"

#define MIRRORS_FILENAME @"Mirrors.plist"
#define USER_MIRRORS_KEY @"User mirrors"
#define TLM_MIRROR_REORDER_DRAG_TYPE @"TLM_MIRROR_REORDER_DRAG_TYPE"

@interface TLMMirrorController (Private)
- (void)_loadDefaultSites;
@end

@implementation TLMMirrorController

@synthesize _outlineView;
@synthesize _addRemoveControl;
@synthesize _makeDefaultButton;

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
        _mirrorCell = [[TLMMirrorCell alloc] initTextCell:@""];
        [self _loadDefaultSites];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_handleVersionCheckNotification:)
                                                     name:TLMDatabaseVersionCheckComplete
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_handleRepoChangeNotification:)
                                                     name:TLMDefaultRepositoryChangedNotification
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
    [_addRemoveControl release];
    [_makeDefaultButton release];
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

- (TLMMirrorNode *)_mirrorForURL:(NSURL *)aURL
{
    for (TLMMirrorNode *continentNode in _mirrorRoot) {
                
        for (TLMMirrorNode *countryNode in continentNode) {
                        
            /*
             Unfortunately, the user nodes are direct children of the custom node,
             so we have a special case here in order to pick them up.  All other
             URL nodes need another level of iteration.
             */
            if ([countryNode type] == TLMMirrorNodeCountry) {

                for (TLMMirrorNode *URLNode in countryNode) {
                                        
                    NSParameterAssert([URLNode type] == TLMMirrorNodeURL);
                    if ([[URLNode value] isEqual:aURL])
                        return URLNode;
                }
            }
            else if ([countryNode type] == TLMMirrorNodeURL) {
                
                if ([[countryNode value] isEqual:aURL])
                    return countryNode;
            }

        }
    }
    return nil;
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
    [customNode setValue:[NSLocalizedString(@"My Repositories", @"the user's repository group title") uppercaseString]];
    [customNode setType:TLMMirrorNodeContinent];
    [_mirrorRoot addChild:customNode];
    [customNode release];
    
    TLMMirrorNode *multiplexorNode = [TLMMirrorNode new];
    [multiplexorNode setType:TLMMirrorNodeURL];
    [multiplexorNode setValue:__TLMTLNetURL(@"https://mirror.ctan.org/")];
    [customNode addChild:multiplexorNode];
    [multiplexorNode release];
    
    NSDictionary *userPlist = [NSDictionary dictionaryWithContentsOfFile:__TLMUserMirrorsPath()];
    for (NSString *URLString in [userPlist objectForKey:USER_MIRRORS_KEY]) {
        TLMMirrorNode *userNode = [TLMMirrorNode new];
        [userNode setType:TLMMirrorNodeURL];
        [userNode setValue:[NSURL URLWithString:URLString]];
        // dragging used to create spurious duplicates, with no way to remove the multiplexor in particular
        if ([userNode isEqual:multiplexorNode] == NO)
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
                // ignore rsync URLs since we can't use them
                if ([URLString hasPrefix:@"rsync"] == NO) {
                    TLMMirrorNode *URLNode = [TLMMirrorNode new];
                    [URLNode setValue:__TLMTLNetURL(URLString)];
                    [URLNode setType:TLMMirrorNodeURL];
                    [countryNode addChild:URLNode];
                    [URLNode release];
                }
            }
        }
        
        for (NSString *countryName in countryNodes)
            [continentNode addChild:[countryNodes objectForKey:countryName]];
        
        [_mirrorRoot addChild:continentNode];
        [continentNode release];
    }
    
    /*
     If we upgrade and lose the default server from the plist, add it back in to the 
     custom section so the user can still edit it.
     */
    NSURL *defaultURL = [[TLMEnvironment currentEnvironment] defaultServerURL];
    if (nil == [self _mirrorForURL:defaultURL]) {
        TLMLog(__func__, @"Unable to find default server URL %@.  Adding as custom repository.", defaultURL);
        TLMMirrorNode *userNode = [TLMMirrorNode new];
        [userNode setType:TLMMirrorNodeURL];
        [userNode setValue:defaultURL];
        [[self _customNode] addChild:userNode];
        [userNode release];
        
        // could save it here, but there's no reason to; if the user edits it, it'll be saved anyway
    }
}

- (void)awakeFromNib
{        
    [_outlineView reloadData];
    [_outlineView registerForDraggedTypes:[NSArray arrayWithObjects:TLM_MIRROR_REORDER_DRAG_TYPE, (id)kUTTypeURL, NSURLPboardType, NSStringPboardType, nil]];
    [_outlineView setDraggingSourceOperationMask:NSDragOperationMove | NSDragOperationCopy forLocal:YES];
    [_outlineView setDraggingSourceOperationMask:NSDragOperationCopy forLocal:NO];
    [_outlineView setDoubleAction:@selector(doubleClickAction:)];
    [_outlineView setTarget:self];
}

- (void)_handleVersionCheckNotification:(NSNotification *)aNote
{
    TLMLog(__func__, @"%@", [aNote userInfo]);
    TLMLog(__func__, @"repository = %@", [self _mirrorForURL:[[aNote userInfo] objectForKey:@"URL"]]);
}

- (void)_handleRepoChangeNotification:(NSNotification *)aNote
{
    [_outlineView reloadData];
}

- (void)doubleClickAction:(id)sender
{
    NSInteger row = [_outlineView clickedRow];
    if (row >= 0) {
        TLMMirrorNode *clickedNode = [_outlineView itemAtRow:row];
        if ([clickedNode type] == TLMMirrorNodeURL)
            [[(TLMAppController *)[NSApp delegate] mainWindowController] refreshUpdatedPackageListWithURL:[clickedNode value]];
        else
            NSBeep();
    }
}

- (NSArray *)mirrorsMatchingSearchString:(NSString *)aString;
{
    NSMutableArray *array = [NSMutableArray array];
    for (TLMMirrorNode *continentNode in _mirrorRoot) {
        
        NSParameterAssert([continentNode type] == TLMMirrorNodeContinent);
        
        // if the search string exactly matches a particular continent, add all of its mirrors
        if ([[continentNode value] caseInsensitiveCompare:aString] == NSOrderedSame) {
            
            for (TLMMirrorNode *countryOrURLNode in continentNode) {
                
                // children of the custom node are URL nodes, and have no descendants
                if ([countryOrURLNode type] == TLMMirrorNodeURL) {
                    [array addObject:[[countryOrURLNode value] absoluteString]];
                
                }
                else {
                    
                    // truly a country node
                    for (TLMMirrorNode *URLNode in countryOrURLNode) {
                        
                        NSParameterAssert([URLNode type] == TLMMirrorNodeURL);
                        [array addObject:[[URLNode value] absoluteString]];
                    }
                }
            }
        }
        else {
        
            for (TLMMirrorNode *countryOrURLNode in continentNode) {
                
                // custom node spcial case
                if ([countryOrURLNode type] == TLMMirrorNodeURL) {
                    
                    // add specific mirrors from the custom node, based on substring match
                    NSString *urlString = [[countryOrURLNode value] absoluteString];
                    if ([urlString rangeOfString:aString].length)
                        [array addObject:urlString];
                }
                else {
                    
                    // if the search string exactly matches a particular country, add all of its mirrors
                    if ([[countryOrURLNode value] caseInsensitiveCompare:aString] == NSOrderedSame) {
                        
                        for (TLMMirrorNode *URLNode in countryOrURLNode) {
                            
                            NSParameterAssert([URLNode type] == TLMMirrorNodeURL);
                            [array addObject:[[URLNode value] absoluteString]];
                        }
                    }
                    else {
                        
                        // descend and add specific mirrors from any continent based on substring match
                        for (TLMMirrorNode *URLNode in countryOrURLNode) {
                            
                            NSParameterAssert([URLNode type] == TLMMirrorNodeURL);
                            NSString *urlString = [[URLNode value] absoluteString];
                            if ([urlString rangeOfString:aString].length)
                                [array addObject:urlString];
                        }
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

static bool __ismultiplexer(TLMMirrorNode *node)
{
    return [node type] == TLMMirrorNodeURL && [[node value] isMultiplexer];
}

- (void)outlineView:(NSOutlineView *)outlineView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn byItem:(TLMMirrorNode *)item;
{
    // could assert these conditions
    if ([_outlineView parentForItem:item] != [self _customNode])
        return NSBeep();
    
    if (__ismultiplexer(item))
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
    
    if (__isdefaultserver(item)) {
        [cell setFont:[NSFont boldSystemFontOfSize:[defaultFont pointSize]]];
    }
    else if (defaultFont) {
        [cell setFont:defaultFont];
    }
    
    if ([_outlineView parentForItem:item] == [self _customNode] && __ismultiplexer(item) == false) {
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
    return [item type] == TLMMirrorNodeURL ? _mirrorCell : [tableColumn dataCell];
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

static NSIndexSet *__reorderIndexSetFromPasteboard(NSPasteboard *pboard)
{
    OSStatus err;
    
    PasteboardRef carbonPboard;
    err = PasteboardCreate((CFStringRef)[pboard name], &carbonPboard);
    
    if (noErr == err)
        (void)PasteboardSynchronize(carbonPboard);
    
    ItemCount itemCount, itemIndex;
    if (noErr == err)
        err = PasteboardGetItemCount(carbonPboard, &itemCount);
    
    if (noErr != err)
        itemCount = 0;
    
    NSIndexSet *toReturn = nil;
    
    // Pasteboard has 1-based indexing!
    
    for (itemIndex = 1; itemIndex <= itemCount; itemIndex++) {
        
        PasteboardItemID itemID;
        CFArrayRef flavors = NULL;
        CFIndex flavorIndex, flavorCount = 0;
        
        err = PasteboardGetItemIdentifier(carbonPboard, itemIndex, &itemID);
        if (noErr == err)
            err = PasteboardCopyItemFlavors(carbonPboard, itemID, &flavors);
        
        if (noErr == err)
            flavorCount = CFArrayGetCount(flavors);
        
        // flavorCount will be zero in case of an error...
        for (flavorIndex = 0; flavorIndex < flavorCount; flavorIndex++) {
            
            CFStringRef flavor;
            CFDataRef data;
            
            flavor = CFArrayGetValueAtIndex(flavors, flavorIndex);
            
            if (UTTypeEqual(flavor, (CFStringRef)TLM_MIRROR_REORDER_DRAG_TYPE)) {
                
                err = PasteboardCopyItemFlavorData(carbonPboard, itemID, flavor, &data);
                if (noErr == err && NULL != data) {
                    toReturn = [NSUnarchiver unarchiveObjectWithData:(NSData *)data];
                    CFRelease(data);
                }
                
            }
            // ignore any other type; we don't care
            
        }
        
        if (NULL != flavors)
            CFRelease(flavors);
    }
    
    if (carbonPboard) CFRelease(carbonPboard);
    NSLog(@"index set from pboard: %@", toReturn);
    
    return toReturn;
}

// for drag operations
- (BOOL)outlineView:(TLMOutlineView *)outlineView writeItems:(NSArray *)items toPasteboard:(NSPasteboard *)pasteboard;
{
    NSMutableArray *URLs = [NSMutableArray array];
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    
    for (TLMMirrorNode *node in items) {
        
        if ([node type] != TLMMirrorNodeURL)
            continue;
        
        [URLs addObject:[node value]];
        [indexes addIndex:[_outlineView rowForItem:node]];
    }
    
    // clears the pboard and keeps our NS methods from writing to it, so I have to use
    // all of the Carbon pasteboard shit here
    // !!! early return
    if ([NSURL writeURLs:URLs toPasteboard:pasteboard])
        return NO;
    
    OSStatus err;
    PasteboardRef carbonPboard;
    err = PasteboardCreate((CFStringRef)[pasteboard name], &carbonPboard);
    
    if (noErr == err)
        (void)PasteboardSynchronize(carbonPboard);
    
    if (noErr != err) {
        TLMLog(__func__, @"failed to setup pboard %@: %s", [pasteboard name], TLMGetMacOSStatusErrorString(err));
        return NO;
    }
    
    CFDataRef utf8Data = (CFDataRef)[NSArchiver archivedDataWithRootObject:indexes];
    
    // any pointer type; private to the creating application
    PasteboardItemID itemID = (void *)TLM_MIRROR_REORDER_DRAG_TYPE;
    err = PasteboardPutItemFlavor(carbonPboard, itemID, (CFStringRef)TLM_MIRROR_REORDER_DRAG_TYPE, utf8Data, kPasteboardFlavorNoFlags);
    
    if (noErr != err)
        TLMLog(__func__, @"failed to write to pboard %@: %s", [pasteboard name], TLMGetMacOSStatusErrorString(err));
    
    ItemCount itemCount;
    err = PasteboardGetItemCount(carbonPboard, &itemCount);
    
    if (carbonPboard)
        CFRelease(carbonPboard);
    
    return noErr == err && itemCount > 0;

}

// for cmd-c copy support
- (void)outlineView:(TLMOutlineView *)outlineView writeSelectedRowsToPasteboard:(NSPasteboard *)pboard;
{
    NSMutableArray *URLs = [NSMutableArray array];
    
    for (TLMMirrorNode *node in [outlineView selectedItems]) {
        
        if ([node type] != TLMMirrorNodeURL)
            continue;
        
        [URLs addObject:[node value]];
    }
    
    if ([URLs count] == 0 || [NSURL writeURLs:URLs toPasteboard:[NSPasteboard pasteboardWithName:NSGeneralPboard]] == NO)
        NSBeep();
}

- (NSDragOperation)outlineView:(NSOutlineView *)outlineView validateDrop:(id <NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)idx;
{
    if ([item isEqual:[self _customNode]] == NO) return NSDragOperationNone;
    
    // fixme: if it's a local drag, assume it's reordering; should probably test for option-key to copy
    if ([[[info draggingPasteboard] types] containsObject:TLM_MIRROR_REORDER_DRAG_TYPE]) return NSDragOperationMove;
    
    NSArray *URLs = [NSURL URLsFromPasteboard:[info draggingPasteboard]];
    if ([URLs count] == 0) return NSDragOperationNone;
    // originally checked isFileURL here, but you can have a file: based repo
    return NSDragOperationCopy;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView acceptDrop:(id <NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)idx;
{
    NSParameterAssert([item isEqual:[self _customNode]]);
    NSArray *URLs = [NSURL URLsFromPasteboard:[info draggingPasteboard]];
    
    // may be external drag, in which case we're not going to be removing
    NSMutableArray *childrenToRemove = [NSMutableArray array];
    if ([[[info draggingPasteboard] types] containsObject:TLM_MIRROR_REORDER_DRAG_TYPE]) {
        
        NSIndexSet *sourceIndexes = __reorderIndexSetFromPasteboard([info draggingPasteboard]);
        NSUInteger ridx = [sourceIndexes firstIndex];
        
        // indexes are based off outline view, not child indexes
        while (NSNotFound != ridx) {
            [childrenToRemove addObject:[_outlineView itemAtRow:ridx]];
            ridx = [sourceIndexes indexGreaterThanIndex:ridx];
        }
    }
    
    for (NSURL *aURL in URLs) {
        TLMMirrorNode *userNode = [TLMMirrorNode new];
        [userNode setType:TLMMirrorNodeURL];
        [userNode setValue:aURL];
        // either NSDragOperationMove or NSDragOperationCopy, and we handle both the same way
        [[self _customNode] insertChild:userNode atIndex:idx];
        [userNode release];
    }
    
    for (TLMMirrorNode *toRemove in childrenToRemove) {
        [[self _customNode] removeChildIdenticalTo:toRemove];
    }
    
    [_outlineView reloadData];
    [self performSelector:@selector(_archivePlist) withObject:nil afterDelay:0];
    return [URLs count] > 0;
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
        else if ([(NSURL *)[(TLMMirrorNode *)item value] isMultiplexer]) {
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
    
    // allow even if already default
    [_makeDefaultButton setEnabled:([selectedItems count] == 1)];
}

- (void)_removeSelectedItems
{
    NSArray *selectedItems = [[[_outlineView selectedItems] copy] autorelease];
    for (TLMMirrorNode *node in selectedItems) {
        if ([node type] == TLMMirrorNodeURL)
            [[self _customNode] removeChildIdenticalTo:node];
    }
    [_outlineView reloadData];
    [self _archivePlist];
}

- (void)_copySelectedRows:(id)sender
{
    [self outlineView:_outlineView writeSelectedRowsToPasteboard:[NSPasteboard generalPasteboard]];
}

- (void)_makeSelectedMirrorDefault:(id)sender
{
    NSArray *selectedItems = [_outlineView selectedItems];
    if ([selectedItems count] == 1 && [(TLMMirrorNode *)[selectedItems lastObject] type] == TLMMirrorNodeURL) {
        NSURL *newDefault = [(TLMMirrorNode *)[selectedItems lastObject] value];
        [TLMEnvironment setDefaultRepository:newDefault];
        /*
         Users expect a button titled "Use As Home" to change the current mirror, too,
         which seems reasonable.  However, this action can be called for the current
         mirror, and we don't want to do a spurious reload in that case.
         */
        if ([[[(TLMAppController *)[NSApp delegate] mainWindowController] serverURL] isEqual:newDefault] == NO)
            [[(TLMAppController *)[NSApp delegate] mainWindowController] refreshUpdatedPackageListWithURL:newDefault];
        // notification handler should take care of UI updates for mirror window
    }
    else {
        NSBeep();
    }
}

- (void)changeDefaultMirror:(id)sender
{
    [self _makeSelectedMirrorDefault:sender];
}

- (BOOL)windowShouldClose:(id)sender { return [[self window] makeFirstResponder:nil]; }

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem;
{
    SEL action = [anItem action];
    if (@selector(changeDefaultMirror:) == action || @selector(_makeSelectedMirrorDefault:) == action) {
        NSArray *selectedItems = [_outlineView selectedItems];
        return ([selectedItems count] == 1 && [(TLMMirrorNode *)[selectedItems lastObject] type] == TLMMirrorNodeURL);
    }
    else if (@selector(_copySelectedRows:) == action)
        return [_outlineView numberOfSelectedRows] > 0;
    else
        return YES;
}

- (NSMenu *)tableView:(NSTableView *)tableView contextMenuForRow:(NSInteger)row column:(NSInteger)column;
{
    NSZone *zone = [NSMenu menuZone];
    NSMenu *menu = [[NSMenu allocWithZone:zone] init];
    
    NSMenuItem *item = [[NSMenuItem allocWithZone:zone] initWithTitle:NSLocalizedString(@"Copy", @"context menu")
                                                               action:@selector(_copySelectedRows:)
                                                        keyEquivalent:@""];
    [item setAction:@selector(_copySelectedRows:)];
    [item setTarget:self];
    [menu addItem:item];
    [item release];
    
    item = [[NSMenuItem allocWithZone:zone] initWithTitle:NSLocalizedString(@"Set Default Repository", @"context menu")
                                                   action:@selector(_makeSelectedMirrorDefault:)
                                            keyEquivalent:@""];
    [item setAction:@selector(_makeSelectedMirrorDefault:)];
    [item setTarget:self];
    [menu addItem:item];
    [item release];
    
    return [menu autorelease];
}

- (void)addRemoveAction:(id)sender
{
    switch ([_addRemoveControl selectedSegment]) {
        case 0:
        {
            TLMMirrorNode *child = [[TLMMirrorNode new] autorelease];
            [child setType:TLMMirrorNodeURL];
            [child setValue:[NSURL URLWithString:@"https://"]];
            [[self _customNode] addChild:child];
            [_outlineView reloadData];
            [_outlineView expandItem:[self _customNode]];
            [_outlineView editColumn:0 row:[_outlineView rowForItem:child] withEvent:nil select:YES];
            break;
        }
        case 1:
            [self _removeSelectedItems];
            break;
        default:
            break;
    }
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
