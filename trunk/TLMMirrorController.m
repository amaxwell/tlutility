//
//  TLMMirrorController.m
//  TeX Live Manager
//
//  Created by Adam R. Maxwell on 11/18/10.
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

#import "TLMMirrorController.h"

enum  {
    TLMMirrorNodeContinent = 0,
    TLMMirrorNodeCountry   = 1,
    TLMMirrorNodeURL       = 2
};
typedef NSInteger TLMMirrorNodeType;

@interface TLMMirrorNode : NSObject
{
@private
    TLMMirrorNodeType  _type;
    NSString          *_name;
    NSMutableArray    *_children;
}

@property (nonatomic, readwrite) NSString *name;
@property (nonatomic, readwrite) TLMMirrorNodeType *type;

- (void)addChild:(id)child;
- (id)childAtIndex:(NSUInteger)idx;


@end



@implementation TLMMirrorController

- (void)awakeFromNib
{
    
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
/*
- (void)outlineView:(TLMOutlineView *)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(TLMProfileNode *)item;
{
    NSFont *defaultFont = [outlineView defaultFont];
    
    if (([item type] & TLMProfileRoot) != 0) {
        [cell setFont:[NSFont boldSystemFontOfSize:[defaultFont pointSize]]];
    }
    else if (defaultFont) {
        [cell setFont:defaultFont];
    }
}

- (NSCell *)outlineView:(NSOutlineView *)outlineView dataCellForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    if (nil == tableColumn) return nil;
    if ([[tableColumn identifier] isEqualToString:@"value"] && [[item value] isKindOfClass:[NSValue class]]) {
        return _checkboxCell;
    }
    return [[[NSTextFieldCell alloc] initTextCell:@""] autorelease];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(TLMProfileNode *)item
{
    return [item type] & TLMProfileRoot;
}
*/

- (id)outlineView:(NSOutlineView *)outlineView itemForPersistentObject:(id)object;
{
    [self _loadRootNode];
    for (NSUInteger r = 0; r < [_rootNode numberOfChildren]; r++)
        if ([[[_rootNode childAtIndex:r] name] isEqualToString:object])
            return [_rootNode childAtIndex:r];
    return nil;
}

- (id)outlineView:(NSOutlineView *)outlineView persistentObjectForItem:(TLMProfileNode *)item;
{
    return [item name];
}

- (void)outlineView:(TLMOutlineView *)outlineView writeSelectedRowsToPasteboard:(NSPasteboard *)pboard;
{
    if ([outlineView numberOfRows] != [outlineView numberOfSelectedRows])
        return NSBeep();
    
    NSString *profileString = [TLMProfileNode profileStringWithRoot:_rootNode];
    [pboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    [pboard setString:profileString forType:NSStringPboardType];
}

@end
