//
//  TLMLogDataSource.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/12/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "TLMLogDataSource.h"
#import "TLMASLMessage.h"
#import "TLMASLStore.h"

@interface TLMLogDataSource()
@property (readwrite, copy) NSArray *messages;
@end


@implementation TLMLogDataSource

@synthesize _tableView;
@synthesize messages = _messages;

- (id)init
{
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(_handleStoreUpdateNotification:) 
                                                     name:TLMASLStoreUpdateNotification 
                                                   object:[TLMASLStore sharedStore]];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_updateTimer invalidate];
    
    [_tableView setDataSource:nil];
    [_tableView setDelegate:nil];
    [_tableView release];
    
    [_messages release];
    
    [super dealloc];
}

- (void)_handleStoreUpdateNotification:(NSNotification *)aNote
{
    [self setMessages:[[TLMASLStore sharedStore] messages]];
    [_tableView reloadData];
    [_tableView scrollRowToVisible:([_tableView numberOfRows] - 1)];
}

- (void)_timerFired:(NSTimer *)ignored
{
    [[TLMASLStore sharedStore] update];
}

- (void)startUpdates;
{
    _updateCount++;
    if (nil == _updateTimer)
        _updateTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(_timerFired:) userInfo:nil repeats:YES];
}

- (void)stopUpdates;
{
    _updateCount--;
    if (0 == _updateCount) {
        [_updateTimer performSelector:@selector(invalidate) withObject:nil afterDelay:5.0];
        _updateTimer = nil;
    }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView;
{
    return [_messages count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row;
{
    TLMASLMessage *msg = [_messages objectAtIndex:row];
    return [msg valueForKey:[tableColumn identifier]];
}

@end
