//
//  TLMLogWindowController.m
//  TeX Live Manager
//
//  Created by Adam R. Maxwell on 07/17/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "TLMLogWindowController.h"
#import "TLMLogMessage.h"
#import "TLMLogServer.h"
#import "TLMTableView.h"

@implementation TLMLogWindowController

@synthesize _tableView;

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
        _messages = [NSMutableArray new];
        
        // pointer equality dictionary, non-copying (since TLMLogMessage is technically mutable)
        _rowHeights = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    }
    return self;    
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [_tableView setDataSource:nil];
    [_tableView setDelegate:nil];
    [_tableView release];
    
    [_messages release];
    if (_rowHeights) CFRelease(_rowHeights);
    
    [super dealloc];
}

- (NSString *)windowNibName { return @"LogWindow"; }

- (void)_update
{
    // timer does not repeat
    _updateScheduled = NO;
    
    NSArray *toAdd = [[TLMLogServer sharedServer] messagesFromIndex:[_messages count]];
    // nothing to do; may happen if the delayed perform arrives just before a sync notification
    if ([toAdd count] == 0)
        return;
    
    [_messages addObjectsFromArray:toAdd];
    
    BOOL shouldScroll = NO;
    NSUInteger rowCount = [_tableView numberOfRows];
    // scroll to the last row, unless the user has manually scrolled up (check before reloading!)
    if (0 == rowCount || (rowCount > 0 && NSIntersectsRect([_tableView visibleRect], [_tableView rectOfRow:(rowCount - 1)])))
        shouldScroll = YES; 
    
    [_tableView reloadData];
    
    // remember to call -numberOfRows again since it just changed...
    if (shouldScroll)
        [_tableView scrollRowToVisible:([_tableView numberOfRows] - 1)];
}

- (void)_scheduleUpdate
{
    _updateScheduled = YES;
    
    // update the log in all common modes
    [self performSelector:@selector(_update) withObject:nil afterDelay:0.3 inModes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
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
    return [_messages count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row;
{
    TLMLogMessage *msg = [_messages objectAtIndex:row];
    return [msg valueForKey:[tableColumn identifier]];
}

- (void)tableView:(TLMTableView *)tableView writeSelectedRowsToPasteboard:(NSPasteboard *)pboard;
{
    NSParameterAssert(tableView == _tableView);
    [pboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    if ([[tableView selectedRowIndexes] count]) {
        NSArray *messages = [_messages objectsAtIndexes:[tableView selectedRowIndexes]];
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
    [_tableView noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [_messages count])]];
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row;
{
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
