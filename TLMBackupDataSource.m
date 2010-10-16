//
//  TLMBackupDataSource.m
//  TeX Live Manager
//
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

#import "TLMBackupDataSource.h"
#import "TLMBackupNode.h"
#import "TLMInfoController.h"
#import "TLMLogServer.h"
#import "TLMBackupCell.h"

@implementation TLMBackupDataSource

@synthesize outlineView = _outlineView;
@synthesize _controller;
@synthesize statusWindow = _statusWindow;
@synthesize lastUpdateURL = _lastUpdateURL;
@synthesize backupNodes = _backupNodes;
@synthesize _searchField;
@synthesize refreshing = _refreshing;

- (id)init
{
    self = [super init];
    if (self) {
        _displayedBackupNodes = [NSMutableArray new];
        _sortDescriptors = [NSMutableArray new];
    }
    return self;
}

- (void)dealloc
{
    _controller = nil;
    [_outlineView setDelegate:nil];
    [_outlineView setDataSource:nil];
    [_outlineView release];
    [_backupNodes release];
    [_displayedBackupNodes release];
    [_searchField release];
    [_sortDescriptors release];
    [_lastUpdateURL release];
    [_statusWindow release];
    [super dealloc];
}

- (void)awakeFromNib
{
    [_outlineView setFontNamePreferenceKey:@"TLMBackupListTableFontName" 
                         sizePreferenceKey:@"TLMBackupListTableFontSize"];
}

- (void)setBackupNodes:(NSArray *)nodes
{
    [_backupNodes autorelease];
    _backupNodes = [nodes copy];
    [self search:nil];
}

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem;
{
    SEL action = [anItem action];
    if (@selector(showInfo:) == action)
        return [[[TLMInfoController sharedInstance] window] isVisible] == NO;
    else if (@selector(refreshList:) == action)
        return NO == _refreshing;
    else
        return YES;
}

- (IBAction)search:(id)sender;
{
    NSString *searchString = [_searchField stringValue];
    NSArray *selectedItems = [_outlineView selectedItems];
    
    if (nil == searchString || [searchString isEqualToString:@""]) {
        [_displayedBackupNodes setArray:_backupNodes];
    }
    else {
        [_displayedBackupNodes removeAllObjects];
        for (TLMBackupNode *node in _backupNodes) {
            if ([node matchesSearchString:searchString])
                [_displayedBackupNodes addObject:node];
        }
    }
    [_displayedBackupNodes sortUsingDescriptors:_sortDescriptors];    
    [_outlineView reloadData];
    
    // restore previously selected packages, if possible
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    for (id item in selectedItems) {
        NSInteger idx = [_outlineView rowForItem:item];
        if (-1 != idx)
            [indexes addIndex:idx];
    }
    [_outlineView selectRowIndexes:indexes byExtendingSelection:NO];    
}

- (id)selectedItem
{
    id selectedItem = nil;
    if ([_outlineView selectedRow] != -1) {
        selectedItem = [_outlineView itemAtRow:[_outlineView selectedRow]];
        if ([_outlineView parentForItem:selectedItem])
            selectedItem = [_outlineView parentForItem:selectedItem];
    }
    return selectedItem;
}

- (IBAction)showInfo:(id)sender;
{
    if ([self selectedItem] != nil)
        [[TLMInfoController sharedInstance] showInfoForPackage:[self selectedItem] location:[self lastUpdateURL]];
    else if ([[[TLMInfoController sharedInstance] window] isVisible] == NO) {
        [[TLMInfoController sharedInstance] showInfoForPackage:nil location:[self lastUpdateURL]];
        [[TLMInfoController sharedInstance] showWindow:nil];
    }
}

- (IBAction)refreshList:(id)sender;
{
    [_controller refreshBackupList];
}

static inline BOOL __TLMIsBackupNode(id obj)
{
    return [obj isKindOfClass:[TLMBackupNode class]];
}

- (void)restoreAction:(id)sender
{
    NSNumber *version = [_outlineView itemAtRow:[_outlineView clickedRow]];
    NSString *name = [[_outlineView parentForItem:version] name];
    [_controller restorePackage:name version:version];
}

#pragma mark NSOutlineView datasource

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)anIndex ofItem:(TLMBackupNode *)item;
{
    return (nil == item) ? [_displayedBackupNodes objectAtIndex:anIndex] : [item versionAtIndex:anIndex];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(TLMBackupNode *)item;
{
    return __TLMIsBackupNode(item);
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(TLMBackupNode *)item;
{
    return (nil == item) ? [_displayedBackupNodes count] : (__TLMIsBackupNode(item) ? [item numberOfVersions] : 0);
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item;
{
    return __TLMIsBackupNode(item) ? [item name] : item;
}

#pragma mark NSOutlineView delegate

- (NSCell *)outlineView:(NSOutlineView *)outlineView dataCellForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    id cell = [tableColumn dataCellForRow:[outlineView rowForItem:item]];
    if (cell && __TLMIsBackupNode(item) == NO && tableColumn) {
        TLMBackupCell *backupCell = [[[TLMBackupCell alloc] initTextCell:@""] autorelease];
        [backupCell setTarget:self];
        [backupCell setAction:@selector(restoreAction:)];
        [backupCell setFont:[outlineView font]];
        [backupCell setBackgroundStyle:[cell backgroundStyle]];
        [backupCell setLineBreakMode:[cell lineBreakMode]];
        [backupCell setWraps:[cell wraps]];
        [backupCell setAlignment:[cell alignment]];
        [backupCell setScrollable:[cell isScrollable]];
        [backupCell setControlSize:[cell controlSize]];
        [backupCell setTruncatesLastVisibleLine:[cell truncatesLastVisibleLine]];
        cell = backupCell;
    }
    return cell;
}

- (void)outlineView:(NSOutlineView *)outlineView didClickTableColumn:(NSTableColumn *)tableColumn;
{
    /*
     Copied from TLMPackageListDataSource, and is currently overkill since we
     only have a single table column here.
     */
    _sortAscending = !_sortAscending;
    
    for (NSTableColumn *col in [outlineView tableColumns])
        [outlineView setIndicatorImage:nil inTableColumn:col];
    NSImage *image = _sortAscending ? [NSImage imageNamed:@"NSAscendingSortIndicator"] : [NSImage imageNamed:@"NSDescendingSortIndicator"];
    [outlineView setIndicatorImage:image inTableColumn:tableColumn];
    
    NSString *key = [tableColumn identifier];
    NSSortDescriptor *sort = nil;
    
    // all string keys, so do a simple comparison
    sort = [[NSSortDescriptor alloc] initWithKey:key ascending:_sortAscending selector:@selector(localizedCaseInsensitiveCompare:)];
    [sort autorelease];
    
    // make sure we're not duplicating any descriptors (possibly with reversed order)
    NSUInteger cnt = [_sortDescriptors count];
    while (cnt--) {
        if ([[[_sortDescriptors objectAtIndex:cnt] key] isEqualToString:key])
            [_sortDescriptors removeObjectAtIndex:cnt];
    }
    
    // push the new sort descriptor, which is correctly ascending/descending
    if (sort) [_sortDescriptors insertObject:sort atIndex:0];
    
    // pop the last sort descriptor, if we have more sort descriptors than table columns
    while ((NSInteger)[_sortDescriptors count] > [outlineView numberOfColumns])
        [_sortDescriptors removeLastObject];
    
    [_displayedBackupNodes sortUsingDescriptors:_sortDescriptors];
    [outlineView reloadData];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification;
{
    if ([[[TLMInfoController sharedInstance] window] isVisible]) {
        // reset for multiple selection or empty selection
        if ([_outlineView numberOfSelectedRows] != 1)
            [[TLMInfoController sharedInstance] showInfoForPackage:nil location:[self lastUpdateURL]];
        else
            [self showInfo:nil];
    }
    
    // toolbar updating is somewhat erratic, so force it to validate here
    [[[_controller window] toolbar] validateVisibleItems];
}

@end
