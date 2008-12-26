//
//  TLMOutlineView.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/24/08.
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

#import "TLMOutlineView.h"

@interface TLMOutlineView ()

@property (readwrite, copy) NSString *fontNamePreferenceKey;
@property (readwrite, copy) NSString *fontSizePreferenceKey;

@end

@implementation TLMOutlineView

@synthesize fontNamePreferenceKey = _fontNamePreferenceKey;
@synthesize fontSizePreferenceKey = _fontSizePreferenceKey;

- (BOOL)dataSourceAllowsCopying
{
    return [[self dataSource] respondsToSelector:@selector(outlineView:writeSelectedRowsToPasteboard:)];
}

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem;
{
    if ([anItem action] == @selector(copy:))
        return [self numberOfSelectedRows] > 0 && [self dataSourceAllowsCopying];
    else if ([anItem action] == @selector(changeFont:))
        return ([self fontNamePreferenceKey] && [self fontSizePreferenceKey]);
    else
        return NO;
}

- (IBAction)copy:(id)sender;
{
    if ([self dataSourceAllowsCopying])
        [[self dataSource] outlineView:self writeSelectedRowsToPasteboard:[NSPasteboard generalPasteboard]];
    else
        NSBeep();
}

- (NSControlSize)cellControlSize 
{
    NSCell *dataCell = [[[self tableColumns] lastObject] dataCell];
    return nil == dataCell ? NSRegularControlSize : [dataCell controlSize];
}

- (void)setFont:(NSFont *)aFont
{
    NSParameterAssert(aFont);
    for (NSTableColumn *tc in [self tableColumns])
        [[tc dataCell] setFont:aFont];
}

- (void)changeFont:(id)sender 
{
    if ([self fontNamePreferenceKey] && [self fontSizePreferenceKey]) {
        
        NSString *fontName = [[NSUserDefaults standardUserDefaults] objectForKey:[self fontNamePreferenceKey]];
        float fontSize = [[NSUserDefaults standardUserDefaults] floatForKey:[self fontSizePreferenceKey]];
        NSFont *font = nil;
        
        // if not set, use the font from the nib
        if(fontName) {
            
            font = [NSFont fontWithName:fontName size:fontSize];
            if(nil == font)
                font = [NSFont controlContentFontOfSize:[NSFont systemFontSizeForControlSize:[self cellControlSize]]];
            font = [[NSFontManager sharedFontManager] convertFont:font];
            
            [[NSUserDefaults standardUserDefaults] setFloat:[font pointSize] forKey:[self fontSizePreferenceKey]];
            [[NSUserDefaults standardUserDefaults] setObject:[font fontName] forKey:[self fontNamePreferenceKey]];
            
            [self setFont:font];
            NSLayoutManager *lm = [NSLayoutManager new];
            [self setRowHeight:[lm defaultLineHeightForFont:font] + 2.0f];
            [lm release];
            
            [self tile];
            [self reloadData]; 
        }
    }
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    [self changeFont:nil];
}

- (void)setFontNamePreferenceKey:(NSString *)name sizePreferenceKey:(NSString *)size;
{
    NSParameterAssert(name && size);
    [self setFontNamePreferenceKey:name];
    [self setFontSizePreferenceKey:size];
}

- (NSArray *)selectedItems
{
    NSIndexSet *selIndexes = [self selectedRowIndexes];
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:[selIndexes count]];
    NSUInteger idx = [selIndexes firstIndex];
    while (NSNotFound != idx) {
        id item = [self itemAtRow:idx];
        if (item) [items addObject:item];
        idx = [selIndexes indexGreaterThanIndex:idx];
    }
    return items;
}

@end
