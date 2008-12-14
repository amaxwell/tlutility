//
//  TLMLogDataSource.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/12/08.
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
#import "TLMLogDataSource.h"
#import "TLMLogMessage.h"
#import "TLMLogServer.h"
#import "TLMTableView.h"

@interface TLMLogDataSource()
@property (readwrite, copy) NSArray *messages;
@end


@implementation TLMLogDataSource

@synthesize _tableView;
@synthesize messages = _messages;

+ (void)initialize
{
    // set up the server
    [TLMLogServer sharedServer];
}

- (id)init
{
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(_handleLogServerUpdateNotification:) 
                                                     name:TLMLogServerUpdateNotification 
                                                   object:[TLMLogServer sharedServer]];        
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

- (void)_handleLogServerUpdateNotification:(NSNotification *)aNote
{
    [self setMessages:[[TLMLogServer sharedServer] messages]];
    [_tableView reloadData];
    [_tableView scrollRowToVisible:([_tableView numberOfRows] - 1)];
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

@end
