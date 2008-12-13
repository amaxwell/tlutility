//
//  TLMMainWindowController.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/6/08.
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

#import "TLMMainWindowController.h"
#import "TLMPackage.h"
#import "TLMListUpdatesOperation.h"
#import "TLMUpdateOperation.h"
#import "TLMSplitView.h"
#import "TLMInfoController.h"
#import "TLMLogUtilities.h"
#import "TLMASLStore.h"

static char _TLMOperationQueueOperationContext;

@implementation TLMMainWindowController

@synthesize _tableView, _progressIndicator, _hostnameField, _splitView, _logDataSource;


- (id)init
{
    return [self initWithWindowNibName:[self windowNibName]];
}

- (id)initWithWindowNibName:(NSString *)windowNibName
{
    self = [super initWithWindowNibName:windowNibName];
    if (self) {
        _packages = [NSMutableArray new];
        _queue = [NSOperationQueue new];
        [_queue setMaxConcurrentOperationCount:1];
        [_queue addObserver:self forKeyPath:@"operations" options:0 context:&_TLMOperationQueueOperationContext];
        _lastTextViewHeight = 0.0;
        _updateInfrastructure = NO;
    }
    return self;
}

- (void)dealloc
{
    [_queue removeObserver:self forKeyPath:@"operations"];
    [_queue cancelAllOperations];
    [_queue waitUntilAllOperationsAreFinished];
    [_queue release];
    
    [_tableView setDelegate:nil];
    [_tableView setDataSource:nil];
    [_tableView release];
    
    [_splitView setDelegate:nil];
    [_splitView release];
    
    [_packages release];
    [_progressIndicator release];
    [_logDataSource release];
    
    [super dealloc];
}

- (void)awakeFromNib
{
    [[self window] setTitle:[[NSBundle mainBundle] objectForInfoDictionaryKey:(id)kCFBundleNameKey]];
    [_hostnameField setStringValue:@""];
        
    // may as well populate the list immediately
    [self listUpdates:nil];
}

- (NSString *)windowNibName { return @"MainWindow"; }

- (void)_operationCountChanged
{
    NSParameterAssert([NSThread isMainThread]);
    if ([[_queue operations] count]) {
        [_progressIndicator startAnimation:nil];
    }
    else {
        [_progressIndicator stopAnimation:nil];
    }
}

// NB: this will arrive on the queue's thread, at least under some conditions!
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == &_TLMOperationQueueOperationContext) {
        [self performSelectorOnMainThread:@selector(_operationCountChanged) withObject:nil waitUntilDone:NO];
        if ([[_queue operations] count]) {
            [_logDataSource performSelectorOnMainThread:@selector(startUpdates) withObject:nil waitUntilDone:NO];
        }
        else {
            [_logDataSource performSelectorOnMainThread:@selector(stopUpdates) withObject:nil waitUntilDone:NO];
        }
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)_handleListUpdatesFinishedNotification:(NSNotification *)aNote
{
    NSParameterAssert([NSThread isMainThread]);
    TLMListUpdatesOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];

    // Karl sez these are the packages that the next version of tlmgr will require you to install before installing anything else
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"name IN { 'bin-texlive', 'texlive.infra' }"];
    NSArray *packages = [[op packages] filteredArrayUsingPredicate:predicate];
    
    if ([packages count]) {
        // log for debugging, then display an alert so the user has some idea of what's going on...
        // FIXME: display in table
        // [self _appendLine:[NSString stringWithFormat:@"Critical updates detected: %@", [packages valueForKey:@"name"]] color:[NSColor redColor]];
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"Critical Updates Available", @"")];
        [alert setAlertStyle:NSCriticalAlertStyle];
        [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"%d packages are available for update, but the TeX Live installer packages listed here must be updated first.", @""), [[op packages] count]]];
        [alert beginSheetModalForWindow:[self window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
        _updateInfrastructure = YES;
    }
    else {
        _updateInfrastructure = NO;
        packages = [op packages];
    }
    
    [_packages setArray:packages];
    [_tableView reloadData];
    
    // FIXME: this doesn't work correctly (only changes font when the text field is made responder?)
    if ([op updateURL]) {
        NSMutableAttributedString *attrString = [[NSMutableAttributedString alloc] initWithString:[[op updateURL] absoluteString]];
        [attrString addAttribute:NSLinkAttributeName value:[op updateURL] range:NSMakeRange(0, [attrString length])];
        [_hostnameField setAttributedStringValue:attrString];
        [attrString release];
    }
}

- (void)_handleInstallFinishedNotification:(NSNotification *)aNote
{
    NSParameterAssert([NSThread isMainThread]);
    TLMUpdateOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    
    // ignore operations that failed or were explicitly cancelled
    if ([op isCancelled] == NO) {
        // This is slow, but if infrastructure was updated or a package installed other dependencies, we have no way of manually removing from the list.
        // FIXME: need to ensure the same mirror is used for this!
        [self listUpdates:nil];
    }
}

// FIXME: add a property to operations instead of checking class
- (BOOL)_installIsRunning
{
    NSArray *ops = [[[_queue operations] copy] autorelease];
    for (id op in ops) {
        if ([op isKindOfClass:[TLMUpdateOperation class]])
            return YES;
    }
    return NO;
}

- (BOOL)_validateInstallSelectedRow
{
    if ([_packages count] == 0)
        return NO;
    
    // pushing multiple operations into the queue could work, but users will get impatient and click the button multiple times
    if ([[_queue operations] count] > 0)
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
    if (@selector(cancelAllOperations:) == action)
        return [[_queue operations] count] && [self _installIsRunning] == NO; // cancel doesn't work with install operations
    else if (@selector(showInfo:) == action)
        return [[[TLMInfoController sharedInstance] window] isVisible] == NO;
    else if (@selector(removeSelectedRow:) == action)
        return [[_tableView selectedRowIndexes] count] > 0;
    else if (@selector(listUpdates:) == action)
        return [[_queue operations] count] == 0;
    else if (@selector(installSelectedRow:) == action)
        return [self _validateInstallSelectedRow];
    else if (@selector(updateAll:) == action)
        return [[_queue operations] count] == 0 && [_packages count];
    else
        return YES;
}

- (IBAction)cancelAllOperations:(id)sender;
{
    [_queue cancelAllOperations];
}

// TODO: should this be a toggle to show/hide?
- (IBAction)showInfo:(id)sender;
{
    if ([_tableView selectedRow] != -1 && [_tableView selectedRow] < [_packages count])
        [[TLMInfoController sharedInstance] showInfoForPackage:[_packages objectAtIndex:[_tableView selectedRow]]];
    else if ([[[TLMInfoController sharedInstance] window] isVisible] == NO) {
        [[TLMInfoController sharedInstance] showInfoForPackage:nil];
        [[TLMInfoController sharedInstance] showWindow:nil];
    }
}

- (IBAction)removeSelectedRow:(id)sender;
{
    // FIXME: [self _appendLine:@"removeSelectedRow: is not implemented" color:[NSColor greenColor]];
}

- (IBAction)listUpdates:(id)sender;
{
    TLMListUpdatesOperation *op = [TLMListUpdatesOperation new];
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(_handleListUpdatesFinishedNotification:) 
                                                 name:TLMOperationFinishedNotification 
                                               object:op];
    [_queue addOperation:op];
    [op release];
}

- (void)updateAllAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;
{
    if (NSAlertFirstButtonReturn == returnCode) {
        NSArray *packageNames = nil;
        // force an install of only these packages, since old versions of tlmgr may not do that
        if (_updateInfrastructure)
            packageNames = [NSArray arrayWithObjects:@"bin-texlive", @"texlive.infra", nil];
        TLMUpdateOperation *op = [[TLMUpdateOperation alloc] initWithPackageNames:packageNames];
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(_handleInstallFinishedNotification:) 
                                                     name:TLMOperationFinishedNotification 
                                                   object:op];
        [_queue addOperation:op];
        [op release];    
    }    
}

- (IBAction)updateAll:(id)sender;
{
    NSAlert *alert = [[NSAlert new] autorelease];
    [alert setMessageText:NSLocalizedString(@"Update All Packages?", @"")];
    // may not be correct for _updateInfrastructure, but tlmgr may remove stuff also...so leave it as-is
    [alert setInformativeText:NSLocalizedString(@"This will install all available updates and remove packages that no longer exist on the server.", @"")];
    [alert addButtonWithTitle:NSLocalizedString(@"Update", @"")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
    [alert beginSheetModalForWindow:[self window] modalDelegate:self didEndSelector:@selector(updateAllAlertDidEnd:returnCode:contextInfo:) contextInfo:NULL]; 
}    

- (BOOL)windowShouldClose:(id)sender;
{
    BOOL shouldClose = YES;
    if ([self _installIsRunning]) {
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"Installation In Progress!", @"")];
        [alert setAlertStyle:NSCriticalAlertStyle];
        [alert setInformativeText:NSLocalizedString(@"If you close the window, the installation process may leave your TeX installation in an unknown state.  You can ignore this warning or wait until the installation finishes.", @"")];
        [alert addButtonWithTitle:NSLocalizedString(@"Wait", @"")];
        [alert addButtonWithTitle:NSLocalizedString(@"Ignore", @"")];
        
        NSInteger rv = [alert runModal];
        if (NSAlertFirstButtonReturn == rv)
            shouldClose = NO;
    }
    return shouldClose;
}

- (IBAction)installSelectedRow:(id)sender;
{
    if ([[_tableView selectedRowIndexes] count] == [_packages count]) {
        [self updateAll:nil];
    }
    else {
        NSArray *packageNames = [[_packages valueForKey:@"name"] objectsAtIndexes:[_tableView selectedRowIndexes]];
        TLMUpdateOperation *op = [[TLMUpdateOperation alloc] initWithPackageNames:packageNames];
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(_handleInstallFinishedNotification:) 
                                                     name:TLMOperationFinishedNotification 
                                                   object:op];
        [_queue addOperation:op];
        [op release];   
    }
}

# pragma mark table datasource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView;
{
    return [_packages count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row;
{
    NSString *identifier = [tableColumn identifier];
    id value = nil;

    if ([identifier isEqualToString:@"action"] == NO)
        value = [[_packages objectAtIndex:row] valueForKey:identifier];
    
    return value;
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row;
{
    TLMPackage *package = [_packages objectAtIndex:row];
    if ([[tableColumn identifier] isEqualToString:@"action"] == NO) {
        if ([package failedToParse])
            [cell setTextColor:[NSColor redColor]];
        else if ([package willBeRemoved])
            [cell setTextColor:[NSColor grayColor]];
        else if ([package currentlyInstalled] == NO)
            [cell setTextColor:[NSColor blueColor]];
        else
            [cell setTextColor:[NSColor blackColor]];
    }
}

- (NSCell *)tableView:(NSTableView *)tableView dataCellForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    NSCell *dataCell = [tableColumn dataCellForRow:row];
    NSString *identifier = [tableColumn identifier];
    if ([identifier isEqualToString:@"action"]) {
        TLMPackage *package = [_packages objectAtIndex:row];
        if ([package willBeRemoved])
            dataCell = [[[[[tableView tableColumns] objectAtIndex:0] dataCellForRow:0] copy] autorelease];
    }
    return dataCell;
}

static NSComparisonResult __TLMCompareAction(id a, id b, void *context)
{
    // two possible choices: installed and will be removed, or already installed and will be updated
    if ([a willBeRemoved] == [b willBeRemoved])
        return NSOrderedSame;
    if ([a needsUpdate] == [b needsUpdate])
        return NSOrderedSame;
    BOOL ascending = *(BOOL *)context;
    return ascending ? NSOrderedAscending : NSOrderedDescending;
}

- (void)tableView:(NSTableView *)tableView didClickTableColumn:(NSTableColumn *)tableColumn
{
    _sortAscending = !_sortAscending;
    for (NSTableColumn *col in [_tableView tableColumns])
        [_tableView setIndicatorImage:nil inTableColumn:col];
    NSImage *image = _sortAscending ? [NSImage imageNamed:@"NSAscendingSortIndicator"] : [NSImage imageNamed:@"NSDescendingSortIndicator"];
    [_tableView setIndicatorImage:image inTableColumn:tableColumn];
    NSString *identifier = [tableColumn identifier];
    NSSortDescriptor *sort = nil;
    if ([identifier isEqualToString:@"action"]) {
        [_packages sortUsingFunction:__TLMCompareAction context:&_sortAscending];
    }
    else if ([identifier isEqualToString:@"remoteVersion"]) {
        sort = [[[NSSortDescriptor alloc] initWithKey:@"remoteVersion" ascending:_sortAscending] autorelease];
    }
    else if ([identifier isEqualToString:@"localVersion"]) {
        sort = [[[NSSortDescriptor alloc] initWithKey:@"localVersion" ascending:_sortAscending] autorelease];
    }
    else if ([identifier isEqualToString:@"name"]) {
        sort = [[[NSSortDescriptor alloc] initWithKey:@"name" ascending:_sortAscending selector:@selector(localizedCaseInsensitiveCompare:)] autorelease];
    }
    else if ([identifier isEqualToString:@"status"]) {
        sort = [[[NSSortDescriptor alloc] initWithKey:@"status" ascending:_sortAscending selector:@selector(localizedCaseInsensitiveCompare:)] autorelease];
    }
    if (sort) [_packages sortUsingDescriptors:[NSArray arrayWithObject:sort]];
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

#pragma mark Splitview delegate

// implementation from BibDesk's BDSKEditor
- (void)splitView:(TLMSplitView *)splitView doubleClickedDividerAt:(NSUInteger)subviewIndex;
{
    NSView *tableView = [[splitView subviews] objectAtIndex:0];
    NSView *textView = [[splitView subviews] objectAtIndex:1];
    NSRect tableFrame = [tableView frame];
    NSRect textViewFrame = [textView frame];
    
    // not sure what the criteria for isSubviewCollapsed, but it doesn't work
    if(NSHeight(textViewFrame) > 0.0){ 
        // save the current height
        _lastTextViewHeight = NSHeight(textViewFrame);
        tableFrame.size.height += _lastTextViewHeight;
        textViewFrame.size.height = 0.0;
    } else {
        // previously collapsed, so pick a reasonable value to start
        if(_lastTextViewHeight <= 0.0)
            _lastTextViewHeight = 150.0; 
        textViewFrame.size.height = _lastTextViewHeight;
        tableFrame.size.height = NSHeight([splitView frame]) - _lastTextViewHeight - [splitView dividerThickness];
        if (NSHeight(tableFrame) < 0.0) {
            tableFrame.size.height = 0.0;
            textViewFrame.size.height = NSHeight([splitView frame]) - [splitView dividerThickness];
            _lastTextViewHeight = NSHeight(textViewFrame);
        }
    }
    [tableView setFrame:tableFrame];
    [textView setFrame:textViewFrame];
    [splitView adjustSubviews];
    // fix for NSSplitView bug, which doesn't send this in adjustSubviews
    [[NSNotificationCenter defaultCenter] postNotificationName:NSSplitViewDidResizeSubviewsNotification object:splitView];
}

@end
