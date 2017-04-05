//
//  TLMMainWindowController.m
//  TeX Live Utility
//
//  Created by Adam Maxwell on 12/6/08.
/*
 This software is Copyright (c) 2008-2016
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
#import "TLMTexdistConfigController.h"
#import "TLMDocumentationController.h"

@interface TLMMainWindowController (Private)
// only declare here if reorganizing the implementation isn't practical
- (void)_refreshCurrentDataSourceIfNeeded;
- (void)_refreshLocalDatabase;
- (void)_displayStatusString:(NSString *)statusString dataSource:(id <TLMListDataSource>)dataSource;
@end


static char _TLMOperationQueueOperationContext;

#define DB_LOAD_STATUS_STRING      ([NSString stringWithFormat:@"%@%C", NSLocalizedString(@"Loading Database", @"status message"), TLM_ELLIPSIS])
#define URL_VALIDATE_STATUS_STRING ([NSString stringWithFormat:@"%@%C", NSLocalizedString(@"Validating Server", @"status message"), TLM_ELLIPSIS])

/*
 Increment this when/if toolbar configuration changes.
 I guess an alternative would be to change the identifier in the nib...
 */
#define TOOLBAR_VERSION ((int)1)

static Class _UserNotificationCenterClass;
static Class _UserNotificationClass;

#ifndef MAC_OS_X_VERSION_10_8
@interface NSUserNotification : NSObject
@property (readwrite, copy) NSString *title;
@end
@interface NSUserNotificationCenter : NSObject
+ (id)defaultUserNotificationCenter;
+ (void)deliverNotification:(NSUserNotification *)note;
@end
#endif

@implementation TLMMainWindowController

@synthesize _progressIndicator;
@synthesize _URLField;
@synthesize _packageListDataSource;
@synthesize _tabView;
@synthesize _updateListDataSource;
@synthesize _installDataSource;
@synthesize infrastructureNeedsUpdate = _infrastructureNeedsUpdate;
@synthesize updatingInfrastructure = _updatingInfrastructure;
@synthesize _backupDataSource;
@synthesize serverURL = _serverURL;

+ (void)initialize
{
    _UserNotificationCenterClass = NSClassFromString(@"NSUserNotificationCenter");
    _UserNotificationClass = NSClassFromString(@"NSUserNotification");
}

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
        _updatingInfrastructure = NO;
        _infrastructureNeedsUpdate = NO;
        _operationCount = 0;
        
        if ([[NSUserDefaults standardUserDefaults] integerForKey:@"MainWindowToolbarVersion"] != TOOLBAR_VERSION) {
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"NSToolbar Configuration Main window toolbar"];
            [[NSUserDefaults standardUserDefaults] setInteger:TOOLBAR_VERSION forKey:@"MainWindowToolbarVersion"];
        }        
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
    [_packageListDataSource release];
    [_updateListDataSource release];
    [_backupDataSource release];
    [_installDataSource release];
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
    
    // set to YES in the nib in hopes that it shows up in the stupid toolbar config sheet
    [_progressIndicator setDisplayedWhenStopped:NO];
    
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
    
    // need good initial properties since we can't add to the queue if tlmgr doesn't exist
    [_URLField setButtonImage:[NSImage imageNamed:NSImageNameRefreshFreestandingTemplate]];
    [_URLField setButtonTarget:self];
    [_URLField setButtonAction:@selector(refresh:)];
}

/*
 All this crap is to allow the spinner to be visible in the customization palette and
 toolbar when modifying the toolbar, and otherwise hidden when it's stopped.  I tried
 a lot of stuff here, so remember not to screw with this unless it breaks.
 
     1) Setting it always-visible in the nib and sending -[_progressIndicator setDisplayedWhenStopped:NO]
        in -awakeFromNib will cause the one in the toolbar and the one in the palette to both be hidden.
     2) It has to be sent when the sheet goes away.  Any sooner and you won't be able to see it to move
        it around in the toolbar.
     3) Just returning the @"pig" identifier in toolbarDefaultItemIdentifiers will put the spinner as the
        first item in the toolbar, which is not what I want.  Therefore, a few of the other items in the
        nib also have identifiers set.
 */
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag;
{
    if ([itemIdentifier isEqualToString:@"pig"]) {
        NSProgressIndicator *pig = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, 0, 16, 16)];
        [pig setControlSize:NSSmallControlSize];
        [pig setStyle:NSProgressIndicatorSpinningStyle];
        [pig setUsesThreadedAnimation:YES];
        [pig setDisplayedWhenStopped:YES];
        if (flag) [self set_progressIndicator:pig];

        NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        [item setView:pig];
        [pig release];
        [item setPaletteLabel:NSLocalizedString(@"Progress", @"toolbar item palette label")];
        [item setMaxSize:[pig frame].size];
        [item setMinSize:[pig frame].size];
        return [item autorelease];
    }
    return nil;
}

- (void)windowWillBeginSheet:(NSNotification *)notification;
{
    if ([[[self window] toolbar] customizationPaletteIsRunning])
        [_progressIndicator setDisplayedWhenStopped:YES];
}

- (void)windowDidEndSheet:(NSNotification *)notification;
{
    if ([[[self window] toolbar] customizationPaletteIsRunning] == NO)
        [_progressIndicator setDisplayedWhenStopped:NO];
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar;
{
    return [NSArray arrayWithObjects:@"homeButton", @"addressField", @"pig", NSToolbarFlexibleSpaceItemIdentifier, @"searchField", nil];
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar;
{
    return [NSArray arrayWithObject:@"pig"];
}

- (void)_stopProgressBar:(NSNotification *)aNote
{
    // we're done with the progress bar now, so set it to zero to clear it out
    [_URLField setProgressValue:0];
    [NSApp setApplicationIconImage:nil];
}

- (void)_startProgressBar:(NSNotification *)aNote
{    
    // we always have an integral number of bytes >> 1, so set a fake value here so it draws immediately
    const double initialValue = 1.0;
    [_URLField setMinimumProgressValue:0.0];
    [_URLField setMaximumProgressValue:([[[aNote userInfo] objectForKey:TLMLogSize] doubleValue] + initialValue)];
    [_URLField setProgressValue:initialValue];
}

- (void)_updateProgressBar:(NSNotification *)aNote
{
    [_URLField incrementProgressBy:[[[aNote userInfo] objectForKey:TLMLogSize] doubleValue]];
    /*
     Formerly called -[[self _progressBar] display] here.  That was killing performance after I
     added progress updates to the infra operation; drawing basically stalled, since the
     window had to synchronize too frequently.  All this to say...don't do that again.
     */
    CGFloat p = [_URLField progressValue] / [_URLField maximumProgressValue];
    [NSApp setApplicationIconImage:[TLMProgressIndicatorCell applicationIconBadgedWithProgress:p]];
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    // checkbox in IB doesn't work?
    [[[self window] toolbar] setAutosavesConfiguration:YES];   
}

- (void)_goHome
{
    if ([[[TLMEnvironment currentEnvironment] defaultServerURL] isMultiplexer])
        [self _displayStatusString:URL_VALIDATE_STATUS_STRING dataSource:_currentListDataSource];
    // home is based on prefs, not the current URL
    _serverURL = [[[TLMEnvironment currentEnvironment] validServerURLFromURL:nil] copy];
    if ([[[_currentListDataSource statusWindow] statusString] isEqualToString:URL_VALIDATE_STATUS_STRING])
        [self _displayStatusString:nil dataSource:_currentListDataSource];
    
    // !!! end up with a bad environment if this is the multiplexer, and the UI gets out of sync
    if (nil == _serverURL)
        _serverURL = [[[TLMEnvironment currentEnvironment] defaultServerURL] copy];
    
    if ([_serverURL isMultiplexer]) {
        TLMLog(__func__, @"Still have multiplexer URL after setup.  This is not good.");
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"Unable to find a valid update server", @"alert title")];
        [alert setInformativeText:NSLocalizedString(@"Either a network problem exists or the TeX Live version on the server does not match.  If this problem persists on further attempts, you may need to try a different repository.", @"alert text")];
        [alert beginSheetModalForWindow:[self window]
                          modalDelegate:nil
                         didEndSelector:NULL
                            contextInfo:NULL];
    }
    
    [_URLField setStringValue:[[self serverURL] absoluteString]];
    
    // I don't like having this selected and highlighted at launch, for some reason
    [[_URLField currentEditor] setSelectedRange:NSMakeRange(0, 0)];
    [[self window] makeFirstResponder:nil];
    
}

- (void)gpgInstallAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)context
{
    TLMDatabaseYear year = [[TLMEnvironment currentEnvironment] texliveYear];
    if ([[alert suppressionButton] state] == NSOnState)
        [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInteger:year]
                                                  forKey:TLMDisableGPGAlertPreferenceKey];
    
    if (NSAlertFirstButtonReturn == returnCode) {
        //   tlmgr --repository http://www.preining.info/tlgpg/ install tlgpg
        NSURL *gpgURL = [NSURL URLWithString:@"http://www.preining.info/tlgpg/"];
        [_URLField setStringValue:[gpgURL absoluteString]];
        [self setServerURL:gpgURL];
        
        // I don't like having this selected and highlighted at launch, for some reason
        [[_URLField currentEditor] setSelectedRange:NSMakeRange(0, 0)];
        [[self window] makeFirstResponder:nil];
        
        TLMInstallOperation *gpgOperation = [[TLMInstallOperation alloc] initWithPackageNames:[NSArray arrayWithObject:@"tlgpg"] location:gpgURL reinstall:YES];
        [self _addOperation:gpgOperation selector:@selector(_handleGPGInstallFinishedNotification:) setRefreshingForDataSource:nil];
        [gpgOperation release];
    }
    else {
        // set the dirty bit on all datasources
        [_updateListDataSource setNeedsUpdate:YES];
        [_packageListDataSource setNeedsUpdate:YES];
        [_backupDataSource setNeedsUpdate:YES];
        [_installDataSource setNeedsUpdate:YES];
        
        // do this after the window loads, so something is visible right away
        [self _goHome];
    }
}

- (void)showWindow:(id)sender
{
    [super showWindow:sender];
    
    [[(TLMAppController *)[NSApp delegate] logWindowController] setDockingDelegate:self];

    static BOOL __windowDidShow = NO;
    if (__windowDidShow) return;
    __windowDidShow = YES;
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:TLMDisableGPGAlertPreferenceKey])
        TLMLog(__func__, @"User has chosen to permanently ignore the GPG install alert");
    
    TLMEnvironment *currentEnv = [TLMEnvironment currentEnvironment];
    const TLMDatabaseYear currentYear = [currentEnv texliveYear];
    // force the user to disable GPG install warning every year
    if (currentYear >= 2016 &&
        [[NSUserDefaults standardUserDefaults] integerForKey:TLMDisableGPGAlertPreferenceKey] != currentYear &&
        [[TLMDatabase localDatabase] packageNamed:@"tlgpg"] == nil) {

            NSAlert *alert = [[NSAlert new] autorelease];
            [alert setMessageText:NSLocalizedString(@"Enable security validation of packages?", @"alert title")];
            [alert setInformativeText:NSLocalizedString(@"This version of TeX Live allows you to check the digital signature of downloaded packages by installing GnuPG. For better security, you should enable this feature.", @"alert text")];
            [alert addButtonWithTitle:NSLocalizedString(@"Enable", @"button title")];
            [alert addButtonWithTitle:NSLocalizedString(@"Later", @"button title")];
            [alert setShowsSuppressionButton:YES];
            [alert beginSheetModalForWindow:[self window]
                              modalDelegate:self
                             didEndSelector:@selector(gpgInstallAlertDidEnd:returnCode:contextInfo:)
                                contextInfo:NULL];
    }
    else {

        // set the dirty bit on all datasources
        [_updateListDataSource setNeedsUpdate:YES];
        [_packageListDataSource setNeedsUpdate:YES];
        [_backupDataSource setNeedsUpdate:YES];
        [_installDataSource setNeedsUpdate:YES];

        // do this after the window loads, so something is visible in the URL field
        [self _goHome];
    }
    
    // for info window; TL 2011 and later only
    [self _refreshLocalDatabase];
        
    // no need to update if we do a migration
    if ([TLMLaunchAgentController migrateLocalToUserIfNeeded] == NO && [TLMLaunchAgentController scriptNeedsUpdate]) {
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"Newer update checker is available", @"alert title")];
        [alert setInformativeText:NSLocalizedString(@"A newer version of the scheduled update script is available.  Would you like to install it now?", @"alert text")];
        [alert addButtonWithTitle:NSLocalizedString(@"Yes", @"button title")];
        [alert addButtonWithTitle:NSLocalizedString(@"No", @"button title")];
        [alert beginSheetModalForWindow:[self window] 
                          modalDelegate:self
                         didEndSelector:@selector(launchAgentScriptUpdateAlertDidEnd:returnCode:contextInfo:)
                            contextInfo:NULL];
    }
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

// cover method to avoid loading the log controller's window before it's needed
- (NSWindow *)_logWindow
{
    TLMLogWindowController *lwc = [(TLMAppController *)[NSApp delegate] logWindowController];
    return [lwc isWindowLoaded] ? [[(TLMAppController *)[NSApp delegate] logWindowController] window] : nil;
}

- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)frameSize;
{
    const CGFloat dy = NSHeight([sender frame]) - frameSize.height;
    const CGFloat dx = NSWidth([sender frame]) - frameSize.width;
    NSWindow *logWindow = [self _logWindow];
    if ([logWindow isVisible] && [[[self window] childWindows] containsObject:logWindow]) {
        
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

- (void)windowDidResize:(NSNotification *)notification;
{
    NSWindow *logWindow = [self _logWindow];
    if ([logWindow isVisible] && [[[self window] childWindows] containsObject:logWindow] == NO)
        [self dockableWindowGeometryDidChange:logWindow];    
}

- (void)windowDidMove:(NSNotification *)notification;
{
    NSWindow *logWindow = [self _logWindow];
    if ([logWindow isVisible] && [[[self window] childWindows] containsObject:logWindow] == NO)
        [self dockableWindowGeometryDidChange:logWindow];
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
    /*
     I think this is here in case the overlay window is added while the sheet
     is being positioned.  The sheet seems to work fine if the overlay window
     is up first, and in fact this call causes some flickering when the sheet
     is repositioned.  Avoid it if we definitely have the overlay now.
     */
    if (nil == [_currentListDataSource statusWindow])
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

- (NSArray *)control:(NSControl *)control textView:(NSTextView *)textView completions:(NSArray *)words forPartialWordRange:(NSRange)charRange indexOfSelectedItem:(NSInteger *)selIndex;
{
    if (selIndex) *selIndex = 0;
    NSFormatter *fmt = [[control cell] formatter];
    NSMutableArray *candidates = [[[(TLMAppController *)[NSApp delegate] mirrorController] mirrorsMatchingSearchString:[textView string]] mutableCopy];
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

- (void)_runUpdmap
{
    [self _displayStatusString:NSLocalizedString(@"Running updmap…", @"") dataSource:_currentListDataSource];
    TLMTask *task = [[TLMTask new] autorelease];
    [task setLaunchPath:[[TLMEnvironment currentEnvironment] updmapAbsolutePath]];
    [task launch];
    
    // so we can check/log messages and clear the status overlay
    [task waitUntilExit];
    
    if ([task terminationStatus] == 0) {
        if ([[task outputString] length])
            TLMLog(__func__, @"%@", [task outputString]);
        if ([[task errorString] length])
            TLMLog(__func__, @"%@", [task errorString]);
    }
    else if ([task terminationStatus]) {
        TLMLog(__func__, @"updmap had problems:\n%@", [task errorString]);
    }
    [self _displayStatusString:nil dataSource:_currentListDataSource];
}

- (void)_updmapAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{    
    if ([[alert suppressionButton] state] == NSOnState)
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:TLMDisableUpdmapAlertPreferenceKey];

    if (NSAlertFirstButtonReturn == returnCode) {
        [[alert window] orderOut:nil];
        [self _runUpdmap];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:TLMEnableUserUpdmapPreferenceKey];
    }
    else {
        TLMLog(__func__, @"User declined to run updmap in spite of having the config file; whatever.");
    }
}

- (void)_runUpdmapIfNeeded
{    
    
    const TLMDatabaseYear texliveYear = [[TLMEnvironment currentEnvironment] texliveYear];
    
    // !!! early return
    if (texliveYear < 2012) {
        TLMLog(__func__, @"Not doing user updmap.cfg check for old TeX Live versions");
        return;
    }
        
    TLMTask *task = [[TLMTask new] autorelease];
    [task setLaunchPath:[[TLMEnvironment currentEnvironment] kpsewhichAbsolutePath]];
    [task setArguments:[NSArray arrayWithObjects:@"-all", @"updmap.cfg", nil]];
    [task launch];
    [task waitUntilExit];
    NSArray *updmapCfgPaths = nil;
    if ([task terminationStatus] == 0 && [task outputString]) {
        NSString *outputString = [[task outputString] stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        updmapCfgPaths = [outputString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    }
    else {
        TLMLog(__func__, @"%@ %@ returned an error: %@", [task launchPath], [[task arguments] componentsJoinedByString:@" "], [task errorString]);
    }
    
    task = [[TLMTask new] autorelease];
    [task setLaunchPath:[[TLMEnvironment currentEnvironment] kpsewhichAbsolutePath]];
    [task setArguments:[NSArray arrayWithObject:@"-var-value=TEXMFHOME"]];
    [task launch];
    [task waitUntilExit];
    NSArray *texmfHomePaths = nil;
    if ([task terminationStatus] == 0 && [task outputString]) {
        NSString *outputString = [[task outputString] stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        texmfHomePaths = [outputString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    }
    else {
        TLMLog(__func__, @"%@ %@ returned an error: %@", [task launchPath], [[task arguments] componentsJoinedByString:@" "], [task errorString]);
    }
    
    for (NSString *updmapCfgPath in updmapCfgPaths) {
        
        BOOL isSubpathOfHome = NO;
        
        for (NSString *texmfHomePath in texmfHomePaths) {
            if ([updmapCfgPath hasPrefix:texmfHomePath]) {
                isSubpathOfHome = YES;
                break;
            }
        }
        
        if (NO == isSubpathOfHome) {
            TLMLog(__func__, @"%@ is not in %@; ignoring", updmapCfgPath, texmfHomePaths);
        }
        // now see if any of these files exist (should exist if kpsewhich returns anything)
        else if ([[NSFileManager defaultManager] fileExistsAtPath:updmapCfgPath]) {
            
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            TLMLog(__func__, @"Found local map file %@", updmapCfgPath);

            /*
             show alert if preference is not enabled && (not previously shown for this TL year || user has not checked box to disable warning)
             */
            if ([defaults boolForKey:TLMEnableUserUpdmapPreferenceKey]) {
                [self _runUpdmap];
            }
            else if ([defaults integerForKey:TLMLastUpdmapVersionShownKey] != texliveYear || [defaults boolForKey:TLMDisableUpdmapAlertPreferenceKey] == NO) {
                    
                NSAlert *alert = [[NSAlert new] autorelease];
                [alert setMessageText:NSLocalizedString(@"Local fonts were found", @"alert title")];
                [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"You appear to have installed fonts in your home directory.  Would you like them to be automatically activated in TeX Live %d?", @"alert text, integer format specifier"), texliveYear]];
                [alert addButtonWithTitle:NSLocalizedString(@"Yes", @"button title")];
                [alert addButtonWithTitle:NSLocalizedString(@"No", @"button title")];
                
                // don't bother showing current state, so user doesn't disable accidentally
                [alert setShowsSuppressionButton:YES];
                [alert beginSheetModalForWindow:[self window]
                                  modalDelegate:self
                                 didEndSelector:@selector(_updmapAlertDidEnd:returnCode:contextInfo:)
                                    contextInfo:NULL];

            }
            
            // set this whether we run updmap or not
            [defaults setInteger:texliveYear forKey:TLMLastUpdmapVersionShownKey];
            
            // only need to run it once
            break;
        }
        else {
            TLMLog(__func__, @"WARNING: updmap returned nonexistent path at %@", updmapCfgPath);
        }
    }
}

- (BOOL)_checkCommandPathAndWarn:(BOOL)displayWarning
{
    NSString *cmdPath = [[TLMEnvironment currentEnvironment] tlmgrAbsolutePath];
    BOOL exists = [[NSFileManager defaultManager] isExecutableFileAtPath:cmdPath];

    if (NO == exists) {
        
        if (displayWarning) {
            NSAlert *alert = [[NSAlert new] autorelease];
            [alert setMessageText:NSLocalizedString(@"TeX installation not found.", @"alert sheet title")];
            [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"The tlmgr tool does not exist at %@.  Please set the correct location in preferences or install TeX Live.", @"alert message text"), cmdPath]];
            [alert beginSheetModalForWindow:[self window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
        }
        else {
            TLMLog(__func__, @"bad path %@, but displayWarning = %d", cmdPath, displayWarning);
        }
    }
    
    return exists;
}

- (void)_addOperation:(TLMOperation *)op selector:(SEL)sel setRefreshingForDataSource:(id)dataSource
{
    // short-circuit the tlmgr path check when installing
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
 
 Note: also called when manually entering a mirror in the address field, so we can also
 get uncached/unvalidated mirrors here.
 */
- (BOOL)_isCorrectDatabaseVersionAtURL:(NSURL *)aURL
{
    TLMLog(__func__, @"Checking database version in case preferences have been changed%C", TLM_ELLIPSIS);
    // should be cached, unless the user has screwed up (and that's the case we're trying to catch)
    TLMDatabase *db = [TLMDatabase databaseForMirrorURL:aURL];
    const TLMDatabaseYear year = [[TLMEnvironment currentEnvironment] texliveYear];
    if ([db failed] || [db texliveYear] == TLMDatabaseUnknownYear) {
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"Unable to determine repository version", @"alert title")];
        [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"You have TeX Live %lu installed, but the version at %@ cannot be determined.", @"alert text, integer and string format specifiers"), (long)year, [aURL absoluteString]]];
        [alert beginSheetModalForWindow:[self window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
        return NO;
    }
    else if ([db texliveYear] != year) {
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"Repository has a different TeX Live version", @"alert title")];
        [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"The repository at %@ has TeX Live %lu, but you have TeX Live %lu installed.  You need to switch repositories in order to continue.", @"alert text, two integer format specifiers"), [aURL absoluteString], (long)[db texliveYear], (long)year]];
        [alert beginSheetModalForWindow:[self window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
        TLMLog(__func__, @"Well, this is not going to work:  %@ has TeX Live %lu, and the installed version is TeX Live %lu", [aURL absoluteString], (long)[db texliveYear], (long)year);
        return NO;
    }
    return YES;
}

- (void)_updateAllPackagesFromRepository:(NSURL *)repository
{
    // sanity check in case the user switched the environment after getting an update listing
    if ([self _isCorrectDatabaseVersionAtURL:repository]) {
        TLMOperation *op = nil;
        if (_infrastructureNeedsUpdate) {
            _updatingInfrastructure = YES;
            _infrastructureNeedsUpdate = NO;
            op = [[TLMInfraUpdateOperation alloc] initWithLocation:repository];
            TLMLog(__func__, @"Beginning infrastructure update from %@", [repository absoluteString]);
            [self _addOperation:op selector:@selector(_handleInfrastructureUpdateFinishedNotification:) setRefreshingForDataSource:nil];
        }
        else {
#if DEBUG
#warning FIXME
#endif
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
                    NSInteger vers = [[line substringFromIndex:NSMaxRange(r)] integerValue];
                    if (vers > 0) [versions setObject:[NSNumber numberWithInteger:vers] forKey:name];
                    break;
                }
            }
        }
    }
    return versions;
}

- (void)_postUserNotificationWithTitle:(NSString *)title
{
    NSUserNotification *note = [[_UserNotificationClass new] autorelease];
    [note setTitle:title];
    [[_UserNotificationCenterClass defaultUserNotificationCenter] deliverNotification:note];
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
        _infrastructureNeedsUpdate = YES;
        
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
        NSParameterAssert(NO == _infrastructureNeedsUpdate);
        [_updateListDataSource setPackageFilter:nil];
    }
    
    [_updateListDataSource setAllPackages:allPackages];
    [_updateListDataSource setRefreshing:NO];
    [_updateListDataSource setNeedsUpdate:NO];
    
    NSString *statusString = nil;
    
    if ([op isCancelled])
        statusString = NSLocalizedString(@"Listing Cancelled", @"main window status string");
    else if ([op failed]) {
        statusString = NSLocalizedString(@"Listing Failed", @"main window status string");
        [self _postUserNotificationWithTitle:statusString];
    }
    else if ([allPackages count] == 0) {
        statusString = NSLocalizedString(@"No Updates Available", @"main window status string");
        [self _postUserNotificationWithTitle:statusString];
    }
    
    [self _displayStatusString:statusString dataSource:_updateListDataSource];
    [[[self window] toolbar] validateVisibleItems];
}

- (void)_refreshLocalDatabase
{
    [TLMDatabase reloadLocalDatabase];
}

- (void)_refreshUpdatedPackageListFromLocation:(NSURL *)location
{
    // refresh should always clear status first
    [self _displayStatusString:nil dataSource:_updateListDataSource];
    
    if ([[TLMDatabase databaseForMirrorURL:location] texliveYear] != TLMDatabaseUnknownYear) {
        // disable refresh action for this view
        [_updateListDataSource setRefreshing:YES];
        TLMListUpdatesOperation *op = [[TLMListUpdatesOperation alloc] initWithLocation:location];
        [self _addOperation:op selector:@selector(_handleListUpdatesFinishedNotification:) setRefreshingForDataSource:_updateListDataSource];
        [op release];
        TLMLog(__func__, @"Refreshing list of updated packages%C", TLM_ELLIPSIS);
    }
    else {
        // happens when network is down; this can be a 10-12 minute timeout with TL 2011
        TLMLog(__func__, @"Not updating package list, since the repository database version could not be determined");
        [self _displayStatusString:NSLocalizedString(@"Listing Failed", @"main window status string")
                        dataSource:_updateListDataSource];
    }
}

- (void)_handleUpdateFinishedNotification:(NSNotification *)aNote
{
    NSParameterAssert([NSThread isMainThread]);
    NSParameterAssert(NO == _updatingInfrastructure);
    
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
            
        [self _runUpdmapIfNeeded];
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
        NSString *statusString = NSLocalizedString(@"Update Succeeded", @"status message");
        [self _displayStatusString:statusString dataSource:_updateListDataSource];
        [self _postUserNotificationWithTitle:statusString];

    }
    [[[self window] toolbar] validateVisibleItems];
}

- (void)_handleInfrastructureUpdateFinishedNotification:(NSNotification *)aNote
{
    NSParameterAssert([NSThread isMainThread]);
    NSParameterAssert(_updatingInfrastructure);
    NSParameterAssert(NO == _infrastructureNeedsUpdate);
    
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
            _infrastructureNeedsUpdate = YES;
        }
        else {
            // successful infrastructure update; remove the infra package from the list manually
            // ??? when did TL quit using arch-specific texlive.infra packages?
            [_updateListDataSource removePackageNamed:@"texlive.infra"];
            // formerly called _refreshUpdatedPackageListFromLocation here
            [_updateListDataSource setPackageFilter:nil];
            NSString *statusString = NSLocalizedString(@"Infrastructure Update Succeeded", @"status message");
            [self _displayStatusString:statusString dataSource:_updateListDataSource];
            [self _postUserNotificationWithTitle:statusString];
        }
    }
    
    _updatingInfrastructure = NO;
    [[[self window] toolbar] validateVisibleItems];
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
        NSString *statusString = NSLocalizedString(@"Paper Size Change Failed", @"status message");
        [self _displayStatusString:statusString dataSource:_updateListDataSource];
        [self _postUserNotificationWithTitle:statusString];
    }
    [[[self window] toolbar] validateVisibleItems];
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
    [[[self window] toolbar] validateVisibleItems];
}

- (void)_handleBackupPruningFinishedNotification:(NSNotification *)aNote
{
    TLMBackupOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    if ([op failed]) {
        TLMLog(__func__, @"Pruning failed.  Error was: %@", [op errorMessages]);
        NSString *statusString = NSLocalizedString(@"Backup Pruning Failed", @"status message");
        [self _displayStatusString:statusString dataSource:_backupDataSource];
        [self _postUserNotificationWithTitle:statusString];
    }
    else {
        [_backupDataSource setNeedsUpdate:YES];
        [self _refreshCurrentDataSourceIfNeeded];
    }
    [[[self window] toolbar] validateVisibleItems];
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

- (void)_handleDocumentationOptionFinishedNotification:(NSNotification *)aNote
{
    TLMOptionOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    if ([op failed]) {
        TLMLog(__func__, @"Failed to change documentation option.  Error was: %@", [op errorMessages]);
        NSString *statusString = NSLocalizedString(@"Changing Documentation Option Failed", @"status message");
        [self _displayStatusString:statusString dataSource:_updateListDataSource];
        [self _postUserNotificationWithTitle:statusString];
    }
    [[[self window] toolbar] validateVisibleItems];
}

- (void)documentationSheetDidEnd:(NSWindow *)sheet returnCode:(TLMDocumentationReturnCode)rc contextInfo:(void *)context
{
    [sheet orderOut:self];
    TLMDocumentationController *tdc = context;
    [tdc autorelease];
    if (rc & TLMDocumentationChanged) {
        
        NSString *optString = [NSString stringWithFormat:@"%d", (rc & TLMDocumentationInstallLater) ? 1 : 0];
        TLMOptionOperation *change = [[TLMOptionOperation alloc] initWithKey:@"docfiles" value:optString];
        [self _addOperation:change selector:@selector(_handleDocumentationOptionFinishedNotification:) setRefreshingForDataSource:nil];
        [change release];
    }
    
    if (rc & TLMDocumentationInstallNow) {
        
        NSMutableArray *packageNames = [NSMutableArray array];
        for (TLMDatabasePackage *pkg in [[TLMDatabase localDatabase] packages]) {
            // avoid trying to reinstall the dummy TL package(s)
            if ([[pkg name] hasPrefix:@"00texlive"] == NO)
                [packageNames addObject:[pkg name]];
        }
        [self _installPackagesWithNames:packageNames reinstall:YES];
    }
}

- (void)_handleLaunchAgentInstallFinishedNotification:(NSNotification *)aNote
{
    TLMAuthorizedOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    if ([op isCancelled] == NO)
        TLMLog(__func__, @"Finished running launchd agent installer script");
    [[[self window] toolbar] validateVisibleItems];
}

- (void)launchAgentScriptUpdateAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)context
{
    if (NSAlertFirstButtonReturn == returnCode) {
        NSMutableArray *options = [NSMutableArray array];
        [options addObject:@"--install"];
        [options addObject:@"--script"];
        [options addObject:[[NSBundle mainBundle] pathForResource:@"update_check" ofType:@"py"]];     
        TLMOperation *installOp = [[TLMOperation alloc] initWithCommand:[[NSBundle mainBundle] pathForAuxiliaryExecutable:@"agent_installer.py"] options:options];
        [self _addOperation:installOp selector:@selector(_handleLaunchAgentInstallFinishedNotification:) setRefreshingForDataSource:nil];
        [installOp release];
    }
}

- (void)launchAgentControllerSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)context
{
    [sheet orderOut:self];
    TLMLaunchAgentController *lac = context;
    [lac autorelease];
    if (returnCode & TLMLaunchAgentChanged) {
        
        NSMutableArray *options = [NSMutableArray array];
                        
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
                
        TLMOperation *installOp = [[TLMOperation alloc] initWithCommand:[[NSBundle mainBundle] pathForAuxiliaryExecutable:@"agent_installer.py"] options:options];                     
        [self _addOperation:installOp selector:@selector(_handleLaunchAgentInstallFinishedNotification:) setRefreshingForDataSource:nil];
        [installOp release];
        
    }
}

- (void)texdistConfigSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)context
{
    [sheet orderOut:self];
    TLMTexdistConfigController *tcc = context;
    [tcc autorelease];
}

- (void)_handleLoadDatabaseFinishedNotification:(NSNotification *)aNote
{
    TLMLoadDatabaseOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    
    [_packageListDataSource setPackageNodes:[TLMDatabase packageNodesByMergingLocalWithMirror:[op updateURL]]];
    [_packageListDataSource setRefreshing:NO];
    [_packageListDataSource setNeedsUpdate:NO];
    
    NSString *statusString = nil;
    
    if ([op isCancelled])
        statusString = NSLocalizedString(@"Database Loading Cancelled", @"main window status string");
    else if ([op failed]) {
        statusString = NSLocalizedString(@"Database Loading Failed", @"main window status string");
        [self _postUserNotificationWithTitle:statusString];
    }
    
    [self _displayStatusString:statusString dataSource:_packageListDataSource];
    [[[self window] toolbar] validateVisibleItems];
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
    else if ([op failed]) {
        statusString = NSLocalizedString(@"Backup Listing Failed", @"main window status string");
        [self _postUserNotificationWithTitle:statusString];
    }
    else if ([[op backupNodes] count] ==0)
        statusString = NSLocalizedString(@"No Backups Available", @"main window status string");
        
    [self _displayStatusString:statusString dataSource:_backupDataSource];
    [_backupDataSource setRefreshing:NO];
    [[[self window] toolbar] validateVisibleItems];
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
    TLMLog(__func__, @"Refreshing list of all packages%C", TLM_ELLIPSIS);

    TLMLoadDatabaseOperation *op = [[TLMLoadDatabaseOperation alloc] initWithLocation:location offline:offline];
    [self _addOperation:op selector:@selector(_handleLoadDatabaseFinishedNotification:) setRefreshingForDataSource:_packageListDataSource];
    [op release];
    [[[self window] toolbar] validateVisibleItems];
}

- (void)alertForLogWindowDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    if (NSAlertFirstButtonReturn == returnCode) {
        [(TLMAppController *)[NSApp delegate] showLogWindow:nil];
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
                
        [self _runUpdmapIfNeeded];
        [self _refreshLocalDatabase];
        
        [_updateListDataSource setNeedsUpdate:YES];
        [_packageListDataSource setNeedsUpdate:YES];
        [_backupDataSource setNeedsUpdate:YES];
        
        [self _refreshCurrentDataSourceIfNeeded];
        
        // _handleInstallFinishedNotification: also gets called for _installDataSource, but that's pretty rare
        NSString *statusString = NSLocalizedString(@"Install Succeeded", @"status message");
        [self _displayStatusString:statusString dataSource:_packageListDataSource];
        [self _postUserNotificationWithTitle:statusString];

    }
    [[[self window] toolbar] validateVisibleItems];
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

- (void)_handleGPGInstallFinishedNotification:(NSNotification *)aNote
{
    TLMInstallOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];

    if ([op failed]) {
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"Failed to enable security validation of packages.", @"alert title")];
        [alert setInformativeText:NSLocalizedString(@"Installing gpg appears to have failed. Would you like to show the log now or ignore this warning?", @"alert message text")];
        [alert addButtonWithTitle:NSLocalizedString(@"Show Log", @"button title")];
        [alert addButtonWithTitle:NSLocalizedString(@"Ignore", @"button title")];
        [alert beginSheetModalForWindow:[self window]
                          modalDelegate:self
                         didEndSelector:@selector(alertForLogWindowDidEnd:returnCode:contextInfo:)
                            contextInfo:NULL];
    }
    
    NSString *statusString = NSLocalizedString(@"Security Validation Enabled", @"status message");
    [self _displayStatusString:statusString dataSource:_packageListDataSource];
    [self _postUserNotificationWithTitle:statusString];

    // finish the rest of -showWindow setup here
    [self goHome:nil];
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
        
        [self _runUpdmapIfNeeded];
        [self _refreshLocalDatabase];
        [_updateListDataSource setNeedsUpdate:YES];
        [_packageListDataSource setNeedsUpdate:YES];
        [_backupDataSource setNeedsUpdate:YES];
        
        [self _refreshCurrentDataSourceIfNeeded];
        NSString *statusString = NSLocalizedString(@"Removal Succeeded", @"status message");
        [self _displayStatusString:statusString dataSource:_packageListDataSource];
        [self _postUserNotificationWithTitle:statusString];
    }
    [[[self window] toolbar] validateVisibleItems];
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
                
        [self _runUpdmapIfNeeded];
        [self _refreshLocalDatabase];
        [_updateListDataSource setNeedsUpdate:YES];
        
        // no reason to refresh backups or package list after a restore
        [self _refreshCurrentDataSourceIfNeeded];
        
        // will get blown away by the refresh if backup isn't the current datasource, but that's okay
        NSString *statusString = NSLocalizedString(@"Restore Succeeded", @"status message");
        [self _displayStatusString:statusString dataSource:_backupDataSource];
        [self _postUserNotificationWithTitle:statusString];

    }        
    [[[self window] toolbar] validateVisibleItems];
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
        [(TLMAppController *)[NSApp delegate] openDisasterRecoveryPage:nil];
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
    [self _goHome];
    
    // web browser expectations
    [_updateListDataSource setNeedsUpdate:YES];
    [_packageListDataSource setNeedsUpdate:YES];
    [self _refreshCurrentDataSourceIfNeeded];
}

- (void)updateInfrastructure:(id)sender;
{
    [self _displayStatusString:nil dataSource:_updateListDataSource];
    TLMLog(__func__, @"Beginning user-requested infrastructure update%C", TLM_ELLIPSIS);
    _infrastructureNeedsUpdate = YES;
    [self _updateAllPackages];
}

- (void)updateInfrastructureFromCriticalRepository:(id)sender
{
    [self _displayStatusString:nil dataSource:_updateListDataSource];
    TLMLog(__func__, @"Beginning user-requested infrastructure update from tlcritical repo%C", TLM_ELLIPSIS);
    _infrastructureNeedsUpdate = YES;
    NSURL *repo = [NSURL URLWithString:[[NSUserDefaults standardUserDefaults] objectForKey:TLMTLCriticalRepository]];
    [self _updateAllPackagesFromRepository:repo];
}

- (void)changeDefaultMirror:(id)sender
{
    // validate the current URL if the user is editing it (only checks syntax, not reachability or versioning)
    if ([[self window] firstResponder] != [[self window] fieldEditor:YES forObject:_URLField] || [[self window] makeFirstResponder:nil])
        [TLMEnvironment setDefaultRepository:[self serverURL]];
}

- (void)reconfigureDistributions:(id)sender
{
    TLMTexdistConfigController *tcc = [TLMTexdistConfigController new];
    [NSApp beginSheet:[tcc window]
       modalForWindow:[self window]
        modalDelegate:self
       didEndSelector:@selector(texdistConfigSheetDidEnd:returnCode:contextInfo:)
          contextInfo:tcc];
}

- (void)configureDocumentation:(id)sender;
{
    TLMDocumentationController *tdc = [TLMDocumentationController new];
    [NSApp beginSheet:[tdc window]
       modalForWindow:[self window]
        modalDelegate:self
       didEndSelector:@selector(documentationSheetDidEnd:returnCode:contextInfo:)
          contextInfo:tdc];
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
        diagnostic = CFNetDiagnosticCreateWithURL(CFAllocatorGetDefault(), (CFURLRef)serverURL);
        [(id)diagnostic autorelease];
    }
    CFStringRef desc = NULL;
    if (nil == serverURL || (diagnostic && kCFNetDiagnosticConnectionDown == CFNetDiagnosticCopyNetworkStatusPassively(diagnostic, &desc))) {
        // this is basically a dummy URL that we pass through in offline mode
        serverURL = [NSURL fileURLWithPath:[[TLMEnvironment currentEnvironment] installDirectory] isDirectory:YES];
        if (NULL == desc) desc = CFRetain(CFSTR("unknown error"));
        TLMLog(__func__, @"Network connection is down (%@).  Trying local install database %@%C", desc, serverURL, TLM_ELLIPSIS);
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
        // make sure it's okay to call this with the multiplexer, just in case
        if ([aURL isMultiplexer])
            aURL = [[TLMEnvironment currentEnvironment] validServerURLFromURL:aURL];
        // if no valid URL, bad things are about to happen...
        if (nil == aURL)
            aURL = [[TLMEnvironment currentEnvironment] defaultServerURL];
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
    if (NO == _infrastructureNeedsUpdate) {
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
    // action sent from current datasource
    [self _displayStatusString:nil dataSource:_currentListDataSource];

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
    
    // action sent from list datasource only
    [self _displayStatusString:nil dataSource:_packageListDataSource];
    
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

#define SUPPRESS_PAPERSIZE_ALERT @"SuppressPaperSizeAlert"

- (void)_paperSizeMismatchAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    if (NSAlertFirstButtonReturn == returnCode) {
        [[alert window] orderOut:nil];
        [self changePapersize:nil];
    }        
    if ([[alert suppressionButton] state] == NSOnState)
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:SUPPRESS_PAPERSIZE_ALERT];
}

#define TLM_PAPERSIZE_CHECK_TASK_KEY @"paper size check task key"

- (void)_paperSizeCheckTerminated:(NSNotification *)note
{
    TLMTask *task = [note object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSTaskDidTerminateNotification object:task];
    
    NSString *currentSize = nil;
    NSInteger ret = [task terminationStatus];
    if (0 != ret) {
        TLMLog(__func__, @"Unable to determine current paper size for pdftex");
    }
    else if ([task outputString]) {
        NSArray *sizes = [[task outputString] componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        if ([sizes count])
            currentSize = [sizes objectAtIndex:0];
    }
    
    /*
     MacTeX installer checks paper size using this:
     
     PAPER=`sudo -u $USER defaults read com.apple.print.PrintingPrefs DefaultPaperID | perl -pe 's/^iso-//; s/^na-//'`
     
     Unfortunately, it apparently fails on Lion systems with a clean install, so this
     preference is likely being phased out or is just unreliable.  We now check at launch
     to avoid user confusion from this being set properly on some systems vs. others.
     */
    NSString *systemPaperSize = [[[[NSPrintInfo sharedPrintInfo] paperName] componentsSeparatedByString:@"-"] lastObject];
    TLMLog(__func__, @"System paper size = %@, pdftex paper size = %@", systemPaperSize, currentSize);
    
    if (currentSize && systemPaperSize && [systemPaperSize isEqualToString:currentSize] == NO) {
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:NSLocalizedString(@"TeX Live paper size does not match system default", @"alert title")];
        [alert setInformativeText:NSLocalizedString(@"Would you like to set the TeX Live paper size now?", @"alert text")];
        [alert addButtonWithTitle:NSLocalizedString(@"Yes", @"")];
        [alert addButtonWithTitle:NSLocalizedString(@"No", @"")];
        [alert setShowsSuppressionButton:YES];
        [alert beginSheetModalForWindow:[self window]
                          modalDelegate:self
                         didEndSelector:@selector(_paperSizeMismatchAlertDidEnd:returnCode:contextInfo:)
                            contextInfo:NULL];
    }
    
    NSParameterAssert([[[NSThread currentThread] threadDictionary] objectForKey:TLM_PAPERSIZE_CHECK_TASK_KEY]);
    [[[NSThread currentThread] threadDictionary] removeObjectForKey:TLM_PAPERSIZE_CHECK_TASK_KEY];
}

- (void)checkSystemPaperSize;
{
    // ignore the suppression key if we haven't checked this TL version
    NSString *lastSizeCheckVersionKey = @"TLMLastPaperSizeAlertVersionKey";
    const TLMDatabaseYear lastCheckedYear = [[NSUserDefaults standardUserDefaults] integerForKey:lastSizeCheckVersionKey];
    const TLMDatabaseYear currentYear = [[TLMEnvironment currentEnvironment] texliveYear];
    
    // !!! early return
    if ([[NSUserDefaults standardUserDefaults] boolForKey:SUPPRESS_PAPERSIZE_ALERT] && lastCheckedYear == currentYear)
        return;
    
    [[NSUserDefaults standardUserDefaults] setInteger:currentYear forKey:lastSizeCheckVersionKey];
    
    TLMTask *task = [TLMTask new];
    [task setLaunchPath:[[TLMEnvironment currentEnvironment] tlmgrAbsolutePath]];
    [task setArguments:[NSArray arrayWithObjects:@"pdftex", @"paper", @"--list", nil]];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_paperSizeCheckTerminated:)
                                                 name:NSTaskDidTerminateNotification 
                                               object:task];
    [task launch];

    /*
     Need to keep the task around long enough to pick up the notification, and
     clang squawks if I release in the callback.  Associated objects would be
     another way to do this.
     */
    [[[NSThread currentThread] threadDictionary] setObject:task forKey:TLM_PAPERSIZE_CHECK_TASK_KEY];
    [task release];
    
}

@end
