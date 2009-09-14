//
//  TLMInstallDataSource.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 09/10/09.
/*
 This software is Copyright (c) 2009
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

#import "TLMInstallDataSource.h"
#import "TLMProfileNode.h"

@implementation TLMInstallDataSource

@synthesize lastUpdateURL = _lastUpdateURL;
@synthesize statusWindow = _statusWindow;
@synthesize outlineView = _outlineView;
@synthesize _controller;

- (void)dealloc
{
    [_outlineView release];
    [_rootNode release];
    [_controller release];
    [_lastUpdateURL release];
    [_statusWindow release];
    [_checkboxCell release];
    [super dealloc];
}

- (void)awakeFromNib
{
    _rootNode = [TLMProfileNode newDefaultProfile];
    _checkboxCell = [[NSButtonCell alloc] initTextCell:@""];
    [_checkboxCell setButtonType:NSSwitchButton];
    [_checkboxCell setControlSize:NSSmallControlSize];
    [_checkboxCell setTarget:self];
    [_checkboxCell setAction:@selector(changeBoolean:)];
    [_outlineView reloadData];
}

- (void)changeBoolean:(id)sender
{
    TLMProfileNode *node = nil;
    if ([_outlineView clickedRow] >= 0)
        node = [_outlineView itemAtRow:[_outlineView clickedRow]];

    BOOL currentValue = [[node value] boolValue];
    [node setValue:[NSNumber numberWithBool:(!currentValue)]];
    [_outlineView reloadItem:node];
}

#pragma mark NSOutlineView datasource

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)anIndex ofItem:(TLMProfileNode *)item;
{
    return nil == item ? [_rootNode childAtIndex:anIndex] : [item childAtIndex:anIndex];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(TLMProfileNode *)item;
{
    return [item type] & TLMProfileRoot && [item numberOfChildren];
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(TLMProfileNode *)item;
{
    return nil == item ? [_rootNode numberOfChildren] : [item numberOfChildren];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(TLMProfileNode *)item;
{
    id value = [item valueForKey:[tableColumn identifier]];
    if ([item type] & TLMProfileRoot) {
        value = [value uppercaseString];
    }
    return value;
}

- (NSCell *)outlineView:(NSOutlineView *)outlineView dataCellForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    if (nil == tableColumn) return nil;
    if ([[tableColumn identifier] isEqualToString:@"value"] && [[item value] isKindOfClass:[NSValue class]]) {
        return _checkboxCell;
    }
    return [tableColumn dataCell];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(TLMProfileNode *)item
{
    return [item type] & TLMProfileRoot;
}

- (void)outlineView:(NSOutlineView *)outlineView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn byItem:(id)item;
{
    NSParameterAssert([[tableColumn identifier] isEqualToString:@"value"]);
    [item setValue:object];
    
    NSFileHandle *fh = [NSFileHandle fileHandleWithStandardOutput];
    [fh writeData:[[TLMProfileNode profileStringWithRoot:_rootNode] dataUsingEncoding:NSUTF8StringEncoding]];
}

@end
