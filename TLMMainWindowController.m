//
//  TLMMainWindowController.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/6/08.
/*
 This software is Copyright (c) 2008-2010
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
#import "TLMInstallDataSource.h"

#import "TLMListUpdatesOperation.h"
#import "TLMUpdateOperation.h"
#import "TLMInfraUpdateOperation.h"
#import "TLMPapersizeOperation.h"
#import "TLMAuthorizedOperation.h"
#import "TLMListOperation.h"
#import "TLMRemoveOperation.h"
#import "TLMInstallOperation.h"
#import "TLMNetInstallOperation.h"
#import "TLMOptionOperation.h"
#import "TLMBackupOperation.h"

#import "TLMSplitView.h"
#import "TLMStatusWindow.h"
#import "TLMInfoController.h"
#import "TLMPreferenceController.h"
#import "TLMLogServer.h"
#import "TLMAppController.h"
#import "TLMPapersizeController.h"
#import "TLMTabView.h"
#import "TLMReadWriteOperationQueue.h"
#import "TLMSizeFormatter.h"
#import "TLMTask.h"
#import "TLMProgressIndicatorCell.h"
#import "TLMAutobackupController.h"

static char _TLMOperationQueueOperationContext;

@implementation TLMMainWindowController

@synthesize _progressIndicator;
@synthesize _progressBar;
@synthesize _hostnameView;
@synthesize _splitView;
@synthesize _logDataSource;
@synthesize _packageListDataSource;
@synthesize _tabView;
@synthesize _statusBarView;
@synthesize _updateListDataSource;
@synthesize _installDataSource;
@synthesize infrastructureNeedsUpdate = _updateInfrastructure;

#define ENABLE_INSTALL 0

- (id)init
{
    return [self initWithWindowNibName:[self windowNibName]];
}

- (id)initWithWindowNibName:(NSString *)windowNibName
{
    self = [super initWithWindowNibName:windowNibName];
    if (self) {
        TLMReadWriteOperationQueue *queue = [TLMReadWriteOperationQueue defaultQueue];
        [queue addObserver:self forKeyPath:@"operationCount" options:0 context:&_TLMOperationQueueOperationContext];
        _lastTextViewHeight = 0.0;
        _updateInfrastructure = NO;
        _operationCount = 0;
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[TLMReadWriteOperationQueue defaultQueue] removeObserver:self forKeyPath:@"operationCount"];
    
    [_tabView setDelegate:nil];
    [_tabView release];
    
    [_splitView setDelegate:nil];
    [_splitView release];
    
    [_statusBarView release];
    [_hostnameView release];
    
    [_progressIndicator release];
    [_progressBar release];
    [_logDataSource release];
    [_packageListDataSource release];
    [_updateListDataSource release];
    [_previousInfrastructureVersions release];
    
    [super dealloc];
}

- (void)awakeFromNib
{
    [[self window] setTitle:[[NSBundle mainBundle] objectForInfoDictionaryKey:(id)kCFBundleNameKey]];

    // set delegate before adding tabs, so the datasource gets inserted properly in the responder chain
    _currentListDataSource = _updateListDataSource;
    [_tabView setDelegate:self];
    [_tabView addTabNamed:NSLocalizedString(@"Manage Updates", @"tab title") withView:[[_updateListDataSource tableView]  enclosingScrollView]];
    [_tabView addTabNamed:NSLocalizedString(@"Manage Packages", @"tab title") withView:[[_packageListDataSource outlineView] enclosingScrollView]];
#if ENABLE_INSTALL
    [_tabView addTabNamed:NSLocalizedString(@"Install", @"tab title") withView:[[_installDataSource outlineView] enclosingScrollView]];
#endif
    
    // 10.5 release notes say this is enabled by default, but it returns NO
    [_progressIndicator setUsesThreadedAnimation:YES];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_startProgressBar:)
                                                 name:TLMLogTotalProgressNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_updateProgressBar:)
                                                 name:TLMLogIncrementalProgressNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_stopProgressBar:)
                                                 name:TLMLogFinishedProgressNotification
                                               object:nil];
}

- (void)_stopProgressBar:(NSNotification *)aNote
{
    // we're done with the progress bar now, so set it to maxValue to keep it from using CPU while hidden (seen on 10.6.3)
    [[self _progressBar] setDoubleValue:[[self _progressBar] maxValue]];
    [[self _progressBar] setHidden:YES];
    [NSApp setApplicationIconImage:nil];
}

- (void)_startProgressBar:(NSNotification *)aNote
{
    // just in case it's still running, though that should never happen with the read/write queue...
    [self _stopProgressBar:nil];
    
    // hack from BibDesk: progress bars may not work correctly after the first time they're used, due to an AppKit bug
    NSProgressIndicator *pb = [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:[self _progressBar]]];
    [[[self _progressBar] superview] replaceSubview:[self _progressBar] with:pb];
    [self set_progressBar:pb];
    [[self _progressBar] setMinValue:0.0];
    [[self _progressBar] setMaxValue:[[[aNote userInfo] objectForKey:TLMLogSize] doubleValue]];
    // we always have an integral number of bytes >> 1, so set a fake value here so it draws immediately
    [[self _progressBar] setDoubleValue:0.5];
    [[self _progressBar] setHidden:NO];
    [[self _progressBar] display];
}

- (void)_updateProgressBar:(NSNotification *)aNote
{
    [[self _progressBar] incrementBy:[[[aNote userInfo] objectForKey:TLMLogSize] doubleValue]];
    // make sure it displays immediately
    [[self _progressBar] display];
    
    CGFloat p = [[self _progressBar] doubleValue] / [[self _progressBar] maxValue];
    [NSApp setApplicationIconImage:[TLMProgressIndicatorCell applicationIconBadgedWithProgress:p]];
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    // may as well populate the list immediately; by now we should have the window to display a warning sheet
    [self refreshUpdatedPackageList];
    
    // checkbox in IB doesn't work?
    [[[self window] toolbar] setAutosavesConfiguration:YES];    
}

- (NSString *)windowNibName { return @"MainWindow"; }

- (void)_setOperationCountAsNumber:(NSNumber *)count
{
    NSParameterAssert([NSThread isMainThread]);
    
    NSUInteger newCount = [count unsignedIntegerValue];
    if (_operationCount != newCount) {
        
        // previous count was zero, so spinner is currently stopped
        if (0 == _operationCount) {
            [_progressIndicator startAnimation:self];
        }
        // previous count != 0, so spinner is currently animating
        else if (0 == newCount) {
            [_progressIndicator stopAnimation:self];
        }
        
        // validation depends on this value
        _operationCount = newCount;
        
        // can either do this or post a custom event...
        [[[self window] toolbar] validateVisibleItems];
    }
}

// NB: this will arrive on the queue's thread, at least under some conditions!
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == &_TLMOperationQueueOperationContext) {
        /*
         NSOperationQueue + KVO sucks: calling performSelectorOnMainThread:withObject:waitUntilDone: 
         with waitUntilDone:YES will cause a deadlock if the main thread is currently in a callout to -[NSOperationQueue operations].
         What good is KVO on a non-main thread anyway?  That makes it useless for bindings, and KVO is a pain in the ass to use
         vs. something like NSNotification.  Grrr.
         */
        NSNumber *count = [NSNumber numberWithUnsignedInteger:[[TLMReadWriteOperationQueue defaultQueue] operationCount]];
        [self performSelectorOnMainThread:@selector(_setOperationCountAsNumber:) withObject:count waitUntilDone:NO];
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

// tried validating toolbar items using bindings to queue.operations.@count but the queue sends KVO notifications on its own thread
- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem;
{
    SEL action = [anItem action];
    if (@selector(cancelAllOperations:) == action)
        return _operationCount > 0;
    else if (@selector(updateInfrastructure:) == action)
        return [[TLMReadWriteOperationQueue defaultQueue] isWriting] == NO;
    else
        return YES;
}

- (BOOL)windowShouldClose:(id)sender;
{
    BOOL shouldClose = YES;
    if ([[TLMReadWriteOperationQueue defaultQueue] isWriting]) {
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"Installation in progress!", @"alert title")];
        [alert setAlertStyle:NSCriticalAlertStyle];
        [alert setInformativeText:NSLocalizedString(@"If you close the window, the installation process may leave your TeX installation in an unknown state.  You can ignore this warning and close the window, or wait until the installation finishes.", @"alert message text")];
        [alert addButtonWithTitle:NSLocalizedString(@"Wait", @"button title")];
        [alert addButtonWithTitle:NSLocalizedString(@"Ignore", @"button title")];
        
        NSInteger rv = [alert runModal];
        if (NSAlertFirstButtonReturn == rv)
            shouldClose = NO;
    }
    return shouldClose;
}

#pragma mark Interface updates

/*
 Cover for <TLMListDataSource> lastUpdateURL that ensures the URL is non-nil.  
 The original tlmgr (August 2008 MacTeX) doesn't print the URL on the first line of output, 
 and we die with various assertion failures if the URL is nil.  Parsing logs a diagnostic
 in this case, as well, since this breaks some functionality.
 */
- (NSURL *)_lastUpdateURL
{
    NSURL *aURL = [_currentListDataSource lastUpdateURL];
    if (nil == aURL)
        aURL = [[TLMPreferenceController sharedPreferenceController] validServerURL];
    NSParameterAssert(aURL);
    return aURL;
}

- (void)_updateURLView
{
    NSURL *aURL = [_currentListDataSource lastUpdateURL];
    // use defaultServerURL if we haven't previously contacted a host; -validServerURL does network ops
    if (nil == aURL)
        aURL = [[TLMPreferenceController sharedPreferenceController] defaultServerURL];
    NSTextStorage *ts = [_hostnameView textStorage];
    [[ts mutableString] setString:[aURL absoluteString]];
    [ts addAttribute:NSFontAttributeName value:[NSFont labelFontOfSize:0] range:NSMakeRange(0, [ts length])];
    [ts addAttribute:NSLinkAttributeName value:aURL range:NSMakeRange(0, [ts length])];
    [ts addAttributes:[_hostnameView linkTextAttributes] range:NSMakeRange(0, [ts length])];
}

- (void)_fixOverlayWindowOrder
{
    /*
     To avoid showing the overlay window on top of a sheet, call this on a delay
     after showing a sheet or status window.  NB: changing the window level here
     will screw things up; the sheet needs to be at NSNormalWindowLevel.
     */
    TLMStatusWindow *statusWindow = [_currentListDataSource statusWindow];
    if (statusWindow)
        [[[self window] attachedSheet] orderWindow:NSWindowAbove relativeTo:[statusWindow windowNumber]];
}

- (NSRect)window:(NSWindow *)window willPositionSheet:(NSWindow *)sheet usingRect:(NSRect)rect
{
    [self performSelector:@selector(_fixOverlayWindowOrder) withObject:nil afterDelay:0];
    return rect;
}

// pass nil for status to clear the view and remove it
- (void)_displayStatusString:(NSString *)statusString dataSource:(id <TLMListDataSource>)dataSource
{
    // may currently be a window, so get rid of it
    [[dataSource statusWindow] fadeOutAndRemove:YES];
    [dataSource setStatusWindow:nil];
    
    if (statusString) {
        // status window is one shot
        [dataSource setStatusWindow:[TLMStatusWindow windowWithStatusString:statusString frameFromView:_tabView]];
        
        // only display now if this datasource is current
        if ([_currentListDataSource isEqual:dataSource]) {
            [[self window] addChildWindow:[_currentListDataSource statusWindow] ordered:NSWindowAbove];
            [[dataSource statusWindow] fadeIn];
            [self performSelector:@selector(_fixOverlayWindowOrder) withObject:nil afterDelay:0];
        }
    }
}    

- (void)_removeDataSourceFromResponderChain:(id)dataSource
{
    NSResponder *next = [self nextResponder];
#if ENABLE_INSTALL
    if ([next isEqual:_updateListDataSource] || [next isEqual:_packageListDataSource] || [next isEqual:_installDataSource])
#else
    if ([next isEqual:_updateListDataSource] || [next isEqual:_packageListDataSource])
#endif
    {
        [self setNextResponder:[next nextResponder]];
        [next setNextResponder:nil];
    }
}

- (void)_insertDataSourceInResponderChain:(id)dataSource
{
    NSResponder *next = [self nextResponder];
    NSParameterAssert([next isEqual:_updateListDataSource] == NO);
    NSParameterAssert([next isEqual:_packageListDataSource] == NO);
#if ENABLE_INSTALL
    NSParameterAssert([next isEqual:_installDataSource] == NO);
#endif
    
    [self setNextResponder:dataSource];
    [dataSource setNextResponder:next];
}

- (void)tabView:(TLMTabView *)tabView didSelectViewAtIndex:(NSUInteger)anIndex;
{
    // clear the status overlay, if any
    [[_currentListDataSource statusWindow] fadeOutAndRemove:NO];
    [self _removeDataSourceFromResponderChain:_currentListDataSource];
    
    switch (anIndex) {
        case 0:
            
            [self _insertDataSourceInResponderChain:_updateListDataSource];   
            _currentListDataSource = _updateListDataSource;
            [self _updateURLView];
            [[_currentListDataSource statusWindow] fadeIn];

            if ([[_updateListDataSource allPackages] count])
                [_updateListDataSource search:nil];
            break;
        case 1:
            
            [self _insertDataSourceInResponderChain:_packageListDataSource];   
            _currentListDataSource = _packageListDataSource;
            [self _updateURLView];
            [[_currentListDataSource statusWindow] fadeIn];

            // we load the update list on launch, so load this one on first access of the tab

            if ([[_packageListDataSource packageNodes] count])
                [_packageListDataSource search:nil];
            else if ([_packageListDataSource isRefreshing] == NO)
                [self refreshFullPackageList];

            break;
#if ENABLE_INSTALL
        case 2:
            [self _insertDataSourceInResponderChain:_installDataSource];
            _currentListDataSource = _installDataSource;
            [self _updateURLView];
            [[_currentListDataSource statusWindow] fadeIn];
            
            break;
#endif
        default:
            break;
    }
}

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

#pragma mark -
#pragma mark Operations

- (BOOL)_checkCommandPathAndWarn:(BOOL)displayWarning
{
    NSString *cmdPath = [[TLMPreferenceController sharedPreferenceController] tlmgrAbsolutePath];
    BOOL exists = [[NSFileManager defaultManager] isExecutableFileAtPath:cmdPath];
    
    if (NO == exists) {
        TLMLog(__func__, @"tlmgr not found at \"%@\"", cmdPath);
        if (displayWarning) {
            NSAlert *alert = [[NSAlert new] autorelease];
            [alert setMessageText:NSLocalizedString(@"TeX installation not found.", @"alert sheet title")];
            [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"The tlmgr tool does not exist at %@.  Please set the correct location in preferences or install TeX Live.", @"alert message text"), cmdPath]];
            [alert beginSheetModalForWindow:[self window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
        }
    }
    
    return exists;
}

- (void)_addOperation:(TLMOperation *)op selector:(SEL)sel
{
    // avoid the tlmgr check when installing
    if (op && ([_currentListDataSource isEqual:_installDataSource] || [self _checkCommandPathAndWarn:YES])) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:sel name:TLMOperationFinishedNotification object:op];
        [[TLMReadWriteOperationQueue defaultQueue] addOperation:op];
    }
}

- (void)_updateAllPackagesFromRepository:(NSURL *)repository
{
    TLMUpdateOperation *op = nil;
    if (_updateInfrastructure) {
        op = [[TLMInfraUpdateOperation alloc] initWithLocation:repository];
        TLMLog(__func__, @"Beginning infrastructure update from %@", [repository absoluteString]);
    }
    else {
        op = [[TLMUpdateOperation alloc] initWithPackageNames:nil location:repository];
        TLMLog(__func__, @"Beginning update of all packages from %@", [repository absoluteString]);
    }
    [self _addOperation:op selector:@selector(_handleUpdateFinishedNotification:)];
    [op release];
}

- (void)_updateAllPackages
{
    [self _updateAllPackagesFromRepository:[self _lastUpdateURL]];
}

static NSDictionary * __TLMCopyVersionsForPackageNames(NSArray *packageNames)
{
    NSMutableDictionary *versions = [NSMutableDictionary new];
    for (NSString *name in packageNames) {
        TLMTask *task = [[TLMTask new] autorelease];
        [task setLaunchPath:[[TLMPreferenceController sharedPreferenceController] tlmgrAbsolutePath]];
        [task setArguments:[NSArray arrayWithObjects:@"show", name, nil]];
        [task launch];
        [task waitUntilExit];

        /*
         $ tlmgr show texlive.infra
         package:    texlive.infra
         category:   TLCore
         shortdesc:  basic TeX Live infrastructure
         longdesc:   This package contains the files needed to get the TeX Live tools (notably tlmgr) running: perl modules, xz binaries, plus (sometimes) tar and wget.  These files end up in the standalone install packages.
         installed:  Yes
         revision:   15199
         collection: collection-basic
        */
                
        if ([task outputString]) {
            NSArray *lines = [[task outputString] componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
            for (NSString *line in lines) {
                line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                NSRange r = [line rangeOfString:@":"];
                if (r.length && [[line substringToIndex:r.location] caseInsensitiveCompare:@"revision"] == NSOrderedSame) {
                    NSInteger vers = [[line substringFromIndex:NSMaxRange(r)] intValue];
                    if (vers > 0) [versions setObject:[NSNumber numberWithInteger:vers] forKey:name];
                    break;
                }
            }
        }
    }
    return versions;
}

- (void)_handleListUpdatesFinishedNotification:(NSNotification *)aNote
{
    NSParameterAssert([NSThread isMainThread]);
    TLMListUpdatesOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    
    NSArray *allPackages = [op packages];

    /*
     TL 2009: 'bin-texlive' is gone, and we now have 'texlive.infra' and 'texlive.infra.universal-darwin' 
     for infrastructure updates.  This is satisfied by checking for the prefix 'texlive.infra'.  The only 
     other infrastructure packages is 'tlperl.win32', which we probably won't see.
     
     Note: a slow-to-update mirror may have a stale version, so check needsUpdate as well.
     */
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"((name == 'tlperl.win32' OR name BEGINSWITH 'texlive.infra')) AND (needsUpdate == YES)"];
    NSArray *packages = [allPackages filteredArrayUsingPredicate:predicate];
    
    if ([packages count]) {
        [_previousInfrastructureVersions release];
        _previousInfrastructureVersions = __TLMCopyVersionsForPackageNames([packages valueForKey:@"name"]);
        _updateInfrastructure = YES;
        // log for debugging, then display an alert so the user has some idea of what's going on...
        TLMLog(__func__, @"Critical updates detected: %@", [packages valueForKey:@"name"]);
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"Critical updates available.", @"alert title")];
        [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"%lu packages are available for update.  Of these, the TeX Live installer packages listed here must be updated first.  Update now?", @"alert message text"), (unsigned long)[[op packages] count]]];
        [alert addButtonWithTitle:NSLocalizedString(@"Update", @"button title")];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"button title")];
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
    [_updateListDataSource setRefreshing:NO];
    [_updateListDataSource setLastUpdateURL:[op updateURL]];
    [self _updateURLView];
    
    NSString *statusString = nil;
    
    if ([op isCancelled])
        statusString = NSLocalizedString(@"Listing Cancelled", @"main window status string");
    else if ([op failed])
        statusString = NSLocalizedString(@"Listing Failed", @"main window status string");
    else if ([packages count] == 0)
        statusString = NSLocalizedString(@"No Updates Available", @"main window status string");
    
    [self _displayStatusString:statusString dataSource:_updateListDataSource];
}

- (void)_refreshUpdatedPackageListFromLocation:(NSURL *)location
{
    [self _displayStatusString:nil dataSource:_updateListDataSource];
    // disable refresh action for this view
    [_updateListDataSource setRefreshing:YES];
    TLMListUpdatesOperation *op = [[TLMListUpdatesOperation alloc] initWithLocation:location];
    [self _addOperation:op selector:@selector(_handleListUpdatesFinishedNotification:)];
    [op release];
    TLMLog(__func__, @"Refreshing list of updated packages%C", 0x2026);
}

- (void)_handleUpdateFinishedNotification:(NSNotification *)aNote
{
    NSParameterAssert([NSThread isMainThread]);
    TLMUpdateOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    
    // ignore operations that failed or were explicitly cancelled
    if ([op failed]) {
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"The installation failed.", @"alert title")];
        [alert setInformativeText:NSLocalizedString(@"The installation process appears to have failed.  Please check the log display below for details.", @"alert message text")];
        [alert beginSheetModalForWindow:[self window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];                    
    }
    else if ([op isCancelled] == NO) {
        
        // check to see if this was an infrastructure update, which may have wiped out tlmgr
        // NB: should never happen with the new update path (always using disaster recovery)
        if (_updateInfrastructure && NO == [self _checkCommandPathAndWarn:NO]) {
            NSAlert *alert = [[NSAlert new] autorelease];
            [alert setAlertStyle:NSCriticalAlertStyle];
            [alert setMessageText:NSLocalizedString(@"The tlmgr tool no longer exists, possibly due to an update failure.", @"alert title")];
            [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Follow the instructions for Unix disaster recovery on the TeX Live web site at %@.  Would you like to go to that page now?  You can also open it later from the Help menu.", @"alert message text"), @"http://tug.org/texlive/tlmgr.html"]];
            [alert addButtonWithTitle:NSLocalizedString(@"Open Now", @"button title")];
            [alert addButtonWithTitle:NSLocalizedString(@"Later", @"button title")];
            [alert beginSheetModalForWindow:[self window] 
                              modalDelegate:self 
                             didEndSelector:@selector(disasterAlertDidEnd:returnCode:contextInfo:) 
                                contextInfo:NULL];            
        }
        else if (_updateInfrastructure) {
            
            /*
             See if texlive.infra version is the same after installing update-tlmgr-latest.sh, which can happen
             if there's an inconsistency between texlive.infra in tlnet and what got wrapped up in the script.
             */
            NSDictionary *currentVersions = [__TLMCopyVersionsForPackageNames([_previousInfrastructureVersions allKeys]) autorelease];
            if ([currentVersions isEqualToDictionary:_previousInfrastructureVersions]) {
                NSAlert *alert = [[NSAlert new] autorelease];
                [alert setMessageText:NSLocalizedString(@"Possible update failure.", @"alert title")];
                [alert setInformativeText:NSLocalizedString(@"The TeX Live infrastructure packages have the same version after updating.  This could be a packaging problem on the server.  If you see this message repeatedly, wait until the problem is resolved in TeX Live before attempting another update.", @"alert message text")];
                
                // refresh packages after this sheet ends, since it'll likely show the infra update alert sheet
                [alert beginSheetModalForWindow:[self window] 
                                  modalDelegate:self 
                                 didEndSelector:@selector(versionAlertDidEnd:returnCode:contextInfo:) 
                                    contextInfo:NULL];
            }
            else {
                [self _refreshUpdatedPackageListFromLocation:[self _lastUpdateURL]];
            }
            
        }
        else {
            
            /*
             This is slow, but if infrastructure was updated or a package installed other dependencies, 
             we have no way of manually removing from the list.  We also need to ensure that the same 
             mirror is used, so results are consistent.
             */
            [self _refreshUpdatedPackageListFromLocation:[self _lastUpdateURL]];
        }
    }
}

- (void)_cancelAllOperations
{
    TLMLog(__func__, @"User cancelling %@", [TLMReadWriteOperationQueue defaultQueue]);
    [[TLMReadWriteOperationQueue defaultQueue] cancelAllOperations];
    
    // cancel info in case it's stuck
    [[TLMInfoController sharedInstance] cancel];
    
    // hide the progress bar in case we're installing
    [self _stopProgressBar:nil];
}

- (void)_handlePapersizeFinishedNotification:(NSNotification *)aNote
{
    TLMPapersizeOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    if ([op failed]) {
        TLMLog(__func__, @"Failed to change paper size.  Error was: %@", [op errorMessages]);
    }
}

- (void)papersizeSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)context
{    
    [sheet orderOut:self];
    TLMPapersizeController *psc = context;
    [psc autorelease];
    if (TLMPapersizeChanged == returnCode && [psc paperSize]) {
        TLMPapersizeOperation *op = [[TLMPapersizeOperation alloc] initWithPapersize:[psc paperSize]];
        [self _addOperation:op selector:@selector(_handlePapersizeFinishedNotification:)];
        [op release];             
        TLMLog(__func__, @"Setting paper size to %@", [psc paperSize]);
    }
    else if (nil == [psc paperSize]) {
        TLMLog(__func__, @"No paper size from %@", psc);
    }

}

- (void)_handleAutobackupOptionFinishedNotification:(NSNotification *)aNote
{
    TLMOptionOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    if ([op failed]) {
        TLMLog(__func__, @"Autobackup change failed.  Error was: %@", [op errorMessages]);
    }
}

- (void)autobackupSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)context
{
    [sheet orderOut:self];
    TLMAutobackupController *abc = context;
    [abc autorelease];
    if (returnCode & TLMAutobackupChanged) {
        
        TLMOptionOperation *change = nil;
        if ((returnCode & TLMAutobackupIncreased) || (returnCode & TLMAutobackupDecreased)) {
            change = [[TLMOptionOperation alloc] initWithKey:@"autobackup" value:[NSString stringWithFormat:@"%ld", (long)[abc backupCount]]];
            [self _addOperation:change selector:@selector(_handleAutobackupOptionFinishedNotification:)];
            [change autorelease];         
            TLMLog(__func__, @"Setting autobackup to %ld", (long)[abc backupCount]);
        }
        
        if (returnCode & TLMAutobackupPrune) {
            // if autobackup is set to zero, --clean needs an explicit N argument or it returns an error
            TLMBackupOperation *cleaner;
            cleaner = returnCode & TLMAutobackupDisabled ? [TLMBackupOperation newDeepCleanOperation] : [TLMBackupOperation newCleanOperation];
            
            if (change)
                [cleaner addDependency:change];
            [self _addOperation:cleaner selector:@selector(_handleAutobackupOptionFinishedNotification:)];
            [cleaner release];
            TLMLog(__func__, @"Pruning autobackup sets to the last %ld", (long)[abc backupCount]);
        }
    }
}

- (void)_handleListFinishedNotification:(NSNotification *)aNote
{
    TLMListOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    [_packageListDataSource setPackageNodes:[op packageNodes]];
    [_packageListDataSource setRefreshing:NO];
    
    NSString *statusString = nil;
    
    if ([op isCancelled])
        statusString = NSLocalizedString(@"Listing Cancelled", @"main window status string");
    else if ([op failed])
        statusString = NSLocalizedString(@"Listing Failed", @"main window status string");
    
    [self _displayStatusString:statusString dataSource:_packageListDataSource];
    [_packageListDataSource setLastUpdateURL:[op updateURL]];
    [self _updateURLView];
}

- (void)_refreshFullPackageListFromLocation:(NSURL *)location offline:(BOOL)offline
{
    [self _displayStatusString:nil dataSource:_packageListDataSource];
    // disable refresh action for this view
    [_packageListDataSource setRefreshing:YES];
    TLMListOperation *op = [[TLMListOperation alloc] initWithLocation:location offline:offline];
    [self _addOperation:op selector:@selector(_handleListFinishedNotification:)];
    [op release];
    TLMLog(__func__, @"Refreshing list of all packages%C", 0x2026);           
}

- (void)_handleInstallFinishedNotification:(NSNotification *)aNote
{
    TLMInstallOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    
    // ignore operations that failed or were explicitly cancelled
    if ([op failed]) {
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"Install failed.", @"alert title")];
        [alert setInformativeText:NSLocalizedString(@"The install process appears to have failed.  Please check the log display below for details.", @"alert message text")];
        [alert beginSheetModalForWindow:[self window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];                    
    }
    else if ([op isCancelled] == NO) {
        
        // This is slow, but if a package installed other dependencies, we have no way of manually removing from the list.  We also need to ensure that the same mirror is used, so results are consistent.
        [self _refreshFullPackageListFromLocation:[op updateURL] offline:NO];
        
        // this is always displayed, so should always be updated as well
        [self _refreshUpdatedPackageListFromLocation:[op updateURL]];
    }    
}

- (void)_installPackagesWithNames:(NSArray *)packageNames reinstall:(BOOL)reinstall
{
    NSURL *currentURL = [self _lastUpdateURL];
    TLMInstallOperation *op = [[TLMInstallOperation alloc] initWithPackageNames:packageNames location:currentURL reinstall:reinstall];
    [self _addOperation:op selector:@selector(_handleInstallFinishedNotification:)];
    TLMLog(__func__, @"Beginning install of %@\nfrom %@", packageNames, [currentURL absoluteString]);   
}

- (void)_handleRemoveFinishedNotification:(NSNotification *)aNote
{
    TLMRemoveOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    
    // ignore operations that failed or were explicitly cancelled
    if ([op failed]) {
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"Removal failed.", @"alert title")];
        [alert setInformativeText:NSLocalizedString(@"The removal process appears to have failed.  Please check the log display below for details.", @"alert message text")];
        [alert beginSheetModalForWindow:[self window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];                    
    }
    else if ([op isCancelled] == NO) {
        
        // This is slow, but if a package removed other dependencies, we have no way of manually removing from the list.  We also need to ensure that the same mirror is used, so results are consistent.
        [self _refreshFullPackageListFromLocation:[_packageListDataSource lastUpdateURL] offline:NO];
        
        // this is always displayed, so should always be updated as well
        [self _refreshUpdatedPackageListFromLocation:[_packageListDataSource lastUpdateURL]];
    }    
}

- (void)_handleNetInstallFinishedNotification:(NSNotification *)aNote
{
    [self _handleInstallFinishedNotification:aNote];
}
    
- (void)netInstall
{
    NSParameterAssert([_currentListDataSource isEqual:_installDataSource]);
    NSString *profile = [_installDataSource currentProfile];
    TLMNetInstallOperation *op = [[TLMNetInstallOperation alloc] initWithProfile:profile location:[self _lastUpdateURL]];
    [self _addOperation:op selector:@selector(_handleNetInstallFinishedNotification:)];
    [op release];
}

#pragma mark Alert callbacks

- (void)infrastructureAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;
{
    if (NSAlertFirstButtonReturn == returnCode) {
        [self _updateAllPackages];
    }
}

- (void)disasterAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)context
{
    if (NSAlertFirstButtonReturn == returnCode)
        [[NSApp delegate] openDisasterRecoveryPage:nil];
    else
        TLMLog(__func__, @"User chose not to open %@ after failure", @"http://tug.org/texlive/tlmgr.html");
}

- (void)versionAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)unused
{
    [self _refreshUpdatedPackageListFromLocation:[self _lastUpdateURL]];
}

- (void)cancelWarningSheetDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    if (NSAlertSecondButtonReturn == returnCode)
        [self _cancelAllOperations];
    else
        TLMLog(__func__, @"User decided not to cancel %@", [TLMReadWriteOperationQueue defaultQueue]);
}

- (void)updateAllAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;
{
    if (NSAlertFirstButtonReturn == returnCode) {
        [self _updateAllPackages];
    }    
}

- (void)reinstallAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    if (NSAlertFirstButtonReturn == returnCode)
        [self _installPackagesWithNames:[(NSArray *)contextInfo autorelease] reinstall:YES];
}

#pragma mark Actions

- (IBAction)changePapersize:(id)sender;
{
    // sheet asserts and runs tlmgr, so make sure it exists
    if ([self _checkCommandPathAndWarn:YES]) {
        TLMPapersizeController *psc = [TLMPapersizeController new];
        [NSApp beginSheet:[psc window] 
           modalForWindow:[self window] 
            modalDelegate:self 
           didEndSelector:@selector(papersizeSheetDidEnd:returnCode:contextInfo:) 
              contextInfo:psc];
    }
}

- (IBAction)changeAutobackup:(id)sender;
{
    // sheet asserts and runs tlmgr, so make sure it exists
    if ([self _checkCommandPathAndWarn:YES]) {
        TLMAutobackupController *abc = [TLMAutobackupController new];
        [NSApp beginSheet:[abc window] 
           modalForWindow:[self window] 
            modalDelegate:self 
           didEndSelector:@selector(autobackupSheetDidEnd:returnCode:contextInfo:) 
              contextInfo:abc];
    }
}

- (IBAction)cancelAllOperations:(id)sender;
{
    if ([[TLMReadWriteOperationQueue defaultQueue] isWriting]) {
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"An installation is running!", @"alert title")];
        [alert setAlertStyle:NSCriticalAlertStyle];
        [alert setInformativeText:NSLocalizedString(@"If you cancel the installation process, it may leave your TeX installation in an unknown state.  You can ignore this warning and cancel anyway, or keep waiting until the installation finishes.", @"alert message text")];
        [alert addButtonWithTitle:NSLocalizedString(@"Keep Waiting", @"button title")];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel Anyway", @"button title")];
        [alert beginSheetModalForWindow:[self window]
                          modalDelegate:self
                         didEndSelector:@selector(cancelWarningSheetDidEnd:returnCode:contextInfo:)
                            contextInfo:NULL];
    }
    else {
        [self _cancelAllOperations];
    }
}

- (void)updateInfrastructure:(id)sender;
{
    TLMLog(__func__, @"Beginning user-requested infrastructure update%C", 0x2026);
    _updateInfrastructure = YES;
    [self _updateAllPackages];
}

- (void)updateInfrastructureFromCriticalRepository:(id)sender
{
    TLMLog(__func__, @"Beginning user-requested infrastructure update from tlcritical repo%C", 0x2026);
    _updateInfrastructure = YES;
    NSURL *repo = [NSURL URLWithString:[[NSUserDefaults standardUserDefaults] objectForKey:TLMTLCriticalRepository]];
    [self _updateAllPackagesFromRepository:repo];
}

#pragma mark API

- (void)refreshFullPackageList
{
    NSURL *serverURL = [[TLMPreferenceController sharedPreferenceController] validServerURL];
    
    /* 
     If the network is not available, read the local package db so that show info still works.
     Note that all packages thus shown will be installed, so presumably forced updates will fail
     and removal may succeed.  Avoid doing special case menu validation until it seems necessary.
     */
    CFNetDiagnosticRef diagnostic = CFNetDiagnosticCreateWithURL(NULL, (CFURLRef)serverURL);
    [(id)diagnostic autorelease];
    CFStringRef desc = NULL;
    if (diagnostic && kCFNetDiagnosticConnectionDown == CFNetDiagnosticCopyNetworkStatusPassively(diagnostic, &desc)) {
        // this is basically a dummy URL that we pass through in offline mode
        serverURL = [[TLMPreferenceController sharedPreferenceController] installDirectory];
        TLMLog(__func__, @"Network connection is down (%@).  Trying local install database %@%C", desc, serverURL, 0x2026);
        [(id)desc autorelease];
        [self _refreshFullPackageListFromLocation:serverURL offline:YES];
        [self _displayStatusString:NSLocalizedString(@"Network is unavailable", @"") dataSource:_updateListDataSource];
    }
    else {
        [self _refreshFullPackageListFromLocation:serverURL offline:NO];
    }
}

- (void)refreshUpdatedPackageList
{
    [self _refreshUpdatedPackageListFromLocation:[[TLMPreferenceController sharedPreferenceController] validServerURL]];
}

- (void)updateAllPackages;
{
    NSAlert *alert = [[NSAlert new] autorelease];
    NSUInteger size = 0;
    for (TLMPackage *pkg in [_updateListDataSource allPackages])
        size += [[pkg size] unsignedIntegerValue];
    
    [alert setMessageText:NSLocalizedString(@"Update all packages?", @"alert title")];
    // size may not be correct for _updateInfrastructure, but tlmgr may remove stuff also...so leave it as-is
    NSMutableString *informativeText = [NSMutableString string];
    [informativeText appendString:NSLocalizedString(@"This will install all available updates.", @"update alert message text part 1")];
    
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"(willBeRemoved == YES)"];
    NSUInteger removeCount = [[[_updateListDataSource allPackages] filteredArrayUsingPredicate:predicate] count];
    if ([[TLMPreferenceController sharedPreferenceController] autoRemove] && removeCount)
        [informativeText appendFormat:@"  %@", NSLocalizedString(@"Packages that no longer exist on the server will be removed.", @"update alert message text part 2 (optional)")];
    
    predicate = [NSPredicate predicateWithFormat:@"(isInstalled == NO)"];
    NSUInteger installCount = [[[_updateListDataSource allPackages] filteredArrayUsingPredicate:predicate] count];
    if ([[TLMPreferenceController sharedPreferenceController] autoInstall] && installCount)
        [informativeText appendFormat:@"  %@", NSLocalizedString(@"New packages will be installed.", @"update alert message text part 3 (optional)")];
    
    TLMSizeFormatter *sizeFormatter = [[TLMSizeFormatter new] autorelease];
    NSString *sizeString = [sizeFormatter stringForObjectValue:[NSNumber numberWithUnsignedInteger:size]];
    [informativeText appendFormat:NSLocalizedString(@"  Total download size will be %@.", @"partial alert text, with double space in front, only used with tlmgr2"), sizeString];
    
    [alert setInformativeText:informativeText];
    [alert addButtonWithTitle:NSLocalizedString(@"Update", @"button title")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"button title")];
    [alert beginSheetModalForWindow:[self window] 
                      modalDelegate:self 
                     didEndSelector:@selector(updateAllAlertDidEnd:returnCode:contextInfo:) 
                        contextInfo:NULL]; 
}    

- (void)updatePackagesWithNames:(NSArray *)packageNames;
{
    NSURL *currentURL = [self _lastUpdateURL];
    TLMUpdateOperation *op = [[TLMUpdateOperation alloc] initWithPackageNames:packageNames location:currentURL];
    [self _addOperation:op selector:@selector(_handleUpdateFinishedNotification:)];
    [op release];
    TLMLog(__func__, @"Beginning update of %@\nfrom %@", packageNames, [currentURL absoluteString]);
}

// reinstall requires additional option to tlmgr
- (void)installPackagesWithNames:(NSArray *)packageNames reinstall:(BOOL)reinstall
{    
    if (reinstall) {
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"Reinstall packages?", @"alert title")];
        [alert setInformativeText:NSLocalizedString(@"Some of the packages you have selected are already installed.  Would you like to reinstall them?", @"alert message text")];
        [alert addButtonWithTitle:NSLocalizedString(@"Reinstall", @"button title")];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"button title")];
        [alert beginSheetModalForWindow:[self window]
                          modalDelegate:self
                         didEndSelector:@selector(reinstallAlertDidEnd:returnCode:contextInfo:)
                            contextInfo:[packageNames copy]];
    }
    else {
        [self _installPackagesWithNames:packageNames reinstall:NO]; 
    }    
}

- (void)removePackagesWithNames:(NSArray *)packageNames force:(BOOL)force
{   
    // Some idiot could try to wipe out tlmgr itself, so let's try to prevent that...
    // NB: we can have the architecture appended to the package name, so use beginswith.
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF beginswith 'texlive.infra'"];
    NSArray *packages = [packageNames filteredArrayUsingPredicate:predicate];
    
    if ([packages count]) {
        // log for debugging, then display an alert so the user has some idea of what's going on...
        TLMLog(__func__, @"Tried to remove infrastructure packages: %@", packages);
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"Some of these packages cannot be removed.", @"alert title")];
        [alert setInformativeText:NSLocalizedString(@"You are attempting to remove critical parts of the underlying TeX Live infrastructure, and I won't help you do that.", @"alert message text")];
        [alert beginSheetModalForWindow:[self window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
    }
    else {
        TLMRemoveOperation *op = [[TLMRemoveOperation alloc] initWithPackageNames:packageNames force:force];
        [self _addOperation:op selector:@selector(_handleRemoveFinishedNotification:)];
        [op release];
        TLMLog(__func__, @"Beginning removal of\n%@", packageNames); 
    }
}

@end
