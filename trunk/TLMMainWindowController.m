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
#import "TLMPackageListDataSource.h"
#import "TLMUpdateListDataSource.h"

#import "TLMListUpdatesOperation.h"
#import "TLMUpdateOperation.h"
#import "TLMInfraUpdateOperation.h"
#import "TLMPapersizeOperation.h"
#import "TLMAuthorizedOperation.h"
#import "TLMListOperation.h"
#import "TLMRemoveOperation.h"

#import "TLMSplitView.h"
#import "TLMStatusView.h"
#import "TLMInfoController.h"
#import "TLMPreferenceController.h"
#import "TLMLogServer.h"
#import "TLMAppController.h"
#import "TLMPapersizeController.h"
#import "TLMTabView.h"

static char _TLMOperationQueueOperationContext;

@implementation TLMMainWindowController

@synthesize _progressIndicator;
@synthesize _hostnameField;
@synthesize _splitView;
@synthesize _logDataSource;
@synthesize lastUpdateURL = _lastUpdateURL;
@synthesize _statusView;
@synthesize _packageListDataSource;
@synthesize _tabView;
@synthesize _statusBarView;
@synthesize _updateListDataSource;
@synthesize infrastructureNeedsUpdate = _updateInfrastructure;

- (id)init
{
    return [self initWithWindowNibName:[self windowNibName]];
}

- (id)initWithWindowNibName:(NSString *)windowNibName
{
    self = [super initWithWindowNibName:windowNibName];
    if (self) {
        _queue = [NSOperationQueue new];
        [_queue setMaxConcurrentOperationCount:1];
        [_queue addObserver:self forKeyPath:@"operations" options:0 context:&_TLMOperationQueueOperationContext];
        _lastTextViewHeight = 0.0;
        _updateInfrastructure = NO;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_handleApplicationTerminate:) 
                                                     name:NSApplicationWillTerminateNotification
                                                   object:NSApp];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_queue removeObserver:self forKeyPath:@"operations"];
    [_queue cancelAllOperations];
    [_queue waitUntilAllOperationsAreFinished];
    [_queue release];
    
    [_splitView setDelegate:nil];
    [_splitView release];
    [_statusView release];
    [_statusBarView release];
    
    [_progressIndicator release];
    [_lastUpdateURL release];
    [_logDataSource release];
    [_packageListDataSource release];
    [_updateListDataSource release];
    
    [super dealloc];
}

- (void)awakeFromNib
{
    [[self window] setTitle:[[NSBundle mainBundle] objectForInfoDictionaryKey:(id)kCFBundleNameKey]];
    [self setLastUpdateURL:[[TLMPreferenceController sharedPreferenceController] defaultServerURL]]; 

    // set delegate before adding tabs, so the datasource gets inserted properly in the responder chain
    [_tabView setDelegate:self];
    [_tabView addTabNamed:NSLocalizedString(@"Updates", @"") withView:[[_updateListDataSource tableView]  enclosingScrollView]];
    [_tabView addTabNamed:NSLocalizedString(@"All Packages", @"") withView:[[_packageListDataSource outlineView] enclosingScrollView]];
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    // may as well populate the list immediately; by now we should have the window to display a warning sheet
    [self refreshUpdatedPackageList];
    
    // checkbox in IB doesn't work?
    [[[self window] toolbar] setAutosavesConfiguration:YES];
}

- (void)_handleApplicationTerminate:(NSNotification *)aNote
{
    [_queue cancelAllOperations];
    // probably don't want to waitUntilAllOperationsAreFinished here, since we can't force an install operation to quit
}

- (BOOL)_checkCommandPathAndWarn:(BOOL)displayWarning
{
    NSString *cmdPath = [[TLMPreferenceController sharedPreferenceController] tlmgrAbsolutePath];
    BOOL exists = [[NSFileManager defaultManager] isExecutableFileAtPath:cmdPath];
    
    if (NO == exists) {
        TLMLog(nil, @"tlmgr not found at \"%@\"", cmdPath);
        if (displayWarning) {
            NSAlert *alert = [[NSAlert new] autorelease];
            [alert setMessageText:NSLocalizedString(@"TeX installation not found.", @"")];
            [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"The tlmgr tool does not exist at %@.  Please set the correct location in preferences or install TeX Live.", @""), cmdPath]];
            [alert beginSheetModalForWindow:[self window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
        }
    }
    
    return exists;
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
    
    // can either do this or post a custom event...
    [[[self window] toolbar] validateVisibleItems];
}

// NB: this will arrive on the queue's thread, at least under some conditions!
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == &_TLMOperationQueueOperationContext) {
        [self performSelectorOnMainThread:@selector(_operationCountChanged) withObject:nil waitUntilDone:NO];
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)setLastUpdateURL:(NSURL *)aURL
{
    if (nil == aURL) {
        NSURL *defaultURL = [[TLMPreferenceController sharedPreferenceController] defaultServerURL];
        TLMLog(nil, @"A nil URL was passed to %@; using default %@ instead", NSStringFromSelector(_cmd), defaultURL);
        aURL = defaultURL;
    }
    NSParameterAssert(aURL);
    [_hostnameField setStringValue:[aURL absoluteString]];
    
    [_lastUpdateURL autorelease];
    _lastUpdateURL = [aURL copy];
}

- (void)_updateAll
{
    TLMUpdateOperation *op = nil;
    if (_updateInfrastructure) {
        op = [[TLMInfraUpdateOperation alloc] initWithLocation:_lastUpdateURL];
        TLMLog(nil, @"Beginning infrastructure update from %@", [_lastUpdateURL absoluteString]);
    }
    else {
        op = [[TLMUpdateOperation alloc] initWithPackageNames:nil location:_lastUpdateURL];
        TLMLog(nil, @"Beginning update of all packages from %@", [_lastUpdateURL absoluteString]);
    }
    
    if (op) {
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(_handleUpdateFinishedNotification:) 
                                                     name:TLMOperationFinishedNotification 
                                                   object:op];
        [_queue addOperation:op];
        [op release];   
    }
}

- (void)infrastructureAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;
{
    if (NSAlertFirstButtonReturn == returnCode) {
        [self _updateAll];
    }
}

// pass nil for status to clear the view and remove it
- (void)_displayStatusString:(NSString *)statusString
{
    if (statusString) {
        [_statusView setStatusString:statusString];
        [_statusView setFrame:[_tabView bounds]];
        [_tabView addSubview:_statusView];
        [_statusView fadeIn];
    }
    else if ([_statusView isDescendantOf:_tabView]) {
        [_statusView fadeOut];
    }
}    

- (void)_handleListUpdatesFinishedNotification:(NSNotification *)aNote
{
    NSParameterAssert([NSThread isMainThread]);
    TLMListUpdatesOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    
    NSArray *allPackages = [op packages];

    // Karl sez these are the packages that the next version of tlmgr will require you to install before installing anything else
    // note that a slow-to-update mirror may have a stale version, so check needsUpdate as well
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"(name IN { 'bin-texlive', 'texlive.infra' }) AND (needsUpdate == YES)"];
    NSArray *packages = [allPackages filteredArrayUsingPredicate:predicate];
    
    if ([packages count]) {
        _updateInfrastructure = YES;
        // log for debugging, then display an alert so the user has some idea of what's going on...
        TLMLog(nil, @"Critical updates detected: %@", [packages valueForKey:@"name"]);
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"Critical updates available.", @"")];
        [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"%d packages are available for update, but the TeX Live installer packages listed here must be updated first.  Update now?", @""), [[op packages] count]]];
        [alert addButtonWithTitle:NSLocalizedString(@"Update", @"")];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
        [alert beginSheetModalForWindow:[self window]
                          modalDelegate:self 
                         didEndSelector:@selector(infrastructureAlertDidEnd:returnCode:contextInfo:) 
                            contextInfo:NULL];
    }
    else {
        _updateInfrastructure = NO;
        packages = allPackages;
    }
    
    [_updateListDataSource setAllPackages:packages];
    [self setLastUpdateURL:[op updateURL]];
    
    NSString *statusString = nil;
    
    if ([op isCancelled])
        statusString = NSLocalizedString(@"Listing Cancelled", @"");
    else if ([op failed])
        statusString = NSLocalizedString(@"Listing Failed", @"");
    else if ([packages count] == 0)
        statusString = NSLocalizedString(@"No Updates Available", @"");
    
    [self _displayStatusString:statusString];
}

- (void)_refreshUpdatedPackageListFromLocation:(NSURL *)location
{
    [self _displayStatusString:nil];
    if ([self _checkCommandPathAndWarn:YES]) {
        TLMListUpdatesOperation *op = [[TLMListUpdatesOperation alloc] initWithLocation:location];
        if (op) {
            TLMLog(nil, @"Refreshing list of updated packages%C", 0x2026);
            [[NSNotificationCenter defaultCenter] addObserver:self 
                                                     selector:@selector(_handleListUpdatesFinishedNotification:) 
                                                         name:TLMOperationFinishedNotification 
                                                       object:op];
            [_queue addOperation:op];
            [op release];
        }
    }    
}

- (void)disasterAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)context
{
    if (NSAlertFirstButtonReturn == returnCode)
        [[NSApp delegate] openDisasterRecoveryPage:nil];
    else
        TLMLog(nil, @"User chose not to open %@ after failure", @"http://tug.org/texlive/tlmgr.html");
}

- (void)_handleUpdateFinishedNotification:(NSNotification *)aNote
{
    NSParameterAssert([NSThread isMainThread]);
    TLMUpdateOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    
    // ignore operations that failed or were explicitly cancelled
    if ([op failed]) {
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"The installation failed.", @"")];
        [alert setInformativeText:NSLocalizedString(@"The installation process appears to have failed.  Please check the log display below for details.", @"")];
        [alert beginSheetModalForWindow:[self window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];                    
    }
    else if ([op isCancelled] == NO) {
        
        // check to see if this was an infrastructure update, which may have wiped out tlmgr
        // NB: should never happen with the new update path (always using disaster recovery)
        if (_updateInfrastructure && NO == [self _checkCommandPathAndWarn:NO]) {
            NSAlert *alert = [[NSAlert new] autorelease];
            [alert setAlertStyle:NSCriticalAlertStyle];
            [alert setMessageText:NSLocalizedString(@"The tlmgr tool no longer exists, possibly due to an update failure.", @"")];
            [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Follow the instructions for Unix disaster recovery on the TeX Live web site at %@.  Would you like to go to that page now?  You can also open it later from the Help menu.", @""), @"http://tug.org/texlive/tlmgr.html"]];
            [alert addButtonWithTitle:NSLocalizedString(@"Open Now", @"")];
            [alert addButtonWithTitle:NSLocalizedString(@"Later", @"")];
            [alert beginSheetModalForWindow:[self window] 
                              modalDelegate:self 
                             didEndSelector:@selector(disasterAlertDidEnd:returnCode:contextInfo:) 
                                contextInfo:NULL];            
        }
        else {
            // This is slow, but if infrastructure was updated or a package installed other dependencies, we have no way of manually removing from the list.  We also need to ensure that the same mirror is used, so results are consistent.
            [self _refreshUpdatedPackageListFromLocation:[self lastUpdateURL]];
        }
    }
}

// FIXME: add a property to operations instead of checking class
- (BOOL)_installIsRunning
{
    NSArray *ops = [[[_queue operations] copy] autorelease];
    for (id op in ops) {
        if ([op isKindOfClass:[TLMAuthorizedOperation class]])
            return YES;
    }
    return NO;
}

// tried validating toolbar items using bindings to queue.operations.@count but the queue sends KVO notifications on its own thread
- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem;
{
    SEL action = [anItem action];
    if (@selector(cancelAllOperations:) == action)
        return [[_queue operations] count];
    else if (@selector(updateAll:) == action)
        return [[_queue operations] count] == 0 && [[_updateListDataSource allPackages] count];
    else
        return YES;
}

- (IBAction)cancelAllOperations:(id)sender;
{
    [_queue cancelAllOperations];
}

- (void)_handlePapersizeFinishedNotification:(NSNotification *)aNote
{
    TLMPapersizeOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    if ([op failed]) {
        TLMLog(nil, @"Failed to change paper size.  Error was: %@", [op errorMessages]);
    }
}

- (IBAction)papersizeSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)context
{
    [sheet orderOut:self];
    TLMPapersizeController *psc = context;
    [psc autorelease];
    if (TLMPapersizeChanged == returnCode) {
        TLMPapersizeOperation *op = nil;
        if ([psc paperSize])
            op = [[TLMPapersizeOperation alloc] initWithPapersize:[psc paperSize]];
        else
            TLMLog(nil, @"No paper size from %@", psc);
        if (op) {
            TLMLog(nil, @"Setting paper size to %@", [psc paperSize]);
            [[NSNotificationCenter defaultCenter] addObserver:self 
                                                     selector:@selector(_handlePapersizeFinishedNotification:) 
                                                         name:TLMOperationFinishedNotification 
                                                       object:op];
            [_queue addOperation:op];
            [op release];               
        }
    }
}

- (IBAction)changePapersize:(id)sender;
{
    TLMPapersizeController *psc = [TLMPapersizeController new];
    [NSApp beginSheet:[psc window] 
       modalForWindow:[self window] 
        modalDelegate:self 
       didEndSelector:@selector(papersizeSheetDidEnd:returnCode:contextInfo:) 
          contextInfo:psc];
}

- (void)_removeDataSourceFromResponderChain:(id)dataSource
{
    NSResponder *next = [self nextResponder];
    if ([next isEqual:_updateListDataSource] || [next isEqual:_packageListDataSource]) {
        [self setNextResponder:[next nextResponder]];
        [next setNextResponder:nil];
    }
}

- (void)_insertDataSourceInResponderChain:(id)dataSource
{
    NSResponder *next = [self nextResponder];
    NSParameterAssert([next isEqual:_updateListDataSource] == NO);
    NSParameterAssert([next isEqual:_packageListDataSource] == NO);
    
    [self setNextResponder:dataSource];
    [dataSource setNextResponder:next];
}

- (void)tabView:(TLMTabView *)tabView didSelectViewAtIndex:(NSUInteger)anIndex;
{
    // clear the status overlay
    [self _displayStatusString:nil];

    switch (anIndex) {
        case 0:
            
            [self _removeDataSourceFromResponderChain:_packageListDataSource];
            [self _insertDataSourceInResponderChain:_updateListDataSource];   
            
            if ([[_updateListDataSource allPackages] count])
                [_updateListDataSource search:nil];
            break;
        case 1:
            
            [self _removeDataSourceFromResponderChain:_updateListDataSource];
            [self _insertDataSourceInResponderChain:_packageListDataSource];            

            if ([[_packageListDataSource packageNodes] count])
                [_packageListDataSource search:nil];
            else if ([[[_queue operations] valueForKey:@"class"] containsObject:[TLMListOperation self]] == NO)
                [self refreshFullPackageList];
            break;
        default:
            break;
    }
}

- (void)_handleListFinishedNotification:(NSNotification *)aNote
{
    TLMListOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    [_packageListDataSource setPackageNodes:[op packageNodes]];
    
    NSString *statusString = nil;
    
    if ([op isCancelled])
        statusString = NSLocalizedString(@"Listing Cancelled", @"");
    else if ([op failed])
        statusString = NSLocalizedString(@"Listing Failed", @"");
    
    [self _displayStatusString:statusString];
    [self setLastUpdateURL:[op updateURL]];
}

- (void)_refreshFullPackageListFromLocation:(NSURL *)location
{
    [self _displayStatusString:nil];
    if ([self _checkCommandPathAndWarn:YES]) {
        TLMListOperation *op = [[TLMListOperation alloc] initWithLocation:location];
        if (op) {
            TLMLog(nil, @"Refreshing list of all packages%C", 0x2026);
            [[NSNotificationCenter defaultCenter] addObserver:self 
                                                     selector:@selector(_handleListFinishedNotification:) 
                                                         name:TLMOperationFinishedNotification 
                                                       object:op];
            [_queue addOperation:op];
            [op release];
        }            
    }         
}

- (void)refreshFullPackageList
{
    [self _refreshFullPackageListFromLocation:[[TLMPreferenceController sharedPreferenceController] defaultServerURL]];
}

- (void)refreshUpdatedPackageList
{
    [self _refreshUpdatedPackageListFromLocation:[[TLMPreferenceController sharedPreferenceController] defaultServerURL]];
}

- (void)updateAllAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;
{
    if (NSAlertFirstButtonReturn == returnCode) {
        [self _updateAll];
    }    
}

- (IBAction)updateAll:(id)sender;
{
    if ([self _checkCommandPathAndWarn:YES]) {
        NSAlert *alert = [[NSAlert new] autorelease];
        NSUInteger size = 0;
        for (TLMPackage *pkg in [_updateListDataSource allPackages])
            size += [[pkg size] unsignedIntegerValue];
        
        [alert setMessageText:NSLocalizedString(@"Update all packages?", @"")];
        // may not be correct for _updateInfrastructure, but tlmgr may remove stuff also...so leave it as-is
        NSMutableString *informativeText = [NSMutableString string];
        [informativeText appendString:NSLocalizedString(@"This will install all available updates and remove packages that no longer exist on the server.", @"")];
        
        if (size > 0) {
            
            CGFloat totalSize = size;
            NSString *sizeUnits = @"bytes";
            
            // check 1024 + 10% so the plural is always correct (at least in English)
            if (totalSize > 1127) {
                totalSize /= 1024.0;
                sizeUnits = @"kilobytes";
                
                if (totalSize > 1127) {
                    totalSize /= 1024.0;
                    sizeUnits = @"megabytes";
                }
            }
            
            [informativeText appendFormat:NSLocalizedString(@"  Total download size will be %.1f %@.", @""), totalSize, sizeUnits];
        }
        [alert setInformativeText:informativeText];
        [alert addButtonWithTitle:NSLocalizedString(@"Update", @"")];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
        [alert beginSheetModalForWindow:[self window] 
                          modalDelegate:self 
                         didEndSelector:@selector(updateAllAlertDidEnd:returnCode:contextInfo:) 
                            contextInfo:NULL]; 
    }
}    

- (BOOL)windowShouldClose:(id)sender;
{
    BOOL shouldClose = YES;
    if ([self _installIsRunning]) {
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"Installation in progress!", @"")];
        [alert setAlertStyle:NSCriticalAlertStyle];
        [alert setInformativeText:NSLocalizedString(@"If you close the window, the installation process may leave your TeX installation in an unknown state.  You can ignore this warning and close the window, or wait until the installation finishes.", @"")];
        [alert addButtonWithTitle:NSLocalizedString(@"Wait", @"")];
        [alert addButtonWithTitle:NSLocalizedString(@"Ignore", @"")];
        
        NSInteger rv = [alert runModal];
        if (NSAlertFirstButtonReturn == rv)
            shouldClose = NO;
    }
    return shouldClose;
}

- (void)updatePackagesWithNames:(NSArray *)packageNames;
{
    // !!! early return here if tlmgr doesn't exist
    if (NO == [self _checkCommandPathAndWarn:YES])
        return;
    
    TLMUpdateOperation *op = [[TLMUpdateOperation alloc] initWithPackageNames:packageNames location:_lastUpdateURL];
    if (op) {
        TLMLog(nil, @"Beginning update of %@\nfrom %@", packageNames, [_lastUpdateURL absoluteString]);
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(_handleUpdateFinishedNotification:) 
                                                     name:TLMOperationFinishedNotification 
                                                   object:op];
        [_queue addOperation:op];
        [op release];   
    }
}

- (void)installPackagesWithNames:(NSArray *)packageNames
{
    // !!! early return here if tlmgr doesn't exist
    if (NO == [self _checkCommandPathAndWarn:YES])
        return;
    
    // UI action takes place on the full package list
    [self _refreshFullPackageListFromLocation:[self lastUpdateURL]];
    
    // this is always displayed, so should always be updated as well
    [self _refreshUpdatedPackageListFromLocation:[self lastUpdateURL]];
}

- (void)_handleRemoveFinishedNotification:(NSNotification *)aNote
{
    TLMUpdateOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    
    // ignore operations that failed or were explicitly cancelled
    if ([op failed]) {
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"Removal failed.", @"")];
        [alert setInformativeText:NSLocalizedString(@"The removal process appears to have failed.  Please check the log display below for details.", @"")];
        [alert beginSheetModalForWindow:[self window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];                    
    }
    else if ([op isCancelled] == NO) {
        
        // This is slow, but if a package installed other dependencies, we have no way of manually removing from the list.  We also need to ensure that the same mirror is used, so results are consistent.
        [self _refreshFullPackageListFromLocation:[self lastUpdateURL]];
        
        // this is always displayed, so should always be updated as well
        [self _refreshUpdatedPackageListFromLocation:[self lastUpdateURL]];
    }    
}

- (void)removePackagesWithNames:(NSArray *)packageNames
{     
    // some idiot could try to wipe out tlmgr itself, so let's try to prevent that...
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF IN { 'bin-texlive', 'texlive.infra' }"];
    NSArray *packages = [packageNames filteredArrayUsingPredicate:predicate];
    
    if (NO == [self _checkCommandPathAndWarn:YES] || [packages count]) {
        // log for debugging, then display an alert so the user has some idea of what's going on...
        TLMLog(nil, @"Tried to remove infrastructure packages: %@", [packages valueForKey:@"name"]);
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"Some of these packages cannot be removed.", @"")];
        [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"You are attempting to remove critical parts of the underlying TeX Live infrastructure, and I won't help you with that.", @"")]];
        [alert beginSheetModalForWindow:[self window]
                          modalDelegate:nil 
                         didEndSelector:NULL
                            contextInfo:NULL];
    }
    else {
        TLMRemoveOperation *op = [[TLMRemoveOperation alloc] initWithPackageNames:packageNames];
        if (op) {
            TLMLog(nil, @"Beginning removal of\n%@", packageNames);
            [[NSNotificationCenter defaultCenter] addObserver:self 
                                                     selector:@selector(_handleRemoveFinishedNotification:) 
                                                         name:TLMOperationFinishedNotification 
                                                       object:op];
            [_queue addOperation:op];
            [op release];   
        }   
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
