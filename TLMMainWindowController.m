//
//  TLMMainWindowController.m
//  TeX Live Utility
//
//  Created by Adam Maxwell on 12/6/08.
/*
 This software is Copyright (c) 2008-2011
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
#import "TLMBackupDataSource.h"

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
#import "TLMBackupListOperation.h"
#import "TLMLoadDatabaseOperation.h"

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
#import "TLMLaunchAgentController.h"
#import "TLMEnvironment.h"
#import "TLMURLFormatter.h"
#import "TLMAddressTextField.h"

#import "TLMDatabase.h"
#import "TLMDatabasePackage.h"
#import "TLMMirrorController.h"

@interface TLMMainWindowController (Private)
// only declare here if reorganizing the implementation isn't practical
- (void)_refreshCurrentDataSourceIfNeeded;
- (void)_refreshLocalDatabase;
- (void)_displayStatusString:(NSString *)statusString dataSource:(id <TLMListDataSource>)dataSource;
@end


static char _TLMOperationQueueOperationContext;

#define DB_LOAD_STATUS_STRING      ([NSString stringWithFormat:@"%@%C", NSLocalizedString(@"Loading Database", @"status message"), 0x2026])
#define URL_VALIDATE_STATUS_STRING ([NSString stringWithFormat:@"%@%C", NSLocalizedString(@"Validating Server", @"status message"), 0x2026])

@implementation TLMMainWindowController

@synthesize _progressIndicator;
@synthesize _progressBar;
@synthesize _URLField;
@synthesize _packageListDataSource;
@synthesize _tabView;
@synthesize _updateListDataSource;
@synthesize _installDataSource;
@synthesize infrastructureNeedsUpdate = _updateInfrastructure;
@synthesize _backupDataSource;
@synthesize serverURL = _serverURL;

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
    
    [_URLField release];
    [_serverURL release];
        
    [_progressIndicator release];
    [_progressBar release];
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
    [_tabView addTabNamed:NSLocalizedString(@"Updates", @"tab title") withView:[[_updateListDataSource tableView]  enclosingScrollView]];
    [_tabView addTabNamed:NSLocalizedString(@"Packages", @"tab title") withView:[[_packageListDataSource outlineView] enclosingScrollView]];
    [_tabView addTabNamed:NSLocalizedString(@"Backups", @"tab title") withView:[[_backupDataSource outlineView] enclosingScrollView]];
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:TLMEnableNetInstall])
        [_tabView addTabNamed:NSLocalizedString(@"Install", @"tab title") withView:[[_installDataSource outlineView] enclosingScrollView]];
    
    // 10.5 release notes say this is enabled by default, but it returns NO
    [_progressIndicator setUsesThreadedAnimation:YES];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_startProgressBar:)
                                                 name:TLMLogTotalProgressNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_updateProgressBar:)
                                                 name:TLMLogDidIncrementProgressNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_stopProgressBar:)
                                                 name:TLMLogFinishedProgressNotification
                                               object:nil];
    
    TLMURLFormatter *fmt = [[TLMURLFormatter new] autorelease];
    [fmt setReturnsURL:YES];
    [_URLField setFormatter:fmt];    
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
    /*
     - calling [self _stopProgressBar:nil] here will keep the bar from being displayed during the first item of a download
     - use a hack from BibDesk: progress bars may not work correctly after the first time they're used, due to an AppKit bug
     */
    NSProgressIndicator *pb = [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:[self _progressBar]]];
    [[[self _progressBar] superview] replaceSubview:[self _progressBar] with:pb];
    [self set_progressBar:pb];
    // we always have an integral number of bytes >> 1, so set a fake value here so it draws immediately
    const double initialValue = 1.0;
    [[self _progressBar] setMinValue:0.0];
    [[self _progressBar] setMaxValue:([[[aNote userInfo] objectForKey:TLMLogSize] doubleValue] + initialValue)];
    [[self _progressBar] setDoubleValue:initialValue];
    [[self _progressBar] setHidden:NO];
    [[self _progressBar] display];
}

- (void)_updateProgressBar:(NSNotification *)aNote
{
    [[self _progressBar] incrementBy:[[[aNote userInfo] objectForKey:TLMLogSize] doubleValue]];
    /*
     Formerly called -[[self _progressBar] display] here.  That was killing performance after I
     added progress updates to the infra operation; drawing basically stalled, since the
     window had to synchronize too frequently.  All this to say...don't do that again.
     */
    CGFloat p = [[self _progressBar] doubleValue] / [[self _progressBar] maxValue];
    [NSApp setApplicationIconImage:[TLMProgressIndicatorCell applicationIconBadgedWithProgress:p]];
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    // checkbox in IB doesn't work?
    [[[self window] toolbar] setAutosavesConfiguration:YES];   
}

- (void)showWindow:(id)sender
{
    [super showWindow:sender];
    
    [[[NSApp delegate] logWindowController] setDockingDelegate:self];

    static BOOL __windowDidShow = NO;
    if (__windowDidShow) return;
    __windowDidShow = YES;
    
    // set the dirty bit on all datasources
    [_updateListDataSource setNeedsUpdate:YES];
    [_packageListDataSource setNeedsUpdate:YES];
    [_backupDataSource setNeedsUpdate:YES];
    [_installDataSource setNeedsUpdate:YES];
    
    // do this after the window loads, so something is visible right away
    if ([[[TLMEnvironment currentEnvironment] defaultServerURL] isMultiplexer])
        [self _displayStatusString:URL_VALIDATE_STATUS_STRING dataSource:_updateListDataSource];
    _serverURL = [[[TLMEnvironment currentEnvironment] validServerURL] copy];
    if ([[[_updateListDataSource statusWindow] statusString] isEqualToString:URL_VALIDATE_STATUS_STRING])
        [self _displayStatusString:nil dataSource:_updateListDataSource];
    
    // !!! end up with a bad environment if this is the multiplexer, and the UI gets out of sync
    if (nil == _serverURL)
        _serverURL = [[[TLMEnvironment currentEnvironment] defaultServerURL] copy];
    
    if ([_serverURL isMultiplexer]) {
        TLMLog(__func__, @"Still have multiplexer URL after setup.  This is not good.");
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"Unable to find a valid update server", @"alert title")];
        [alert setInformativeText:NSLocalizedString(@"Either a network problem exists or the TeX Live version on the server does not match.  If this problem persists on further attempts, you may need to try a different mirror.", @"alert text")];
        [alert beginSheetModalForWindow:[self window]
                          modalDelegate:nil
                         didEndSelector:NULL
                            contextInfo:NULL];
    }
    
    [_URLField setStringValue:[[self serverURL] absoluteString]];
    
    // I don't like having this selected and highlighted at launch, for some reason
    [[_URLField currentEditor] setSelectedRange:NSMakeRange(0, 0)];
    [[self window] makeFirstResponder:nil];
    
    // for info window; TL 2011 and later only
    [self _refreshLocalDatabase];
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
            
            // change address field to cancel
            [_URLField setButtonImage:[NSImage imageNamed:NSImageNameStopProgressFreestandingTemplate]];
            [_URLField setButtonTarget:self];
            [_URLField setButtonAction:@selector(cancelAllOperations:)];
        }
        // previous count != 0, so spinner is currently animating
        else if (0 == newCount) {
            [_progressIndicator stopAnimation:self];
            
            // change address field to refresh
            [_URLField setButtonImage:[NSImage imageNamed:NSImageNameRefreshFreestandingTemplate]];
            [_URLField setButtonTarget:self];
            [_URLField setButtonAction:@selector(refresh:)];
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

- (id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)client
{
    if (client == _URLField) {
        static TLMMirrorFieldEditor *editor = nil;
        if (nil == editor)
            editor = [[TLMMirrorFieldEditor alloc] init];
        return editor;
    }
    return nil;
}

- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)frameSize;
{
    const CGFloat dy = NSHeight([sender frame]) - frameSize.height;
    const CGFloat dx = NSWidth([sender frame]) - frameSize.width;
    NSWindow *logWindow = [[[NSApp delegate] logWindowController] window];
    if ([[[self window] childWindows] containsObject:logWindow]) {
        
        NSPoint logWindowOrigin = [logWindow frame].origin;
        switch (_dockedEdge) {
            case TLMDockedEdgeBottom:
                logWindowOrigin.y += dy;
                break;
            case TLMDockedEdgeRight:
                logWindowOrigin.x -= dx;
            default:
                break;
        }
        [logWindow setFrameOrigin:logWindowOrigin];
    }
    return frameSize;
}

- (void)dockableWindowWillClose:(NSWindow *)window;
{
    _dockedEdge = TLMDockedEdgeNone;
    [[self window] removeChildWindow:window];
    TLMLog(__func__, @"Undocking log window");
}

- (void)dockableWindowGeometryDidChange:(NSWindow *)window;
{
    // !!! early return on hidden default
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"TLMDisableLogWindowDocking"])
        return;
    
    NSRect logWindowFrame = [window frame];
    const NSRect mainWindowFrame = [[self window] frame];
    const CGFloat tolerance = 10.0;
    const CGFloat dx = NSMaxX(mainWindowFrame) - NSMinX(logWindowFrame);
    const CGFloat dy = NSMinY(mainWindowFrame) - NSMaxY(logWindowFrame);
    
    /*
     Allow docking anytime the log window's midpoint is within the main window's border.
     Using the endpoint is fiddly if you're trying to line up the left edge (when docking
     on the bottom) or top (when docking on the right), since it keeps undocking if you're
     off by a point.
     */
    
    if (ABS(dx) <= tolerance && NSMidY(logWindowFrame) >= NSMinY(mainWindowFrame) && NSMidY(logWindowFrame) <= NSMaxY(mainWindowFrame)) {
        // dock on right side of main window
        
        if (TLMDockedEdgeNone == _dockedEdge) {
            NSParameterAssert([[[self window] childWindows] containsObject:window] == NO);
            // !!! reentrancy: set before changing the frame
            _dockedEdge = TLMDockedEdgeRight;
            [[self window] addChildWindow:window ordered:NSWindowBelow];

            TLMLog(__func__, @"Docking log window on right of main window");
        }
        
        // adjust even if already docked, so we get a consistent distance
        logWindowFrame.origin.x = NSMaxX(mainWindowFrame) + 1;
        [window setFrameOrigin:logWindowFrame.origin];

    }
    else if (ABS(dy) <= tolerance && NSMidX(logWindowFrame) >= NSMinX(mainWindowFrame) && NSMidX(logWindowFrame) <= NSMaxX(mainWindowFrame)) {
        // dock on bottom of main window
        
        if (TLMDockedEdgeNone == _dockedEdge) {
            NSParameterAssert([[[self window] childWindows] containsObject:window] == NO);
            // !!! reentrancy: set before changing the frame
            _dockedEdge = TLMDockedEdgeBottom;
            [[self window] addChildWindow:window ordered:NSWindowBelow];

            TLMLog(__func__, @"Docking log window below main window");
        }

        // adjust even if already docked, so we get a consistent distance
        logWindowFrame.origin.y = NSMinY(mainWindowFrame) - NSHeight(logWindowFrame) - 1;
        [window setFrameOrigin:logWindowFrame.origin];

    }
    else if (TLMDockedEdgeNone != _dockedEdge) {
        NSParameterAssert([[[self window] childWindows] containsObject:window]);
        // already a child window, but moving away
        _dockedEdge = TLMDockedEdgeNone;
        [[self window] removeChildWindow:window];
        TLMLog(__func__, @"Undocking log window");
    }
}

#pragma mark Interface updates

- (void)setServerURL:(NSURL *)aURL
{
    NSParameterAssert(aURL);
    [_serverURL autorelease];
    _serverURL = [aURL copy];
    [_URLField setStringValue:[aURL absoluteString]];
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
    TLMLogServerSync();
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
    if ([next isEqual:_updateListDataSource] || [next isEqual:_packageListDataSource] || [next isEqual:_backupDataSource] || [next isEqual:_installDataSource])
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
    NSParameterAssert([next isEqual:_backupDataSource] == NO);
    NSParameterAssert([next isEqual:_installDataSource] == NO);
    
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
            [[_currentListDataSource statusWindow] fadeIn];
            [self _refreshCurrentDataSourceIfNeeded];
            if ([[_updateListDataSource allPackages] count])
                [_updateListDataSource search:nil];
            break;
        case 1:
            
            [self _insertDataSourceInResponderChain:_packageListDataSource];   
            _currentListDataSource = _packageListDataSource;
            [[_currentListDataSource statusWindow] fadeIn];
            
            [self _refreshCurrentDataSourceIfNeeded];

            if ([[_packageListDataSource packageNodes] count])
                [_packageListDataSource search:nil];

            break;
        case 2:
            
            [self _insertDataSourceInResponderChain:_backupDataSource];
            _currentListDataSource = _backupDataSource;
            [[_currentListDataSource statusWindow] fadeIn];
            
            [self _refreshCurrentDataSourceIfNeeded];

            if ([[_backupDataSource backupNodes] count])
                [_backupDataSource search:nil];
            
            break;            
        case 3:
            
            [self _insertDataSourceInResponderChain:_installDataSource];
            _currentListDataSource = _installDataSource;
            [[_currentListDataSource statusWindow] fadeIn];
            
            [self _refreshCurrentDataSourceIfNeeded];

            break;
        default:
            break;
    }
}

- (BOOL)control:(NSControl *)control didFailToFormatString:(NSString *)string errorDescription:(NSString *)error
{
    if (control == _URLField) {
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"Invalid URL", @"alert title")];
        [alert setInformativeText:error];
        [alert beginSheetModalForWindow:[self window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
    }
    return NO;
}

- (NSArray *)control:(NSControl *)control textView:(NSTextView *)textView completions:(NSArray *)words forPartialWordRange:(NSRange)charRange indexOfSelectedItem:(NSInteger *)index;
{
    if (index) *index = 0;
    NSFormatter *fmt = [[control cell] formatter];
    NSMutableArray *candidates = [[[[NSApp delegate] mirrorController] mirrorsMatchingSearchString:[textView string]] mutableCopy];
    if (fmt) {
        
        NSUInteger idx = [candidates count];
        while (idx--) {
            id ignored;
            if ([fmt getObjectValue:&ignored forString:[candidates objectAtIndex:idx] errorDescription:NULL] == NO)
                [candidates removeObjectAtIndex:idx];
        }
    }
        
    return [candidates autorelease];
}

- (NSRange)control:(NSControl *)control textView:(NSTextView *)textView rangeForUserCompletion:(NSRange)charRange;
{
    return NSMakeRange(0, [[textView string] length]);
}

- (BOOL)control:(NSControl *)control textViewShouldAutoComplete:(NSTextView *)textView { return control == _URLField; }

#pragma mark -
#pragma mark Operations

- (BOOL)_checkCommandPathAndWarn:(BOOL)displayWarning
{
    NSString *cmdPath = [[TLMEnvironment currentEnvironment] tlmgrAbsolutePath];
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

- (void)_addOperation:(TLMOperation *)op selector:(SEL)sel setRefreshingForDataSource:(id)dataSource
{
    // avoid the tlmgr path check when installing
    if (op && ([_currentListDataSource isEqual:_installDataSource] || [self _checkCommandPathAndWarn:YES])) {
        if (NULL != sel)
            [[NSNotificationCenter defaultCenter] addObserver:self selector:sel name:TLMOperationFinishedNotification object:op];
        [[TLMReadWriteOperationQueue defaultQueue] addOperation:op];
    }
    else if ([dataSource respondsToSelector:@selector(setRefreshing:)]) {
        // operation ending handlers aren't called, so this will never get reset
        [dataSource setRefreshing:NO];
    }

}

/*
 Call before a write operation (update/install), just in case the environment has changed
 since the last time updates were listed.  This avoids downloading the wrong disaster
 recovery script and running it against a different TL version (which the current script
 handles correctly, so this is just an extra precaution).  Note that changing mirrors
 should not be an issue since we always use the last (already validated) mirror.  However,
 changing the the tlmgr path or TeX Dist in system prefs can cause problems.
 */
- (BOOL)_isCorrectDatabaseVersionAtURL:(NSURL *)aURL
{
    TLMLog(__func__, @"Checking database version in case preferences have been changed%C", 0x2026);
    // should be cached, unless the user has screwed up (and that's the case we're trying to catch)
    TLMDatabase *db = [TLMDatabase databaseForMirrorURL:aURL];
    const TLMDatabaseYear year = [[TLMEnvironment currentEnvironment] texliveYear];
    if ([db texliveYear] != year) {
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"Mirror has a different TeX Live version", @"alert title")];
        [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"The mirror at %@ has TeX Live %d, but you have TeX Live %d installed.  You need to adjust your preferences in order to continue.", @"alert text, two integer format specifiers"), [aURL absoluteString], [db texliveYear], year]];
        [alert beginSheetModalForWindow:[self window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
        TLMLog(__func__, @"Well, this is not going to work:  %@ has TeX Live %d, and the installed version is TeX Live %d", [aURL absoluteString], [db texliveYear], year);
        return NO;
    }
    return YES;
}

- (void)_updateAllPackagesFromRepository:(NSURL *)repository
{
    // sanity check in case the user switched the environment after getting an update listing
    if ([self _isCorrectDatabaseVersionAtURL:repository]) {
        TLMUpdateOperation *op = nil;
        if (_updateInfrastructure) {
            op = [[TLMInfraUpdateOperation alloc] initWithLocation:repository];
            TLMLog(__func__, @"Beginning infrastructure update from %@", [repository absoluteString]);
            [self _addOperation:op selector:@selector(_handleInfrastructureUpdateFinishedNotification:) setRefreshingForDataSource:nil];
        }
        else {
            op = [[TLMUpdateOperation alloc] initWithPackageNames:nil location:repository];
            TLMLog(__func__, @"Beginning update of all packages from %@", [repository absoluteString]);
            [self _addOperation:op selector:@selector(_handleUpdateFinishedNotification:) setRefreshingForDataSource:nil];
        }
        [op release];
    }
}

- (void)_updateAllPackages
{
    [self _updateAllPackagesFromRepository:[self serverURL]];
}

static NSDictionary * __TLMCopyVersionsForPackageNames(NSArray *packageNames)
{
    NSMutableDictionary *versions = [NSMutableDictionary new];
    for (NSString *name in packageNames) {
        TLMTask *task = [[TLMTask new] autorelease];
        [task setLaunchPath:[[TLMEnvironment currentEnvironment] tlmgrAbsolutePath]];
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
     other infrastructure package is 'tlperl.win32', which we probably won't see.
     
     Note: a slow-to-update mirror may have a stale version, so check needsUpdate as well.
     */
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"((name == 'tlperl.win32' OR name BEGINSWITH 'texlive.infra')) AND (needsUpdate == YES)"];
    NSArray *criticalPackages = [allPackages filteredArrayUsingPredicate:predicate];
    
    if ([criticalPackages count]) {
        [_previousInfrastructureVersions release];
        _previousInfrastructureVersions = __TLMCopyVersionsForPackageNames([criticalPackages valueForKey:@"name"]);
        _updateInfrastructure = YES;
        
        // only allow updating the infra packages
        [_updateListDataSource setPackageFilter:predicate];
        
        // log for debugging, then display an alert so the user has some idea of what's going on...
        TLMLog(__func__, @"Critical updates detected: %@", [criticalPackages valueForKey:@"name"]);
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
        [_updateListDataSource setPackageFilter:nil];
    }
    
    [_updateListDataSource setAllPackages:allPackages];
    [_updateListDataSource setRefreshing:NO];
    [_updateListDataSource setNeedsUpdate:NO];
    
    NSString *statusString = nil;
    
    if ([op isCancelled])
        statusString = NSLocalizedString(@"Listing Cancelled", @"main window status string");
    else if ([op failed])
        statusString = NSLocalizedString(@"Listing Failed", @"main window status string");
    else if ([allPackages count] == 0)
        statusString = NSLocalizedString(@"No Updates Available", @"main window status string");
    
    [self _displayStatusString:statusString dataSource:_updateListDataSource];
}

- (void)_handleRefreshLocalDatabaseFinishedNotification:(NSNotification *)aNote
{
    TLMLoadDatabaseOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    // only clear this status message, which is intended to be ephemeral
    if ([[[_updateListDataSource statusWindow] statusString] isEqualToString:DB_LOAD_STATUS_STRING])
        [self _displayStatusString:nil dataSource:_updateListDataSource];
}

- (void)_refreshLocalDatabase
{
    if ([[TLMEnvironment currentEnvironment] tlmgrSupportsDumpTlpdb]) {
        // pick a datasource to use here; doesn't matter which, as long as it's the same in the callback
        [self _displayStatusString:DB_LOAD_STATUS_STRING dataSource:_updateListDataSource];
        TLMLog(__func__, @"Updating local package database");
        NSURL *mirror = [[TLMEnvironment currentEnvironment] defaultServerURL];
        TLMLoadDatabaseOperation *op = [[TLMLoadDatabaseOperation alloc] initWithLocation:mirror offline:YES];
        [self _addOperation:op selector:@selector(_handleRefreshLocalDatabaseFinishedNotification:) setRefreshingForDataSource:nil];
        [op release];
    }   
}

- (void)_refreshUpdatedPackageListFromLocation:(NSURL *)location
{
    if ([[TLMDatabase databaseForMirrorURL:location] texliveYear] != TLMDatabaseUnknownYear) {
        [self _displayStatusString:nil dataSource:_updateListDataSource];
        // disable refresh action for this view
        [_updateListDataSource setRefreshing:YES];
        TLMListUpdatesOperation *op = [[TLMListUpdatesOperation alloc] initWithLocation:location];
        [self _addOperation:op selector:@selector(_handleListUpdatesFinishedNotification:) setRefreshingForDataSource:_updateListDataSource];
        [op release];
        TLMLog(__func__, @"Refreshing list of updated packages%C", 0x2026);
    }
    else {
        // happens when network is down; this can be a 10-12 minute timeout with TL 2011
        TLMLog(__func__, @"Not updating package list, since the mirror database version is unknown");
    }
}

- (void)_handleUpdateFinishedNotification:(NSNotification *)aNote
{
    NSParameterAssert([NSThread isMainThread]);
    NSParameterAssert(NO == _updateInfrastructure);
    
    TLMUpdateOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    
    // ignore operations that failed or were explicitly cancelled
    if ([op failed]) {
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"The update failed.", @"alert title")];
        [alert setInformativeText:NSLocalizedString(@"The update process appears to have failed. Would you like to show the log now or ignore this warning?", @"alert message text")];
        [alert addButtonWithTitle:NSLocalizedString(@"Show Log", @"button title")];
        [alert addButtonWithTitle:NSLocalizedString(@"Ignore", @"button title")];
        [alert beginSheetModalForWindow:[self window] 
                          modalDelegate:self 
                         didEndSelector:@selector(alertForLogWindowDidEnd:returnCode:contextInfo:) 
                            contextInfo:NULL];                
    }
    else if ([op isCancelled] == NO) {
            
        [self _refreshLocalDatabase];
        
        /*
         Could remove this to ensure that the "Update Succeeded" message is displayed longer,
         but it's needed in case a package update also updates or installs other dependencies.
         However, this notification is not posted for installs, so I now think that's not a
         problem.
        [_updateListDataSource setNeedsUpdate:YES];
         */

        [_packageListDataSource setNeedsUpdate:YES];
        [_backupDataSource setNeedsUpdate:YES];
        
        [self setServerURL:[op updateURL]];
        
        [self _refreshCurrentDataSourceIfNeeded];
        [self _displayStatusString:NSLocalizedString(@"Update Succeeded", @"status message") dataSource:_updateListDataSource];

    }
}

- (void)_handleInfrastructureUpdateFinishedNotification:(NSNotification *)aNote
{
    NSParameterAssert([NSThread isMainThread]);
    NSParameterAssert(_updateInfrastructure);
    
    TLMUpdateOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    
    // ignore operations that failed or were explicitly cancelled
    if ([op failed]) {
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"The update failed.", @"alert title")];
        [alert setInformativeText:NSLocalizedString(@"The update process appears to have failed. Would you like to show the log now or ignore this warning?", @"alert message text")];
        [alert addButtonWithTitle:NSLocalizedString(@"Show Log", @"button title")];
        [alert addButtonWithTitle:NSLocalizedString(@"Ignore", @"button title")];
        [alert beginSheetModalForWindow:[self window] 
                          modalDelegate:self 
                         didEndSelector:@selector(alertForLogWindowDidEnd:returnCode:contextInfo:) 
                            contextInfo:NULL];                
    }
    else if ([op isCancelled] == NO) {
        
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
            // successful infrastructure update; remove the infra package from the list manually
            // ??? when did TL quit using arch-specific texlive.infra packages?
            [_updateListDataSource removePackageNamed:@"texlive.infra"];
            // formerly called _refreshUpdatedPackageListFromLocation here
            [_updateListDataSource setPackageFilter:nil];
            // versions are okay, and we can no longer rely on the list updates callback to reset this
            _updateInfrastructure = NO;
            [self _displayStatusString:NSLocalizedString(@"Infrastructure Update Succeeded", @"status message") dataSource:_updateListDataSource];
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
        [self _displayStatusString:NSLocalizedString(@"Paper Size Change Failed", @"status message") dataSource:_updateListDataSource];
    }
}

- (void)papersizeSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)context
{    
    [sheet orderOut:self];
    TLMPapersizeController *psc = context;
    [psc autorelease];
    if (TLMPapersizeChanged == returnCode && [psc paperSize]) {
        TLMPapersizeOperation *op = [[TLMPapersizeOperation alloc] initWithPapersize:[psc paperSize]];
        [self _addOperation:op selector:@selector(_handlePapersizeFinishedNotification:) setRefreshingForDataSource:nil];
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

- (void)_handleBackupPruningFinishedNotification:(NSNotification *)aNote
{
    TLMBackupOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    if ([op failed]) {
        TLMLog(__func__, @"Pruning failed.  Error was: %@", [op errorMessages]);
        [self _displayStatusString:NSLocalizedString(@"Backup Pruning Failed", @"status message") dataSource:_backupDataSource];
    }
    else {
        [_backupDataSource setNeedsUpdate:YES];
        [self _refreshCurrentDataSourceIfNeeded];
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
            [self _addOperation:change selector:@selector(_handleAutobackupOptionFinishedNotification:) setRefreshingForDataSource:nil];
            [change autorelease];         
            TLMLog(__func__, @"Setting autobackup to %ld", (long)[abc backupCount]);
        }
        
        if (returnCode & TLMAutobackupPrune) {
            // if autobackup is set to zero, --clean needs an explicit N argument or it returns an error
            TLMBackupOperation *cleaner;
            cleaner = returnCode & TLMAutobackupDisabled ? [TLMBackupOperation newDeepCleanOperation] : [TLMBackupOperation newCleanOperation];
            
            if (change)
                [cleaner addDependency:change];
            [self _addOperation:cleaner selector:@selector(_handleBackupPruningFinishedNotification:) setRefreshingForDataSource:nil];
            [cleaner release];
            TLMLog(__func__, @"Pruning autobackup sets to the last %ld", (long)[abc backupCount]);
        }
    }
}

- (void)_handleLaunchAgentInstallFinishedNotification:(NSNotification *)aNote
{
    TLMAuthorizedOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    if ([op isCancelled] == NO)
        TLMLog(__func__, @"Finished running launchd agent installer script");
}

- (void)launchAgentControllerSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)context
{
    [sheet orderOut:self];
    TLMLaunchAgentController *lac = context;
    [lac autorelease];
    if (returnCode & TLMLaunchAgentChanged) {
        
        NSMutableArray *options = [NSMutableArray arrayWithObject:[[NSBundle mainBundle] pathForAuxiliaryExecutable:@"agent_installer.py"]];
                
        TLMOperation *installOp = nil;
        
        if ((returnCode & TLMLaunchAgentEnabled) != 0) {
            
            [options addObject:@"--install"];
            
            [options addObject:@"--plist"];
            [options addObject:[lac propertyListPath]];
            
            [options addObject:@"--script"];
            [options addObject:[[NSBundle mainBundle] pathForResource:@"update_check" ofType:@"py"]];            

        }
        else {
            [options addObject:@"--remove"];
        }
        
        NSSearchPathDomainMask domains;
        BOOL installed = [TLMLaunchAgentController agentInstalled:&domains];
        
        if ((returnCode & TLMLaunchAgentAllUsers) != 0) {
            // ??? how about uninstalling or unloading from ~/Library?
            installOp = [[TLMAuthorizedOperation alloc] initWithAuthorizedCommand:@"/usr/bin/python" options:options];
            if (installed && (domains & NSUserDomainMask) != 0) {
                TLMLog(__func__, @"*** WARNING *** agent is also installed in ~/Library/LaunchAgents");
            }
        }
        else {
            // ??? how about uninstalling or unloading from /Library?
            installOp = [[TLMOperation alloc] initWithCommand:@"/usr/bin/python" options:options];
            if (installed && (domains & NSLocalDomainMask) != 0) {
                TLMLog(__func__, @"*** WARNING *** agent is also installed in /Library/LaunchAgents");
            }
        }                      
        
        [self _addOperation:installOp selector:@selector(_handleLaunchAgentInstallFinishedNotification:) setRefreshingForDataSource:nil];
        [installOp release];
        
    }
}

- (void)_handleListFinishedNotification:(NSNotification *)aNote
{
    TLMListOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    [_packageListDataSource setPackageNodes:[op packageNodes]];
    [_packageListDataSource setRefreshing:NO];
    [_packageListDataSource setNeedsUpdate:NO];
    
    NSString *statusString = nil;
    
    if ([op isCancelled])
        statusString = NSLocalizedString(@"Listing Cancelled", @"main window status string");
    else if ([op failed])
        statusString = NSLocalizedString(@"Listing Failed", @"main window status string");
    
    [self _displayStatusString:statusString dataSource:_packageListDataSource];
}

- (void)_handleLoadDatabaseFinishedNotification:(NSNotification *)aNote
{
    TLMLoadDatabaseOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    
    [_packageListDataSource setPackageNodes:[TLMDatabase packagesByMergingLocalWithMirror:[op updateURL]]];
    [_packageListDataSource setRefreshing:NO];
    [_packageListDataSource setNeedsUpdate:NO];
    
    NSString *statusString = nil;
    
    if ([op isCancelled])
        statusString = NSLocalizedString(@"Database Loading Cancelled", @"main window status string");
    else if ([op failed])
        statusString = NSLocalizedString(@"Database Loading Failed", @"main window status string");
    
    [self _displayStatusString:statusString dataSource:_packageListDataSource];
}

- (void)_handleListBackupsFinishedNotification:(NSNotification *)aNote
{
    TLMBackupListOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    [_backupDataSource setBackupNodes:[op backupNodes]];
    [_backupDataSource setNeedsUpdate:NO];
    
    NSString *statusString = nil;
    
    if ([op isCancelled])
        statusString = NSLocalizedString(@"Backup Listing Cancelled", @"main window status string");
    else if ([op failed])
        statusString = NSLocalizedString(@"Backup Listing Failed", @"main window status string");
    else if ([[op backupNodes] count] ==0)
        statusString = NSLocalizedString(@"No Backups Available", @"main window status string");
        
    [self _displayStatusString:statusString dataSource:_backupDataSource];
    [_backupDataSource setRefreshing:NO];
}

- (void)_refreshFullPackageListFromLocation:(NSURL *)location offline:(BOOL)offline
{
    // should only happen when the network or mirror is unreachable
    if ([[TLMDatabase databaseForMirrorURL:location] texliveYear] == TLMDatabaseUnknownYear) {
        TLMLog(__func__, @"Unknown database year, so forcing offline mode for package listing");
        offline = YES;
    }
    
    [self _displayStatusString:nil dataSource:_packageListDataSource];
    // disable refresh action for this view
    [_packageListDataSource setRefreshing:YES];
    TLMLog(__func__, @"Refreshing list of all packages%C", 0x2026);
    
    if ([[TLMEnvironment currentEnvironment] tlmgrSupportsDumpTlpdb] == NO) {
        TLMLog(__func__, @"Using legacy code for listing packages.  Hopefully it still works.");
        TLMListOperation *op = [[TLMListOperation alloc] initWithLocation:location offline:offline];
        [self _addOperation:op selector:@selector(_handleListFinishedNotification:) setRefreshingForDataSource:_packageListDataSource];
        [op release];
    }
    else {
        TLMLoadDatabaseOperation *op = [[TLMLoadDatabaseOperation alloc] initWithLocation:location offline:offline];
        [self _addOperation:op selector:@selector(_handleLoadDatabaseFinishedNotification:) setRefreshingForDataSource:_packageListDataSource];
        [op release];
    }
}

- (void)alertForLogWindowDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    if (NSAlertFirstButtonReturn == returnCode) {
        [[NSApp delegate] showLogWindow:nil];
    }
}

- (void)_handleInstallFinishedNotification:(NSNotification *)aNote
{
    TLMInstallOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    
    // ignore operations that failed or were explicitly cancelled
    if ([op failed]) {
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"Install failed.", @"alert title")];
        [alert setInformativeText:NSLocalizedString(@"The install process appears to have failed. Would you like to show the log now or ignore this warning?", @"alert message text")];
        [alert addButtonWithTitle:NSLocalizedString(@"Show Log", @"button title")];
        [alert addButtonWithTitle:NSLocalizedString(@"Ignore", @"button title")];
        [alert beginSheetModalForWindow:[self window] 
                          modalDelegate:self 
                         didEndSelector:@selector(alertForLogWindowDidEnd:returnCode:contextInfo:) 
                            contextInfo:NULL];                    
    }
    else if ([op isCancelled] == NO) {
                
        [self _refreshLocalDatabase];
        
        [_updateListDataSource setNeedsUpdate:YES];
        [_packageListDataSource setNeedsUpdate:YES];
        [_backupDataSource setNeedsUpdate:YES];
        
        [self _refreshCurrentDataSourceIfNeeded];
        
        // _handleInstallFinishedNotification: also gets called for _installDataSource, but that's pretty rare
        [self _displayStatusString:NSLocalizedString(@"Install Succeeded", @"status message") dataSource:_packageListDataSource];

    }    
}

- (void)_installPackagesWithNames:(NSArray *)packageNames reinstall:(BOOL)reinstall
{
    // sanity check in case the user switched the environment after getting an update listing
    NSURL *currentURL = [self serverURL];
    if ([self _isCorrectDatabaseVersionAtURL:currentURL]) {
        TLMInstallOperation *op = [[TLMInstallOperation alloc] initWithPackageNames:packageNames location:currentURL reinstall:reinstall];
        [self _addOperation:op selector:@selector(_handleInstallFinishedNotification:) setRefreshingForDataSource:nil];
        [op release];
        TLMLog(__func__, @"Beginning install of %@\nfrom %@", packageNames, [currentURL absoluteString]);   
    }
}

- (void)_handleRemoveFinishedNotification:(NSNotification *)aNote
{
    TLMRemoveOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    
    // ignore operations that failed or were explicitly cancelled
    if ([op failed]) {
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"Removal failed.", @"alert title")];
        [alert setInformativeText:NSLocalizedString(@"The removal process appears to have failed. Would you like to show the log now or ignore this warning?", @"alert message text")];
        [alert addButtonWithTitle:NSLocalizedString(@"Show Log", @"button title")];
        [alert addButtonWithTitle:NSLocalizedString(@"Ignore", @"button title")];
        [alert beginSheetModalForWindow:[self window] 
                          modalDelegate:self 
                         didEndSelector:@selector(alertForLogWindowDidEnd:returnCode:contextInfo:) 
                            contextInfo:NULL];                 
    }
    else if ([op isCancelled] == NO) {
                
        [_updateListDataSource setNeedsUpdate:YES];
        [_packageListDataSource setNeedsUpdate:YES];
        [_backupDataSource setNeedsUpdate:YES];
        
        [self _refreshCurrentDataSourceIfNeeded];
        [self _displayStatusString:NSLocalizedString(@"Removal Succeeded", @"status message") dataSource:_packageListDataSource];
    }    
}

- (void)_handleRestoreFinishedNotification:(NSNotification *)aNote
{
    TLMRemoveOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    
    // ignore operations that failed or were explicitly cancelled
    if ([op failed]) {
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"Restore failed.", @"alert title")];
        [alert setInformativeText:NSLocalizedString(@"The restore process appears to have failed. Would you like to show the log now or ignore this warning?", @"alert message text")];
        [alert addButtonWithTitle:NSLocalizedString(@"Show Log", @"button title")];
        [alert addButtonWithTitle:NSLocalizedString(@"Ignore", @"button title")];
        [alert beginSheetModalForWindow:[self window] 
                          modalDelegate:self 
                         didEndSelector:@selector(alertForLogWindowDidEnd:returnCode:contextInfo:) 
                            contextInfo:NULL];              
    }
    else if ([op isCancelled] == NO) {
                
        [_updateListDataSource setNeedsUpdate:YES];
        
        // no reason to refresh backups or package list after a restore
        [self _refreshCurrentDataSourceIfNeeded];
        
        // will get blown away by the refresh if backup isn't the current datasource, but that's okay
        [self _displayStatusString:NSLocalizedString(@"Restore Succeeded", @"status message") dataSource:_backupDataSource];

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
    /*
     Use the URL set in preferences, in case the currently installed TL is from the previous year,
     and we munged it to point at the TUG archived versions.
     */
    NSURL *installURL = [[TLMEnvironment currentEnvironment] defaultServerURL];
    TLMNetInstallOperation *op = [[TLMNetInstallOperation alloc] initWithProfile:profile location:installURL];
    [self _addOperation:op selector:@selector(_handleNetInstallFinishedNotification:) setRefreshingForDataSource:nil];
    [op release];
}

- (void)_refreshCurrentDataSourceIfNeeded
{
    
    /*
     This is slow, but if infrastructure was updated or a package installed other dependencies, 
     we have no way of manually removing from the list.  We also need to ensure that the same 
     mirror is used, so results are consistent.
     */
    
    // !!! early return if the data source is up to date
    if ([_currentListDataSource needsUpdate] == NO)
        return;
    
    if ([_currentListDataSource isEqual:_updateListDataSource] && [_updateListDataSource isRefreshing] == NO) {
        [self refreshUpdatedPackageList];
    }
    else if ([_currentListDataSource isEqual:_backupDataSource] && [_backupDataSource isRefreshing] == NO) {
        [self refreshBackupList];
    }
    else if ([_currentListDataSource isEqual:_packageListDataSource] && [_packageListDataSource isRefreshing] == NO) {
        [self refreshFullPackageList];
    }
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
    [self _refreshUpdatedPackageListFromLocation:[self serverURL]];
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

- (IBAction)automaticUpdateCheck:(id)sender;
{
    TLMLaunchAgentController *lac = [TLMLaunchAgentController new];
    [NSApp beginSheet:[lac window] 
       modalForWindow:[self window] 
        modalDelegate:self 
       didEndSelector:@selector(launchAgentControllerSheetDidEnd:returnCode:contextInfo:) 
          contextInfo:lac];
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

- (IBAction)changeServerURL:(id)sender;
{
    NSURL *newURL = [_URLField objectValue];

    if (_operationCount) {
        
        // only warn if this is a different URL
        if ([newURL isEqual:[self serverURL]] == NO) {
            TLMLog(__func__, @"Can't change URL while an operation is in progress");
            [_URLField setStringValue:[[self serverURL] absoluteString]];
            NSBeep();
        }
    }
    else {
        NSURL *aURL;
        NSString *err;
        // manual validation for drag-and-drop; maybe another way to do this...
        if ([[[_URLField cell] formatter] getObjectValue:&aURL forString:[_URLField stringValue] errorDescription:&err]) {
            
            // will show an alert if there's a version mismatch
            if ([newURL isEqual:[self serverURL]]) {
                // don't trigger tlmgr every time the address field loses first responder
                TLMLog(__func__, @"Ignoring spurious URL change action");
            }
            else if ([self _isCorrectDatabaseVersionAtURL:newURL]) {
                TLMLog(__func__, @"User changed URL to %@", newURL);
                [self setServerURL:newURL];
                
                // web browser expectations
                [_updateListDataSource setNeedsUpdate:YES];
                [_packageListDataSource setNeedsUpdate:YES];
                [self _refreshCurrentDataSourceIfNeeded];
            }
            else {
                // wrong db version
                [_URLField setStringValue:[[self serverURL] absoluteString]];
            }

            
        }
        else {
            NSAlert *alert = [[NSAlert new] autorelease];
            [alert setMessageText:NSLocalizedString(@"Invalid URL entered", @"alert title")];
            [alert setInformativeText:err];
            [alert beginSheetModalForWindow:[self window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
            [_URLField setStringValue:[[self serverURL] absoluteString]];
        }
    }
}

- (IBAction)goHome:(id)sender;
{
    if ([[[TLMEnvironment currentEnvironment] defaultServerURL] isMultiplexer])
        [self _displayStatusString:URL_VALIDATE_STATUS_STRING dataSource:_currentListDataSource];
    [_URLField setStringValue:[[[TLMEnvironment currentEnvironment] validServerURL] absoluteString]];
    if ([[[_currentListDataSource statusWindow] statusString] isEqualToString:URL_VALIDATE_STATUS_STRING])
        [self _displayStatusString:nil dataSource:_currentListDataSource];
    [self changeServerURL:nil];
    
    // web browser expectations
    [_updateListDataSource setNeedsUpdate:YES];
    [_packageListDataSource setNeedsUpdate:YES];
    [self _refreshCurrentDataSourceIfNeeded];
}

- (void)updateInfrastructure:(id)sender;
{
    [self _displayStatusString:nil dataSource:_updateListDataSource];
    TLMLog(__func__, @"Beginning user-requested infrastructure update%C", 0x2026);
    _updateInfrastructure = YES;
    [self _updateAllPackages];
}

- (void)updateInfrastructureFromCriticalRepository:(id)sender
{
    [self _displayStatusString:nil dataSource:_updateListDataSource];
    TLMLog(__func__, @"Beginning user-requested infrastructure update from tlcritical repo%C", 0x2026);
    _updateInfrastructure = YES;
    NSURL *repo = [NSURL URLWithString:[[NSUserDefaults standardUserDefaults] objectForKey:TLMTLCriticalRepository]];
    [self _updateAllPackagesFromRepository:repo];
}

#pragma mark API

- (void)refresh:(id)sender
{
    // not part of the protocol since it's meaningless for the install datasource
    if ([_currentListDataSource respondsToSelector:@selector(refreshList:)])
        [(id)_currentListDataSource refreshList:sender];
}

- (void)refreshFullPackageList
{
    NSURL *serverURL = [self serverURL];

    /* 
     If the network is not available, read the local package db so that show info still works.
     Note that all packages thus shown will be installed, so presumably forced updates will fail
     and removal may succeed.  Avoid doing special case menu validation until it seems necessary.
     
     The serverURL and diagnostic are separate tests; serverURL is more robust, but the diagnostic
     might help if the network is actually down.  Should this be done elsewhere?
     */
    CFNetDiagnosticRef diagnostic = NULL;
    if (serverURL) {
        diagnostic = CFNetDiagnosticCreateWithURL(NULL, (CFURLRef)serverURL);
        [(id)diagnostic autorelease];
    }
    CFStringRef desc = NULL;
    if (nil == serverURL || (diagnostic && kCFNetDiagnosticConnectionDown == CFNetDiagnosticCopyNetworkStatusPassively(diagnostic, &desc))) {
        // this is basically a dummy URL that we pass through in offline mode
        serverURL = [NSURL fileURLWithPath:[[TLMEnvironment currentEnvironment] installDirectory] isDirectory:YES];
        if (NULL == desc) desc = CFRetain(CFSTR("unknown error"));
        TLMLog(__func__, @"Network connection is down (%@).  Trying local install database %@%C", desc, serverURL, 0x2026);
        [(id)desc autorelease];
        [self _displayStatusString:NSLocalizedString(@"Network is unavailable", @"") dataSource:_packageListDataSource];
        [self _refreshFullPackageListFromLocation:serverURL offline:YES];
    }
    else {
        [self _refreshFullPackageListFromLocation:serverURL offline:NO];
    }
}

- (void)refreshUpdatedPackageList
{
    [self refreshUpdatedPackageListWithURL:[self serverURL]];
}

- (void)refreshUpdatedPackageListWithURL:(NSURL *)aURL;
{
    if (aURL && [_updateListDataSource isRefreshing] == NO) {
        [self setServerURL:aURL];
        [self _refreshUpdatedPackageListFromLocation:aURL];  
    }
}

- (void)updateAllPackages;
{
    [self _displayStatusString:nil dataSource:_updateListDataSource];
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
    if ([[TLMEnvironment currentEnvironment] autoRemove] && removeCount)
        [informativeText appendFormat:@"  %@", NSLocalizedString(@"Packages that no longer exist on the server will be removed.", @"update alert message text part 2 (optional)")];
    
    predicate = [NSPredicate predicateWithFormat:@"(isInstalled == NO)"];
    NSUInteger installCount = [[[_updateListDataSource allPackages] filteredArrayUsingPredicate:predicate] count];
    if ([[TLMEnvironment currentEnvironment] autoInstall] && installCount)
        [informativeText appendFormat:@"  %@", NSLocalizedString(@"New packages will be installed.", @"update alert message text part 3 (optional)")];
    
    // disaster recovery script is much larger than the value we get from tlmgr
    if (NO == _updateInfrastructure) {
        TLMSizeFormatter *sizeFormatter = [[TLMSizeFormatter new] autorelease];
        NSString *sizeString = [sizeFormatter stringForObjectValue:[NSNumber numberWithUnsignedInteger:size]];
        [informativeText appendFormat:NSLocalizedString(@"  Total download size will be %@.", @"partial alert text, with double space in front, only used with tlmgr2"), sizeString];
    }
    
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
    [self _displayStatusString:nil dataSource:_updateListDataSource];
    NSURL *currentURL = [self serverURL];
    if ([self _isCorrectDatabaseVersionAtURL:currentURL]) {
        TLMUpdateOperation *op = [[TLMUpdateOperation alloc] initWithPackageNames:packageNames location:currentURL];
        [self _addOperation:op selector:@selector(_handleUpdateFinishedNotification:) setRefreshingForDataSource:nil];
        [op release];
        TLMLog(__func__, @"Beginning update of %@\nfrom %@", packageNames, [currentURL absoluteString]);
    }
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
        [self _addOperation:op selector:@selector(_handleRemoveFinishedNotification:) setRefreshingForDataSource:nil];
        [op release];
        TLMLog(__func__, @"Beginning removal of\n%@", packageNames); 
    }
}

- (void)refreshBackupList
{
    TLMBackupListOperation *op = [TLMBackupListOperation new];
    [self _displayStatusString:nil dataSource:_backupDataSource];
    [_backupDataSource setRefreshing:YES];
    [self _addOperation:op selector:@selector(_handleListBackupsFinishedNotification:) setRefreshingForDataSource:_backupDataSource];
    [op release];
}

- (void)restorePackage:(NSString *)packageName version:(NSNumber *)version;
{
    TLMBackupOperation *op = [TLMBackupOperation newRestoreOperationWithPackage:packageName version:version];
    [self _displayStatusString:nil dataSource:_backupDataSource];
    TLMLog(__func__, @"Restoring version %@ of %@", version, packageName);
    [self _addOperation:op selector:@selector(_handleRestoreFinishedNotification:) setRefreshingForDataSource:nil];
    [op release];    
}

@end
