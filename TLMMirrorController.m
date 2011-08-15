//
//  TLMMirrorController.m
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 11/18/10.
/*
 This software is Copyright (c) 2010-2011
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
#import "TLMMirrorNode.h"
#import "TLMMirrorCell.h"
#import "TLMLogServer.h"
#import "TLMDatabase.h"

@interface TLMMirrorController (Private)
- (void)_loadDefaultSites;
@end


@implementation TLMMirrorController

@synthesize _outlineView;

- (id)init
{
    self = [self initWithWindowNibName:[self windowNibName]];
    if (self) {
        _textFieldCell = [[NSTextFieldCell alloc] initTextCell:@""];
        _mirrorCell = [[TLMMirrorCell alloc] initTextCell:@""];
        [self _loadDefaultSites];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_handleVersionCheckNotification:)
                                                     name:TLMDatabaseVersionCheckComplete
                                                   object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_mirrorRoot release];
    [_outlineView release];
    [_mirrorCell release];
    [_textFieldCell release];
    [super dealloc];
}

- (NSString *)windowNibName { return @"Mirrors"; }

static NSURL *__TLMTLNetURL(NSString *mirrorURLString)
{
    return [NSURL TLNetURLForMirror:[NSURL URLWithString:mirrorURLString]];
}

- (void)_loadDefaultSites
{
    if (_mirrorRoot)
        return;
    
    NSString *sitesFile = [[NSBundle mainBundle] pathForResource:@"CTAN.sites" ofType:@"plist"];
    NSDictionary *sites = [[NSDictionary dictionaryWithContentsOfFile:sitesFile] objectForKey:@"sites"];
    
    [_mirrorRoot autorelease];
    _mirrorRoot = [TLMMirrorNode new];
    
    TLMMirrorNode *customNode = [TLMMirrorNode new];
    [customNode setValue:[NSLocalizedString(@"Other Mirrors", @"mirror group title") uppercaseString]];
    [customNode setType:TLMMirrorNodeContinent];
    [_mirrorRoot addChild:customNode];
    [customNode release];
    
    TLMMirrorNode *multiplexorNode = [TLMMirrorNode new];
    [multiplexorNode setType:TLMMirrorNodeURL];
    [multiplexorNode setValue:__TLMTLNetURL(@"http://mirror.ctan.org/")];
    [customNode addChild:multiplexorNode];
    [multiplexorNode release];
    
    for (NSString *continent in sites) {
        
        TLMMirrorNode *continentNode = [TLMMirrorNode new];
        [continentNode setValue:[continent uppercaseString]];
        [continentNode setType:TLMMirrorNodeContinent];
        
        NSMutableDictionary *countryNodes = [NSMutableDictionary dictionary];
        
        for (NSDictionary *mirrorInfo in [sites objectForKey:continent]) {
            
            NSString *countryName = [mirrorInfo objectForKey:@"country"];
            TLMMirrorNode *countryNode = [countryNodes objectForKey:countryName];
            if (nil == countryNode) {
                countryNode = [TLMMirrorNode new];
                [countryNode setType:TLMMirrorNodeCountry];
                [countryNode setValue:countryName];
                [countryNodes setObject:countryNode forKey:countryName];
                [countryNode release];
            }
            
            for (NSString *URLString in [mirrorInfo objectForKey:@"urls"]) {
                TLMMirrorNode *URLNode = [TLMMirrorNode new];
                [URLNode setValue:__TLMTLNetURL(URLString)];
                [URLNode setType:TLMMirrorNodeURL];
                [countryNode addChild:URLNode];
                [URLNode release];
            }
                        
        }
        
        for (NSString *countryName in countryNodes)
            [continentNode addChild:[countryNodes objectForKey:countryName]];
        
        [_mirrorRoot addChild:continentNode];
        [continentNode release];
    }    
}

- (void)awakeFromNib
{        
    [_outlineView reloadData];
}

- (TLMMirrorNode *)_mirrorForURL:(NSURL *)aURL
{
    for (TLMMirrorNode *continentNode in _mirrorRoot) {
        
        for (TLMMirrorNode *countryNode in continentNode) {
            
            for (TLMMirrorNode *URLNode in countryNode) {
                
                NSParameterAssert([URLNode type] == TLMMirrorNodeURL);
                if ([[URLNode value] isEqual:aURL])
                    return URLNode;
            }
        }
    }
    return nil;
}

- (void)_handleVersionCheckNotification:(NSNotification *)aNote
{
    TLMLog(__func__, @"%@", [aNote userInfo]);
    TLMLog(__func__, @"mirror = %@", [self _mirrorForURL:[[aNote userInfo] objectForKey:@"URL"]]);
}

- (NSArray *)mirrorsMatchingSearchString:(NSString *)aString;
{
    NSMutableArray *array = [NSMutableArray array];
    for (TLMMirrorNode *continentNode in _mirrorRoot) {
        
        // if the search string is a particular continent, add all of its mirrors
        if ([continentNode type] != TLMMirrorNodeURL && [[continentNode value] caseInsensitiveCompare:aString] == NSOrderedSame) {
            
            for (TLMMirrorNode *countryNode in continentNode) {
                
                for (TLMMirrorNode *URLNode in countryNode) {
                    
                    NSParameterAssert([URLNode type] == TLMMirrorNodeURL);
                    [array addObject:[[URLNode value] absoluteString]];
                }
            }
        }
        else {
        
            for (TLMMirrorNode *countryNode in continentNode) {
                
                // if the search string is a particular country, add all of its mirrors
                if ([countryNode type] != TLMMirrorNodeURL && [[countryNode value] caseInsensitiveCompare:aString] == NSOrderedSame) {
                                         
                    for (TLMMirrorNode *URLNode in countryNode) {
                        
                        NSParameterAssert([URLNode type] == TLMMirrorNodeURL);
                        [array addObject:[[URLNode value] absoluteString]];
                    }
                }
                else {
                
                    // add specific mirrors from any continent
                    for (TLMMirrorNode *URLNode in countryNode) {
                        
                        NSParameterAssert([URLNode type] == TLMMirrorNodeURL);
                        NSString *urlString = [[URLNode value] absoluteString];
                        if ([urlString rangeOfString:aString].length)
                            [array addObject:urlString];
                    }
                }
            }
        }
    }
    return array;
}

#pragma mark NSOutlineView datasource

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)anIndex ofItem:(TLMMirrorNode *)item;
{
    return nil == item ? [_mirrorRoot childAtIndex:anIndex] : [item childAtIndex:anIndex];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(TLMMirrorNode *)item;
{
    return [item numberOfChildren];
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(TLMMirrorNode *)item;
{
    return nil == item ? [_mirrorRoot numberOfChildren] : [item numberOfChildren];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(TLMMirrorNode *)item;
{
    return [item valueForKey:[tableColumn identifier]];
}

- (void)outlineView:(TLMOutlineView *)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(TLMMirrorNode *)item;
{
    NSFont *defaultFont = [outlineView defaultFont];
    
    if ([item type] == TLMMirrorNodeCountry) {
        [cell setFont:[NSFont boldSystemFontOfSize:[defaultFont pointSize]]];
    }
    else if (defaultFont) {
        [cell setFont:defaultFont];
    }
}

- (NSCell *)outlineView:(NSOutlineView *)outlineView dataCellForTableColumn:(NSTableColumn *)tableColumn item:(TLMMirrorNode *)item
{
    if (nil == tableColumn) return nil;
    return [item type] == TLMMirrorNodeURL ? _mirrorCell : _textFieldCell;
}

- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(TLMMirrorNode *)item
{
    return [item type] == TLMMirrorNodeURL ? 21.0 : 17.0;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(TLMMirrorNode *)item
{
    return [item type] == TLMMirrorNodeContinent;
}

- (id)outlineView:(NSOutlineView *)outlineView itemForPersistentObject:(id)object;
{
    [self _loadDefaultSites];
    return [NSKeyedUnarchiver unarchiveObjectWithData:object];
}

- (id)outlineView:(NSOutlineView *)outlineView persistentObjectForItem:(TLMMirrorNode *)item;
{
    return [NSKeyedArchiver archivedDataWithRootObject:item];
}

- (BOOL)outlineView:(TLMOutlineView *)outlineView writeItems:(NSArray *)items toPasteboard:(NSPasteboard *)pasteboard;
{
    NSMutableArray *URLs = [NSMutableArray array];
        
    for (TLMMirrorNode *node in items) {
        
        if ([node type] != TLMMirrorNodeURL)
            continue;
        
        [URLs addObject:[node value]];
    }

    return [NSURL writeURLs:URLs toPasteboard:pasteboard];
}


- (void)outlineView:(TLMOutlineView *)outlineView writeSelectedRowsToPasteboard:(NSPasteboard *)pboard;
{
    NSMutableArray *URLs = [NSMutableArray array];
    
    for (TLMMirrorNode *node in [outlineView selectedItems]) {
        
        if ([node type] != TLMMirrorNodeURL)
            continue;
        
        [URLs addObject:[node value]];
    }
    
    if ([NSURL writeURLs:URLs toPasteboard:[NSPasteboard pasteboardWithName:NSGeneralPboard]] == NO)
        NSBeep();
}


@end
