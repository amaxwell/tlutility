//
//  TLMLogDataSource.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/12/08.
/*
 This software is Copyright (c) 2008-2009
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
#import "TLMLogDataSource.h"
#import "TLMLogMessage.h"
#import "TLMLogServer.h"
#import "TLMTableView.h"

@implementation TLMLogDataSource

@synthesize _tableView;

- (id)init
{
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(_handleLogServerUpdateNotification:) 
                                                     name:TLMLogServerUpdateNotification 
                                                   object:[TLMLogServer sharedServer]];       
        _messages = [NSMutableArray new];
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
    
    [super dealloc];
}

- (void)_update
{
    // timer does not repeat
    _updateScheduled = NO;
    
    [_messages addObjectsFromArray:[[TLMLogServer sharedServer] messagesFromIndex:[_messages count]]];
    
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
    [pboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    NSArray *messages = [_messages objectsAtIndexes:[_tableView selectedRowIndexes]];
    [pboard setString:[messages componentsJoinedByString:@"\n"] forType:NSStringPboardType];
}

// do a fast literal search for newline characters, since we don't worry about surrogate pairs
static bool __TLMStringIsSingleLine(CFStringRef aString)
{
    CFStringInlineBuffer buffer;
    CFRange rng = CFRangeMake(0, CFStringGetLength(aString));
    CFStringInitInlineBuffer(aString, &buffer, rng);
    UniChar ch;
    CFIndex i;
    CFCharacterSetRef cset = CFCharacterSetGetPredefined(kCFCharacterSetNewline);
    for (i = 0; i < rng.length; i++) {
        ch = CFStringGetCharacterFromInlineBuffer(&buffer, i);
        if (CFCharacterSetIsCharacterMember(cset, ch))
            return false;
    }
    return true;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row;
{
    NSTableColumn *tc = [tableView tableColumnWithIdentifier:@"message"];
    static NSTextFieldCell *cell = nil;
    static CGFloat singleLineCellHeight = 0.0;
    if (nil == cell) {
        cell = [[tc dataCell] copy];
        [cell setStringValue:@"single line test"];
        singleLineCellHeight = [cell cellSize].height;
    }
    id obj = [self tableView:tableView objectValueForTableColumn:tc row:row];
    
    // !!! early return; take a faster path here for the common case, which reduces CPU usage by ~3x
    if (CFGetTypeID(obj) == CFStringGetTypeID() && __TLMStringIsSingleLine((CFStringRef)obj))
        return singleLineCellHeight;

    [cell setObjectValue:obj];
    
    // this has to set up a drawing context and use NSStringDrawing to figure out the height
    return [cell cellSize].height;
}

@end
