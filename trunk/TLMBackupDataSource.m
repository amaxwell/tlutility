//
//  TLMBackupDataSource.m
//  TeX Live Manager
//
/*
 This software is Copyright (c) 2010
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

#import "TLMBackupDataSource.h"
#import "TLMBackupNode.h"

@implementation TLMBackupDataSource

@synthesize outlineView = _outlineView;
@synthesize _controller;
@synthesize statusWindow = _statusWindow;
@synthesize lastUpdateURL = _lastUpdateURL;
@synthesize backupNodes = _backupNodes;
@synthesize _searchField;

- (id)init
{
    self = [super init];
    if (self) {
        _displayedBackupNodes = [NSMutableArray new];
        _sortDescriptors = [NSMutableArray new];
    }
    return self;
}

- (void)dealloc
{
    _controller = nil;
    [_outlineView setDelegate:nil];
    [_outlineView setDataSource:nil];
    [_outlineView release];
    [_backupNodes release];
    [_displayedBackupNodes release];
    [_searchField release];
    [_sortDescriptors release];
    [_lastUpdateURL release];
    [_statusWindow release];
    [super dealloc];
}

- (IBAction)search:(id)sender;
{
    
}

- (IBAction)showInfo:(id)sender;
{
    
}

- (IBAction)refreshList:(id)sender;
{
    
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)anIndex ofItem:(TLMBackupNode *)item;
{
    return (nil == item) ? [_displayedBackupNodes objectAtIndex:anIndex] : [item childAtIndex:anIndex];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(TLMBackupNode *)item;
{
    return (nil == item) ? YES : [item numberOfChildren];
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(TLMBackupNode *)item;
{
    return (nil == item) ? [_displayedBackupNodes count] : [item numberOfChildren];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item;
{
    return [item valueForKey:[tableColumn identifier]];
}

@end
