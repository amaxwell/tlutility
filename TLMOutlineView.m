//
//  TLMOutlineView.m
//  TeX Live Utility
//
//  Created by Adam Maxwell on 12/24/08.
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

#import "TLMOutlineView.h"

@interface TLMOutlineView ()

@property (readwrite, copy) NSString *fontNamePreferenceKey;
@property (readwrite, copy) NSString *fontSizePreferenceKey;

@end

@implementation TLMOutlineView

@synthesize fontNamePreferenceKey = _fontNamePreferenceKey;
@synthesize fontSizePreferenceKey = _fontSizePreferenceKey;

- (void)dealloc
{
    [_fontNamePreferenceKey release];
    [_fontSizePreferenceKey release];
    [_defaultFont release];
    [super dealloc];
}

- (BOOL)dataSourceAllowsCopying
{
    return [[self dataSource] respondsToSelector:@selector(outlineView:writeSelectedRowsToPasteboard:)];
}

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal
{
    return isLocal ? NSDragOperationEvery : NSDragOperationCopy;
}

- (void)disableOutlineCells;
{
    _disableOutlineCells = YES;
    [self setNeedsDisplay:YES];
}

- (void)reloadData
{
    [super reloadData];
    if (_disableOutlineCells) {
        for (NSInteger row = 0; row < [self numberOfRows]; row++)
            [self expandItem:[self itemAtRow:row] expandChildren:YES];
    }
}

- (NSRect)frameOfOutlineCellAtRow:(NSInteger)row
{
    return _disableOutlineCells ? NSZeroRect : [super frameOfOutlineCellAtRow:row];
}

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem;
{
    if ([anItem action] == @selector(copy:))
        return [self numberOfSelectedRows] > 0 && [self dataSourceAllowsCopying];
    else if ([anItem action] == @selector(changeFont:))
        return ([self fontNamePreferenceKey] && [self fontSizePreferenceKey]);
    else
        return YES;
}

- (IBAction)copy:(id)sender;
{
    if ([self dataSourceAllowsCopying])
        [(id <TLMOutlineViewDataSource>)[self dataSource] outlineView:self writeSelectedRowsToPasteboard:[NSPasteboard generalPasteboard]];
    else
        NSBeep();
}

- (void)setFont:(NSFont *)aFont
{
    NSParameterAssert(aFont);
    for (NSTableColumn *tc in [self tableColumns])
        [[tc dataCell] setFont:aFont];
    
    NSLayoutManager *lm = [NSLayoutManager new];
    [self setRowHeight:[lm defaultLineHeightForFont:aFont] + 2.0f];
    [lm release];
    
    if ([[self delegate] respondsToSelector:@selector(outlineViewFontChanged:)])
        [(id <TLMOutlineViewDelegate>)[self delegate] outlineViewFontChanged:self];
    
    [self tile];
    [self reloadData];     
}

- (NSFont *)defaultFont;
{
    NSFont *font = nil;
    
    if ([self fontNamePreferenceKey] && [self fontSizePreferenceKey]) {
        
        NSString *fontName = [[NSUserDefaults standardUserDefaults] objectForKey:[self fontNamePreferenceKey]];
        float fontSize = [[NSUserDefaults standardUserDefaults] floatForKey:[self fontSizePreferenceKey]];
        
        // if not set, use the font from the nib
        if (fontName) {
            font = [NSFont fontWithName:fontName size:fontSize];
        }  
    }
    return font ? font : _defaultFont;
}

- (NSFont *)font
{
    return [[[[self tableColumns] lastObject] dataCell] font];
}

- (void)updateFontFromPreferences
{
    NSFont *font = [self defaultFont];
    if (font) [self setFont:font];
}

- (void)changeFont:(id)sender 
{
    if ([self fontNamePreferenceKey] && [self fontSizePreferenceKey]) {
        NSFont *font = [[NSFontManager sharedFontManager] convertFont:[self font]];
        if (font) {
            [[NSUserDefaults standardUserDefaults] setFloat:[font pointSize] forKey:[self fontSizePreferenceKey]];
            [[NSUserDefaults standardUserDefaults] setObject:[font fontName] forKey:[self fontNamePreferenceKey]];
            [self updateFontFromPreferences];
        }
    }
}

- (BOOL)becomeFirstResponder
{
    const BOOL ret = [super becomeFirstResponder];
    if (ret)
        [[NSFontManager sharedFontManager] setSelectedFont:[self font] isMultiple:NO];
    return ret;
}

- (void)setFontNamePreferenceKey:(NSString *)name sizePreferenceKey:(NSString *)size;
{
    NSParameterAssert(name && size);
    [self setFontNamePreferenceKey:name];
    [self setFontSizePreferenceKey:size];
    // need to update now, or we can end up clobbering this if it's set after -viewDidMoveToWindow
    [self updateFontFromPreferences];
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    [self updateFontFromPreferences];
    if (nil == _defaultFont)
        _defaultFont = [[self font] retain];
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
