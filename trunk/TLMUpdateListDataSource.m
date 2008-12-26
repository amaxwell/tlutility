//
//  TLMUpdateListDataSource.m
//  TeX Live Manager
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

#import "TLMUpdateListDataSource.h"
#import "TLMPackage.h"
#import "TLMMainWindowController.h"
#import "TLMInfoController.h"
#import "TLMLogServer.h"
#import "TLMTableView.h"

@implementation TLMUpdateListDataSource

@synthesize tableView = _tableView;
@synthesize _searchField;
@synthesize allPackages = _allPackages;
@synthesize _controller;

- (id)init
{
    self = [super init];
    if (self) {
        _packages = [NSMutableArray new];
        _sortDescriptors = [NSMutableArray new];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_tableView setDelegate:nil];
    [_tableView setDataSource:nil];
    [_tableView release];
    [_searchField release];
    [_packages release];
    [_allPackages release];
    [_sortDescriptors release];
    
    [super dealloc];
}

- (void)awakeFromNib
{
    [_tableView setFontNamePreferenceKey:@"TLMUpdateListTableFontName" 
                       sizePreferenceKey:@"TLMUpdateListTableFontSize"];
    
    // force this column to be displayed (only used with tlmgr2)
    [[_tableView tableColumnWithIdentifier:@"size"] setHidden:NO];
}

- (void)setAllPackages:(NSArray *)packages
{
    [_allPackages autorelease];
    _allPackages = [packages copy];
    [self search:nil];
}
   
- (BOOL)_validateInstallSelectedRow
{
    // require update all, for consistency with the dialog
    if ([_controller infrastructureNeedsUpdate])
        return NO;
    
    if ([_packages count] == 0)
        return NO;
    
    // tlmgr does nothing in this case, so it's less clear what to do in case of multiple selection
    if ([[_tableView selectedRowIndexes] count] == 1 && [[_packages objectAtIndex:[_tableView selectedRow]] willBeRemoved])
        return NO;
    
    // for multiple selection, just install and let tlmgr deal with any willBeRemoved packages
    return [[_tableView selectedRowIndexes] count] > 0;
}

// tried validating toolbar items using bindings to queue.operations.@count but the queue sends KVO notifications on its own thread
- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem;
{
    SEL action = [anItem action];
    if (@selector(showInfo:) == action)
        return [[[TLMInfoController sharedInstance] window] isVisible] == NO;
    else if (@selector(removeSelectedRow:) == action)
        return [[_tableView selectedRowIndexes] count] > 0;
    else if (@selector(listUpdates:) == action)
        return YES;// FIXME: [[_queue operations] count] == 0;
    else if (@selector(installSelectedRow:) == action)
        return [self _validateInstallSelectedRow];
    else
        return YES;
}

- (IBAction)search:(id)sender;
{
    NSString *searchString = [_searchField stringValue];
    
    if (nil == searchString || [searchString isEqualToString:@""]) {
        [_packages setArray:_allPackages];
    }
    else {
        [_packages removeAllObjects];
        for (TLMPackage *pkg in _allPackages) {
            if ([pkg matchesSearchString:searchString])
                [_packages addObject:pkg];
        }
    }
    [_packages sortUsingDescriptors:_sortDescriptors];
    [_tableView reloadData];
}

// TODO: should this be a toggle to show/hide?
- (IBAction)showInfo:(id)sender;
{
    if ([_tableView selectedRow] != -1)
        [[TLMInfoController sharedInstance] showInfoForPackage:[_packages objectAtIndex:[_tableView selectedRow]]];
    else if ([[[TLMInfoController sharedInstance] window] isVisible] == NO) {
        [[TLMInfoController sharedInstance] showInfoForPackage:nil];
        [[TLMInfoController sharedInstance] showWindow:nil];
    }
}

- (IBAction)removeSelectedRow:(id)sender;
{
    TLMLog(nil, @"removeSelectedRow: is not implemented");
}

// both datasources implement this method
- (IBAction)listUpdates:(id)sender;
{
    [_controller refreshUpdatedPackageList];
}

- (IBAction)installSelectedRow:(id)sender;
{
    
    if ([[_tableView selectedRowIndexes] count] == [_packages count]) {
        [_controller updateAll:nil];
    }
    else {
        NSArray *packageNames = [[_packages valueForKey:@"name"] objectsAtIndexes:[_tableView selectedRowIndexes]];
        [_controller installPackagesWithNames:packageNames];
    }
}

# pragma mark table datasource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView;
{
    return [_packages count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row;
{
    return [[_packages objectAtIndex:row] valueForKey:[tableColumn identifier]];
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row;
{
    TLMPackage *package = [_packages objectAtIndex:row];
    if ([package failedToParse])
        [cell setTextColor:[NSColor redColor]];
    else if ([package willBeRemoved])
        [cell setTextColor:[NSColor grayColor]];
    else if ([package currentlyInstalled] == NO)
        [cell setTextColor:[NSColor blueColor]];
    else
        [cell setTextColor:[NSColor blackColor]];
}

- (void)tableView:(NSTableView *)tableView didClickTableColumn:(NSTableColumn *)tableColumn
{
    _sortAscending = !_sortAscending;
    
    for (NSTableColumn *col in [_tableView tableColumns])
        [_tableView setIndicatorImage:nil inTableColumn:col];
    NSImage *image = _sortAscending ? [NSImage imageNamed:@"NSAscendingSortIndicator"] : [NSImage imageNamed:@"NSDescendingSortIndicator"];
    [_tableView setIndicatorImage:image inTableColumn:tableColumn];
    
    NSString *key = [tableColumn identifier];
    NSSortDescriptor *sort = nil;
    if ([key isEqualToString:@"remoteVersion"] || [key isEqualToString:@"localVersion"] || [key isEqualToString:@"size"]) {
        sort = [[NSSortDescriptor alloc] initWithKey:key ascending:_sortAscending];
    }
    else if ([key isEqualToString:@"name"] || [key isEqualToString:@"status"]) {
        sort = [[NSSortDescriptor alloc] initWithKey:key ascending:_sortAscending selector:@selector(localizedCaseInsensitiveCompare:)];
    }
    else {
        TLMLog(nil, @"Unhandled sort key %@", key);
    }
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
    while ([_sortDescriptors count] > [tableView numberOfColumns])
        [_sortDescriptors removeLastObject];
    
    [_packages sortUsingDescriptors:_sortDescriptors];
    [_tableView reloadData];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification;
{
    if ([[[TLMInfoController sharedInstance] window] isVisible]) {
        // reset for multiple selection or empty selection
        if ([_tableView numberOfSelectedRows] != 1)
            [[TLMInfoController sharedInstance] showInfoForPackage:nil];
        else
            [self showInfo:nil];
    }
}
    
@end
