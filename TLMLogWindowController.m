//
//  TLMLogWindowController.m
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 07/17/11.
/*
 This software is Copyright (c) 2008-2012
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

#import "TLMLogWindowController.h"
#import "TLMPreferenceController.h"
#import "TLMLogMessage.h"
#import "TLMLogServer.h"
#import "TLMTableView.h"
#import "TLMSplitView.h"
#import "TLMLogWindow.h"

#define DEFAULT_HISTORY_MAX 14
#define DEFAULT_HISTORY_KEY @"LogHistoryMax"
#define ARCHIVE_FILENAME    @"Log Messages.plist"
#define ARCHIVE_TIMER_DELAY 30.0

#define SPLITVIEW_AUTOSAVE  @"Session table saved frame"

#define UPDATE_TIMER_DELAY  0.3

@implementation TLMLogWindowController

static NSDate *_currentSessionDate = nil;

@synthesize _messageTableView;
@synthesize _sessionTableView;
@synthesize _splitView;
@synthesize _searchField;
@synthesize dockingDelegate = _dockingDelegate;
@synthesize isWindowLoaded = _windowDidLoad;

+ (void)initialize
{
    if (nil == _currentSessionDate)
        _currentSessionDate = [NSDate new];
}

static NSString * __TLMLogArchivePath()
{
    static NSString *archivePath = nil;
    if (nil == archivePath) {
        archivePath = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) lastObject];
        NSString *appname = [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString *)kCFBundleNameKey];
        archivePath = [archivePath stringByAppendingPathComponent:appname];
        [[NSFileManager defaultManager] createDirectoryAtPath:archivePath withIntermediateDirectories:YES attributes:nil error:NULL];
        archivePath = [[archivePath stringByAppendingPathComponent:ARCHIVE_FILENAME] copy];
    }
    return archivePath;
}

static NSDate *__TLMLogDateWithString(NSString *string)
{
    return [NSDate dateWithTimeIntervalSinceReferenceDate:[string doubleValue]];
}

static NSString *__TLMLogStringFromDate(NSDate *date)
{
    return [NSString stringWithFormat:@"%f", [date timeIntervalSinceReferenceDate]];
}

- (id)init
{
    self = [self initWithWindowNibName:[self windowNibName]];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(_handleLogServerUpdateNotification:) 
                                                     name:TLMLogServerUpdateNotification 
                                                   object:[TLMLogServer sharedServer]];     
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(_handleSyncNotification:) 
                                                     name:TLMLogServerSyncNotification 
                                                   object:[TLMLogServer sharedServer]];  
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_handleApplicationTerminate:)
                                                     name:NSApplicationWillTerminateNotification
                                                   object:nil];

        _messagesByDate = [NSMutableDictionary new];
        [_messagesByDate setObject:[NSMutableArray array] forKey:_currentSessionDate];
        _displayedSessionDate = [_currentSessionDate copy];
        _displayedMessages = [NSMutableArray new];

        NSDictionary *archive = [NSDictionary dictionaryWithContentsOfFile:__TLMLogArchivePath()];
        
        // sort and prune to most recent HISTORY_MAX dates
        NSMutableArray *dates = [NSMutableArray array];
        for (NSString *dateString in archive)
            [dates addObject:__TLMLogDateWithString(dateString)];
        [dates sortUsingSelector:@selector(compare:)];
        
        // hidden default to set history limit; 0 is the default, nonzero is respected, and <0 is infinite
        NSInteger historyLimit = [[NSUserDefaults standardUserDefaults] integerForKey:DEFAULT_HISTORY_KEY];
        if (0 == historyLimit) historyLimit = DEFAULT_HISTORY_MAX;
        else if (historyLimit < 0) historyLimit = NSUIntegerMax;
        
        if ([dates count] > (NSUInteger)historyLimit)
            dates = (id)[dates subarrayWithRange:NSMakeRange([dates count] - historyLimit, historyLimit)];
        
        for (NSDate *date in dates) {
            NSMutableArray *messages = [NSMutableArray new];
            for (NSDictionary *plist in [archive objectForKey:__TLMLogStringFromDate(date)]) {
                TLMLogMessage *message = [[TLMLogMessage alloc] initWithPropertyList:plist];
                [messages addObject:message];
                [message release];
            }
            [_messagesByDate setObject:[[messages copy] autorelease] forKey:date];
            [messages release];
        }
        
        // pointer equality dictionary, non-copying (since TLMLogMessage is technically mutable)
        _rowHeights = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        
        // archive messages periodically, in case of crash or forced quit
        [NSTimer scheduledTimerWithTimeInterval:ARCHIVE_TIMER_DELAY target:self selector:@selector(_archiveTimerFired:) userInfo:nil repeats:YES];
        _lastArchiveCount = 0;
    }
    return self;    
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [_messageTableView setDataSource:nil];
    [_messageTableView setDelegate:nil];
    [_messageTableView release];
    
    [_sessionTableView setDataSource:nil];
    [_sessionTableView setDelegate:nil];
    [_sessionTableView release];
    
    [_displayedSessionDate release];
    [_messagesByDate release];
    if (_rowHeights) CFRelease(_rowHeights);
    [_splitView setDelegate:nil];
    [_splitView release];
    
    [_searchField release];
    [_displayedMessages release];
    
    [super dealloc];
}

- (NSString *)windowNibName { return @"LogWindow"; }

- (void)awakeFromNib
{
    /*
     Make sure both tables are in correct state before monkeying with the frames,
     since that can trigger table relayout.  Apparently the tableview is alive
     and its delegate has been set before this message has been sent, so this is
     too late to call -reloadData?  See Herb's messages to mactex on 26 Oct 2011.
     
     Note that windowWillLoad is too early to call -reloadData, since the outlets
     aren't hooked up yet.  I think a better workaround is to not set the datasource
     and delegate in the nib, but set them in code after everything is loaded.
     */
    
    [_messageTableView setDataSource:self];
    [_messageTableView setDelegate:self];
    [_messageTableView setFontNamePreferenceKey:@"TLMLogWindowMessageFontName"
                              sizePreferenceKey:@"TLMLogWindowMessageFontSize"];
    
    [_sessionTableView setDataSource:self];
    [_sessionTableView setDelegate:self];
    [_sessionTableView setFontNamePreferenceKey:@"TLMLogWindowSessionFontName"
                              sizePreferenceKey:@"TLMLogWindowSessionFontSize"];
    
    [_messageTableView reloadData];
    [_sessionTableView reloadData];
    
    // windowDidLoad is too late for this
    TLMLog(__func__, @"Loaded log window controller");
    _windowDidLoad = YES;

    NSArray *frameStrings = [[NSUserDefaults standardUserDefaults] stringArrayForKey:SPLITVIEW_AUTOSAVE];
    NSUInteger idx = 0;
    for (NSString *frameString in frameStrings)
        [[[_splitView subviews] objectAtIndex:idx++] setFrame:NSRectFromString(frameString)];
    [_splitView adjustSubviews];
}

- (void)setDockingDelegate:(id <TLMDockingWindowDelegate>)obj
{
    // make sure the delegate gets an initial notification
    _dockingDelegate = obj;
    if (_windowDidLoad && [[self window] isVisible])
        [_dockingDelegate dockableWindowGeometryDidChange:[self window]];
}

// only notify for explicit moves or resize via the mouse
- (BOOL)_shouldNotifyDockingDelegate
{
    return [[self window] isVisible] && [(TLMLogWindow *)[self window] isLeftMouseDragging];
}

- (void)windowDidResize:(NSNotification *)notification
{
    if ([self _shouldNotifyDockingDelegate])
        [_dockingDelegate dockableWindowGeometryDidChange:[self window]];
}

- (void)windowDidMove:(NSNotification *)notification;
{
    if ([self _shouldNotifyDockingDelegate])
        [_dockingDelegate dockableWindowGeometryDidChange:[self window]];    
}

- (void)splitViewDidResizeSubviews:(NSNotification *)aNotification
{
    // this is getting sent before awakeFromNib, which might be why the autosave name in the nib won't work
    if ([[self window] isVisible]) {
        NSMutableArray *frameStrings = [NSMutableArray array];
        for (NSView *view in [_splitView subviews])
            [frameStrings addObject:NSStringFromRect([view frame])];
        [[NSUserDefaults standardUserDefaults] setObject:frameStrings forKey:SPLITVIEW_AUTOSAVE];
    }
}

- (void)windowWillClose:(NSNotification *)aNote
{
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:TLMShowLogWindowPreferenceKey];
    [_dockingDelegate dockableWindowWillClose:[self window]];
}

- (void)windowDidBecomeKey:(NSNotification *)notification;
{
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:TLMShowLogWindowPreferenceKey];
}

- (void)_archiveAllSessions
{
    const NSUInteger currentCount = [[_messagesByDate objectForKey:_currentSessionDate] count];
    if (_lastArchiveCount != currentCount) {
        NSMutableDictionary *rootPlist = [NSMutableDictionary new];
        for (NSDate *date in _messagesByDate) {
            NSMutableArray *plistArray = [NSMutableArray new];
            for (TLMLogMessage *message in [_messagesByDate objectForKey:date])
                [plistArray addObject:[message propertyList]];
            // unfortunately, a plist must have strings as keys
            [rootPlist setObject:plistArray forKey:__TLMLogStringFromDate(date)];
            [plistArray release];
        }
        NSString *path = __TLMLogArchivePath();
        NSString *error;
        NSData *data = [NSPropertyListSerialization dataFromPropertyList:rootPlist format:NSPropertyListBinaryFormat_v1_0 errorDescription:&error];
        if (nil == data) {
            NSLog(@"Failed to create property list: %@", error);
            [error autorelease];
        } else if ([data writeToFile:path atomically:YES] == NO) {
            NSLog(@"Failed to save property list at %@", path);
        }
        [rootPlist release];
        _lastArchiveCount = currentCount;
    }
}

- (void)_handleApplicationTerminate:(NSNotification *)aNote
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self setDockingDelegate:nil];
    [self _archiveAllSessions];
}

- (void)_archiveTimerFired:(NSTimer *)ignored
{
    [self _archiveAllSessions];
}

- (void)showWindow:(id)sender
{
    [super showWindow:sender];
    [self search:nil];
    
    // showWindow is called in response to user action, so it's okay to force an update and scroll
    TLMLogServerSync();
    [_messageTableView scrollRowToVisible:([_messageTableView numberOfRows] - 1)];
    
    // send unconditionally, since this isn't in response to the parent window moving
    [_dockingDelegate dockableWindowGeometryDidChange:[self window]];    
}

- (void)_searchAndScroll:(BOOL)scroll
{
    [_displayedMessages removeAllObjects];
    if ([[_searchField stringValue] isEqualToString:@""]) {
        [_displayedMessages setArray:[_messagesByDate objectForKey:_displayedSessionDate]];
    }
    else {
        for (TLMLogMessage *msg in [_messagesByDate objectForKey:_displayedSessionDate]) {
            if ([msg matchesSearchString:[_searchField stringValue]])
                [_displayedMessages addObject:msg];
        }
    }
    [_messageTableView reloadData];
    if (scroll)
        [_messageTableView scrollRowToVisible:([_messageTableView numberOfRows] - 1)];
}

- (void)search:(id)sender;
{
    // Console.app always scrolls to end when searching
    [self _searchAndScroll:YES];
}

- (void)_update
{
    // timer does not repeat
    _updateScheduled = NO;
    
    NSArray *toAdd = [[TLMLogServer sharedServer] messagesFromIndex:[[_messagesByDate objectForKey:_currentSessionDate] count]];
    // !!! early return: nothing to do; may happen if the delayed perform arrives just before a sync notification
    if ([toAdd count] == 0)
        return;
    
    [[_messagesByDate objectForKey:_currentSessionDate] addObjectsFromArray:toAdd];
    
     // No drawing work needed if the window is not loaded or offscreen
    if (_windowDidLoad && [[self window] isVisible]) {
    
        BOOL shouldScroll = NO;
        NSUInteger rowCount = [_messageTableView numberOfRows];
        // scroll to the last row, unless the user has manually scrolled up (check before reloading!)
        if (0 == rowCount || (rowCount > 0 && NSIntersectsRect([_messageTableView visibleRect], [_messageTableView rectOfRow:(rowCount - 1)])))
            shouldScroll = YES; 
        
        [self _searchAndScroll:shouldScroll];
    }
    else {
        /*
         Noop if the outlet isn't set up yet.  Otherwise, a full UI update needed,
         but this will hopefully avoid the exceptions we see on 10.5 when window size
         changes (which affects column layout).  Update: it didn't fix that problem,
         but seems like a good idea anyway.
         */
        [_messageTableView noteNumberOfRowsChanged];
    }

}

- (void)_scheduleUpdate
{
    _updateScheduled = YES;
    
    // update the log in all common modes
    [self performSelector:@selector(_update) withObject:nil afterDelay:UPDATE_TIMER_DELAY inModes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
}    

- (void)_handleLogServerUpdateNotification:(NSNotification *)aNote
{
    if (NO == _updateScheduled)
        [self _scheduleUpdate];
}    

- (void)_handleSyncNotification:(NSNotification *)aNote
{
    [[self class] cancelPreviousPerformRequestsWithTarget:self selector:@selector(_update) object:nil];
    [self _update];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView;
{
    if (tableView == _messageTableView)
        return [_displayedMessages count];
    return [_messagesByDate count];
}

- (NSArray *)_sortedSessionDates
{ 
    NSArray *ascending = [[_messagesByDate allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSUInteger cnt = [ascending count];
    NSMutableArray *descending = [NSMutableArray arrayWithCapacity:cnt];
    while (cnt--)
        [descending addObject:[ascending objectAtIndex:cnt]];
    return descending;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row;
{
    if (tableView == _messageTableView) {
        TLMLogMessage *msg = [_displayedMessages objectAtIndex:row];
        return [msg valueForKey:[tableColumn identifier]];
    }
    else {
        return [[self _sortedSessionDates] objectAtIndex:row];
    }
}

- (void)tableView:(TLMTableView *)tableView writeSelectedRowsToPasteboard:(NSPasteboard *)pboard;
{
    if (tableView == _sessionTableView) {
        NSBeep();
        return;
    }
    
    NSParameterAssert(tableView == _messageTableView);
    [pboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    if ([[tableView selectedRowIndexes] count]) {
        NSArray *messages = [_displayedMessages objectsAtIndexes:[tableView selectedRowIndexes]];
        [pboard setString:[messages componentsJoinedByString:@"\n"] forType:NSStringPboardType];
    }
    else if ([[tableView selectedColumnIndexes] count]) {
        NSArray *columns = [[tableView tableColumns] objectsAtIndexes:[tableView selectedColumnIndexes]];
        NSMutableString *string = [NSMutableString string];
        for (NSInteger row = 0; row < [self numberOfRowsInTableView:tableView]; row++) {
            for (NSTableColumn *col in columns)
                [string appendFormat:@"%@\t", [self tableView:tableView objectValueForTableColumn:col row:row]];
            [string appendString:@"\n"];
        }
        [pboard setString:string forType:NSStringPboardType];
    }
}

- (void)tableViewColumnDidResize:(NSNotification *)aNotification
{
    // changing width will change height, but tableview doesn't know that
    CFDictionaryRemoveAllValues(_rowHeights);
    [_messageTableView noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [_displayedMessages count])]];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    if ([notification object] == _sessionTableView) {
        // clear selection so we don't get into an odd highlight state
        [_messageTableView deselectAll:nil];
        
        [_displayedSessionDate autorelease];
        _displayedSessionDate = [[[self _sortedSessionDates] objectAtIndex:[_sessionTableView selectedRow]] copy];
        CFDictionaryRemoveAllValues(_rowHeights);
        [self _searchAndScroll:NO];
    }
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row;
{
    
    if (tableView == _sessionTableView)
        return [[[[tableView tableColumns] lastObject] dataCell] cellSize].height;
    
    const NSInteger nr = [self numberOfRowsInTableView:tableView];
    if (row >= nr || nr < 0) {
        // !!! workaround for 10.5.8 bug: can't call -reloadData here
        TLMLog(__func__, @"Working around a crash: %@ asked for row index %ld, but the datasource has %ld rows.", [tableView class], (long)row, (long)nr);
        return [[[[tableView tableColumns] lastObject] dataCell] cellSize].height;
    }
    
    // base height on message cell
    NSTableColumn *tc = [tableView tableColumnWithIdentifier:@"message"];
    id obj = [self tableView:tableView objectValueForTableColumn:tc row:row];
    
    // calculating on-the-fly really slows down for a large number of rows, so we cache height by message
    CFNumberRef height = NULL;
    
    // if object is nil, compute using the cell for a nil object
    if (obj) height = CFDictionaryGetValue(_rowHeights, obj);
    
    if (NULL == height) {
        
        // pass an "infinitely" tall rect for cell bounds, and let the cell figure out the string height it needs
        NSRect cellBounds = NSZeroRect;
        cellBounds.size = NSMakeSize([tc width], CGFLOAT_MAX);
        NSTextFieldCell *cell = [tc dataCellForRow:row];
        // presently NSString, but may be attributed in future...
        [cell setObjectValue:obj];
        
        // use an autoreleased instance, since we may not add it to the dictionary
        height = (CFNumberRef)[NSNumber numberWithFloat:[cell cellSizeForBounds:cellBounds].height];
        if (obj) CFDictionarySetValue(_rowHeights, obj, height);
        
    }
    return [(NSNumber *)height floatValue];
}

@end

@implementation TLMLogMessageCell

- (id)initTextCell:(NSString *)str
{
    self = [super initTextCell:str];
    [self setWraps:YES];
    return self;
}

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    [self setWraps:YES];
    return self;
}

// full content is always drawn, since we provide a sufficiently tall row
- (NSRect)expansionFrameWithFrame:(NSRect)cellFrame inView:(NSView *)view 
{ 
    return NSZeroRect;
}

@end
