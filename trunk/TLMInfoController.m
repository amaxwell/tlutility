//
//  TLMInfoController.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/7/08.
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

#import "TLMInfoController.h"
#import "TLMInfoOperation.h"
#import "TLMPackage.h"
#import "TLMOutputParser.h"
#import "TLMLogServer.h"
#import <FileView/FileView.h>
#import "NSMenu_TLMExtensions.h"
#import "TLMOutlineView.h"

@interface _TLMFileObject : NSObject
{
@private
    NSURL    *_URL;
    NSString *_name;
}

@property (readwrite, copy) NSURL *URL;
@property (readwrite, copy) NSString *name;

@end

@interface TLMInfoController()
@property (readwrite, copy) NSArray *fileObjects;
@property (readwrite, copy) NSArray *runfiles;
@property (readwrite, copy) NSArray *sourcefiles;
@property (readwrite, copy) NSArray *docfiles;
@end

static char _TLMInfoFileViewScaleObserverationContext;
static NSString * const TLMInfoFileViewIconScaleKey = @"TLMInfoFileViewIconScaleKey";

@implementation TLMInfoController

@synthesize _textView;
@synthesize _spinner;
@synthesize _tabView;
@synthesize _fileView;
@synthesize fileObjects = _fileObjects;
@synthesize runfiles = _runfiles;
@synthesize sourcefiles = _sourcefiles;
@synthesize docfiles = _docfiles;
@synthesize _outlineView;

+ (TLMInfoController *)sharedInstance
{
    static id sharedInstance = nil;
    if (nil == sharedInstance)
        sharedInstance = [[self alloc] init];
    return sharedInstance;
}

- (id)init
{
    self = [super initWithWindowNibName:[self windowNibName]];
    if (self) {
        _infoQueue = [NSOperationQueue new];
        [_infoQueue setMaxConcurrentOperationCount:1];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_fileView removeObserver:self forKeyPath:@"iconScale"];
    [_infoQueue cancelAllOperations];
    [_infoQueue release];
    [_textView release];
    [_spinner release];
    [_tabView release];
    [_fileView release];
    [_fileObjects release];
    [_runfiles release];
    [_sourcefiles release];
    [_docfiles release];
    [_outlineView release];
    [super dealloc];
}

- (void)_recenterSpinner
{
    if ([[_tabView selectedTabViewItem] isEqual:[_tabView tabViewItemAtIndex:0]] == NO) {
        NSRect windowFrame = [[self window] frame];
        windowFrame.origin = [[self window] convertScreenToBase:windowFrame.origin];
        NSRect bounds = [[_spinner superview] convertRect:windowFrame fromView:nil];
        NSSize spinnerSize = [_spinner bounds].size;
        NSPoint origin = NSMakePoint(NSMidX(bounds), NSMidY(bounds));
        origin.x -= (spinnerSize.width / 2);
        origin.y -= (spinnerSize.height / 2);
        NSRect spinnerFrame;
        spinnerFrame.size = spinnerSize;
        spinnerFrame.origin = origin;
        [_spinner setFrame:spinnerFrame];
        [[_spinner superview] setNeedsDisplay:YES];
    }
}    

- (void)handleContentViewBoundsChanged:(NSNotification *)aNote
{
    [self _recenterSpinner];
}

- (void)awakeFromNib
{
    [(NSPanel *)[self window] setBecomesKeyOnlyIfNeeded:YES];
    
    // I was not able to get the resizing struts to keep the spinner centered, so gave up on IB and resorted to code
    [[[self window] contentView] setPostsBoundsChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleContentViewBoundsChanged:) 
                                                 name:NSViewBoundsDidChangeNotification 
                                               object:[[self window] contentView]];
    
    [_spinner setUsesThreadedAnimation:YES];
    if ([[NSUserDefaults standardUserDefaults] objectForKey:TLMInfoFileViewIconScaleKey] != nil)
        [_fileView setIconScale:[[NSUserDefaults standardUserDefaults] doubleForKey:TLMInfoFileViewIconScaleKey]];
    [_fileView addObserver:self forKeyPath:@"iconScale" options:0 context:&_TLMInfoFileViewScaleObserverationContext];
    
    [_outlineView setFontNamePreferenceKey:@"TLMInfoOutlineViewFontName" sizePreferenceKey:@"TLMInfoOutlineViewFontSize"];
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == &_TLMInfoFileViewScaleObserverationContext) {
        [[NSUserDefaults standardUserDefaults] setDouble:[_fileView iconScale] forKey:TLMInfoFileViewIconScaleKey];
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}


- (void)cancel { [_infoQueue cancelAllOperations]; } 

- (NSString *)windowNibName { return @"InfoPanel"; }

// why is setting this in IB ignored for panels?
- (NSString *)windowFrameAutosaveName { return @"Info Panel"; }

- (void)_handleInfoOperationFinishedNotification:(NSNotification *)aNote
{
    TLMInfoOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    
    // do nothing for cancelled ops, since they're only cancelled if we're going to be showing info for another package
    if ([op isCancelled] == NO) {
        NSString *result = [op infoString];
        if (result) {
            NSArray *docURLs = [op documentationURLs];
            // let texdoc handle the sort order (if any)
            if ([docURLs count]) [[self window] setRepresentedURL:[docURLs objectAtIndex:0]];
            NSMutableArray *fileObjects = [NSMutableArray array];
            for (NSURL *aURL in docURLs) {
                _TLMFileObject *obj = [_TLMFileObject new];
                [obj setURL:aURL];
                [obj setName:[op packageName]];
                [fileObjects addObject:obj];
                [obj release];
            }
            [self setFileObjects:fileObjects];
            [_fileView reloadIcons];
            [[self window] setTitle:[op packageName]];
            [_textView setSelectedRange:NSMakeRange(0, 0)];
            id <TLMInfoOutput> output = [TLMOutputParser outputWithInfoString:result docURLs:docURLs];
            [[_textView textStorage] setAttributedString:[output attributedString]];
            
            [self setRunfiles:[output runfiles]];
            [self setSourcefiles:[output sourcefiles]];
            [self setDocfiles:[output docfiles]];
            [_outlineView reloadData];
            [_outlineView expandItem:nil expandChildren:YES];
            
        }
        else {
            [_textView setString:[NSString stringWithFormat:NSLocalizedString(@"Unable to find info for %@", @"error message for info panel"), [op packageName]]];
        }
        // only change tabs if we have something to show
        [_tabView selectFirstTabViewItem:nil];
        
        // let the spinner keep going if the op was cancelled, since this notification may be delivered after queueing another one
        [_spinner stopAnimation:nil];
    }
}

- (void)showInfoForPackage:(id <TLMInfo>)package
{
    // always clear the queue; this will trigger notifications for any cancelled operations
    [_infoQueue cancelAllOperations]; 
    
    if (nil != package) {
        
        TLMInfoOperation *op = [[TLMInfoOperation alloc] initWithPackageName:[package infoName]];
        if (op) {
            
            // clear previous title and file proxy icon
            [[self window] setTitle:[NSString stringWithFormat:NSLocalizedString(@"Searching%C", @"info panel title"), 0x2026]];
            [[self window] setRepresentedURL:nil];
            
            [self setFileObjects:nil];
            [_fileView reloadIcons];
            
            [self setRunfiles:nil];
            [self setSourcefiles:nil];
            [self setDocfiles:nil];
            [_outlineView reloadData];
            
            [_tabView selectLastTabViewItem:nil];
            [self _recenterSpinner];
            [_spinner startAnimation:nil];
            
            [[NSNotificationCenter defaultCenter] addObserver:self 
                                                     selector:@selector(_handleInfoOperationFinishedNotification:) 
                                                         name:TLMOperationFinishedNotification 
                                                       object:op];
            [_infoQueue addOperation:op];
            [op release];
            
            if ([[self window] isVisible] == NO)
                [self showWindow:self];
        }
    }
    else {
        [[self window] setTitle:NSLocalizedString(@"Nothing Selected", @"info panel title")];
        [[self window] setRepresentedURL:nil];
        [_textView setSelectedRange:NSMakeRange(0, 0)];
        [_textView setString:@""];
        [_spinner stopAnimation:nil];
        [self setFileObjects:nil];
        [_fileView reloadIcons];
        [self setRunfiles:nil];
        [self setSourcefiles:nil];
        [self setDocfiles:nil];
        [_outlineView reloadData];
        [_tabView selectFirstTabViewItem:nil];
    }        
}

- (BOOL)textView:(NSTextView *)aTextView clickedOnLink:(id)link atIndex:(NSUInteger)charIndex
{
    if ([link isKindOfClass:[NSURL class]])
        return [[NSWorkspace sharedWorkspace] openURL:link];
    else if ([link isKindOfClass:[NSString class]] && (link = [NSURL URLWithString:link]) != nil)
        return [[NSWorkspace sharedWorkspace] openURL:link];
    return NO;
}

#pragma mark FileView datasource

- (NSUInteger)numberOfIconsInFileView:(FileView *)aFileView;
{
    return [_fileObjects count];
}

- (NSURL *)fileView:(FileView *)aFileView URLAtIndex:(NSUInteger)anIndex;
{
    return [[_fileObjects objectAtIndex:anIndex] URL];
}

- (NSString *)fileView:(FileView *)aFileView subtitleAtIndex:(NSUInteger)anIndex;
{
    return [[_fileObjects objectAtIndex:anIndex] name];
}

#pragma mark FileView delegate

- (void)fileView:(FileView *)aFileView willPopUpMenu:(NSMenu *)aMenu onIconAtIndex:(NSUInteger)anIndex
{
    NSInteger idx = [aMenu indexOfItemWithTag:FVOpenMenuItemTag];
    if (-1 != idx)
        [aMenu insertOpenWithMenuForURL:[[_fileObjects objectAtIndex:anIndex] URL] atIndex:(idx + 1)];
}

#pragma mark Outline view

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item;
{
    if (nil == item) {
         switch (index) {
             case 0:
                 return _runfiles;
                 break;
             case 1:
                 return _sourcefiles;
                 break;
             case 2:
                 return _docfiles;
                 break;
             default:
                 break;
         }
    }
    return [item objectAtIndex:index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item { return [item isKindOfClass:[NSURL class]] == NO; }

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item 
{ 
    if (nil == item) return 3;
    return [item isKindOfClass:[NSArray class]] ? [item count] : 0; 
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item 
{ 
    if (item == _runfiles)
        return NSLocalizedString(@"Run Files", @"");
    if (item == _sourcefiles)
        return NSLocalizedString(@"Source Files", @"");
    if (item == _docfiles)
        return NSLocalizedString(@"Doc Files", @"");
    return item;
}

// optional methods
- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(id)item { return [item isKindOfClass:[NSURL class]] == NO; }

- (NSCell *)outlineView:(NSOutlineView *)outlineView dataCellForTableColumn:(NSTableColumn *)tableColumn item:(id)item;
{
    NSCell *dataCell = [tableColumn dataCell];
    if ([item isKindOfClass:[NSURL class]]) {
        NSFont *font = [dataCell font];
        dataCell = [[NSPathCell new] autorelease];
        // NSPathStylePopUp is the only one that doesn't look like crap in a table...maybe just a plain file/icon cell would be better
        [(NSPathCell *)dataCell setPathStyle:NSPathStylePopUp];
#warning delegate or action
        [dataCell setFont:font];
        [dataCell setEditable:NO];
    }
    return dataCell; 
}

@end

@implementation _TLMFileObject

@synthesize URL = _URL;
@synthesize name = _name;

- (void)dealloc
{
    [_URL release];
    [_name release];
    [super dealloc];
}

@end
