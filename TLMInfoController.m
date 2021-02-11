//
//  TLMInfoController.m
//  TeX Live Utility
//
//  Created by Adam Maxwell on 12/7/08.
/*
 This software is Copyright (c) 2008-2016
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
#import "TLMTask.h"
#import "TLMEnvironment.h"

#import "TLMDatabase.h"
#import "TLMDatabasePackage.h"

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
@end

static char _TLMInfoFileViewScaleObserverationContext;
static NSString * const TLMInfoFileViewIconScaleKey = @"TLMInfoFileViewIconScaleKey";

@implementation TLMInfoController

@synthesize _textView;
@synthesize _spinner;
@synthesize _tabView;
@synthesize _fileView;
@synthesize fileObjects = _fileObjects;
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
        
        // keep mutable arrays so we can do pointer comparison in datasource methods
        _runfiles = [NSMutableArray new];
        _sourcefiles = [NSMutableArray new];
        _docfiles = [NSMutableArray new];
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
    [_clickedCell release];
    [super dealloc];
}

- (void)_recenterSpinner
{
    if ([[_tabView selectedTabViewItem] isEqual:[_tabView tabViewItemAtIndex:0]] == NO) {
        NSRect windowFrame = [[self window] convertRectFromScreen:[[self window] frame]];
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
    
    // Too bad this isn't the default on Mojave...
    if (@available(macOS 10.14, *)) {
        [_textView setUsesAdaptiveColorMappingForDarkAppearance:YES];
    }
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
            
            [_runfiles setArray:[output runFiles]];
            [_sourcefiles setArray:[output sourceFiles]];
            [_docfiles setArray:[output docFiles]];
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

static NSArray * __TLMURLsFromTexdocOutput2(NSString *outputString)
{
    
    /*
     http://tug.org/mailman/private/texdoc/2009-November/000120.html
     
     Message from mpg:
     
     I also made another change, as a preparation for next version. So the
     final (or so I hope) format is:
     
     argument <tab> score <tab> filename
     
     as in:
     
     foo	1	/path/a
     foo	0	/path/b
     bar	1	/path/c
     
     Currently the score doesn't mean anything, you can just consider it as
     dummy values. But in future versions, there should be a scoring system
     in texdoc, and the score will be a real value. (I intend to use this
     info in coverage-check scripts, but maybe you'll want to use it in some
     way too. I'll keep you informed when the score will become meaningful.)
     
     stokes:tmp amaxwell$ texdoc --version
     texdoc 0.60
     stokes:tmp amaxwell$ texdoc -l -I -M makeindex
     makeindex	10	/usr/local/texlive/2009/texmf-dist/doc/support/makeindex/makeindex.pdf
     makeindex	1.5	/usr/local/texlive/2009/texmf-dist/doc/support/makeindex/ind.pdf
     makeindex	1	/usr/local/texlive/2009/texmf/doc/man/man1/makeindex.man1.pdf
     makeindex	1	/usr/local/texlive/2009/texmf-dist/doc/generic/FAQ-en/html/FAQ-makeindex.html
     */
    
    NSArray *lines = [outputString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableArray *docURLs = [NSMutableArray arrayWithCapacity:[lines count]];
    
    for (NSString *line in lines) {
        
        NSArray *comps = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([comps count] < 3) continue;
        
        NSURL *aURL = [NSURL fileURLWithPath:[comps objectAtIndex:2]];
        if (aURL) [docURLs addObject:aURL];
    }
    
    return docURLs;
}

- (NSArray *)_texdocForPackage:(TLMDatabasePackage *)package
{
    // avoid returning junk results, because texdoc tries too hard
    if ([package isInstalled] == NO)
        return nil;
    
    NSString *cmd = [[TLMEnvironment currentEnvironment] texdocAbsolutePath];
        
    // !!! bail out early if the file doesn't exist
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:cmd] == NO) {
        TLMLog(__func__, @"%@ does not exist or is not executable", cmd);
        return nil;
    }
    
    /*
     The full package name for tlmgr contains names like "bin-dvips.universal-darwin", where
     the relevant bit as far as texdoc is concerned is "dvips".
     */
    NSString *packageName = [package name];
    
    // see if we have a "bin-" prefix
    NSRange r = [packageName rangeOfString:@"bin-"];
    
    // not clear if collection names are meaningful to texdoc but try anyway...
    if (0 == r.length)
        r = [packageName rangeOfString:@"collection-"];
    
    // remove the prefix
    if (r.length)
        packageName = [packageName substringFromIndex:NSMaxRange(r)];
    
    // now look for architecture and remove e.g. ".universal-darwin"
    r = [packageName rangeOfString:@"." options:NSBackwardsSearch];
    if (r.length)
        packageName = [packageName substringToIndex:r.location];
    
    TLMTask *task = [[TLMTask new] autorelease];
    [task setLaunchPath:cmd];
    [task setArguments:[NSArray arrayWithObjects:@"--list", @"--nointeract", @"--machine", packageName, nil]];
    [task launch];
    
    int status = -1;
    [task waitUntilExit];
    status = [task terminationStatus];
    
    return (status == EXIT_SUCCESS && [task outputString]) ? __TLMURLsFromTexdocOutput2([task outputString]) : nil;

}    

- (NSAttributedString *)_attributedStringForPackage:(TLMDatabasePackage *)package docURLs:(NSArray *)docURLs
{
    NSMutableAttributedString *attrString = [[[NSMutableAttributedString alloc] init] autorelease];
    
    NSString *value;
    NSUInteger previousLength;
    NSFont *userFont = [NSFont userFontOfSize:0.0];
    NSFont *boldFont = [[NSFontManager sharedFontManager] convertFont:userFont toHaveTrait:NSBoldFontMask];
    
    value = [package name];
    if (value) {
        previousLength = [attrString length];
        [[attrString mutableString] appendString:NSLocalizedString(@"Package:", @"heading in info panel")];
        [attrString addAttribute:NSFontAttributeName value:boldFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        
        previousLength = [attrString length];
        [[attrString mutableString] appendFormat:@" %@\n\n", value];
        [attrString addAttribute:NSFontAttributeName value:userFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
    }
    
    value = [package shortDescription];
    if (value) {
        previousLength = [attrString length];
        [[attrString mutableString] appendString:NSLocalizedString(@"Summary:", @"heading in info panel")];
        [attrString addAttribute:NSFontAttributeName value:boldFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        
        previousLength = [attrString length];
        [[attrString mutableString] appendFormat:@" %@\n\n", value];
        [attrString addAttribute:NSFontAttributeName value:userFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
    }
    
    previousLength = [attrString length];
    [[attrString mutableString] appendString:NSLocalizedString(@"Status:", @"heading in info panel")];
    [attrString addAttribute:NSFontAttributeName value:boldFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
    if ([package isInstalled]) {
        value = NSLocalizedString(@"Installed", @"status for package");
    }
    else {
        value = NSLocalizedString(@"Not installed", @"status for package");
    }
    previousLength = [attrString length];
    [[attrString mutableString] appendFormat:@" %@\n\n", value];
    [attrString addAttribute:NSFontAttributeName value:userFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
    
    value = [package longDescription];
    if (value) {
        previousLength = [attrString length];
        [[attrString mutableString] appendString:NSLocalizedString(@"Description:\n", @"heading in info panel")];
        [attrString addAttribute:NSFontAttributeName value:boldFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        
        previousLength = [attrString length];
        [[attrString mutableString] appendFormat:@"%@\n", value];
        [attrString addAttribute:NSFontAttributeName value:userFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
    }
        
    // documentation from texdoc
    if ([docURLs count]) {
        previousLength = [attrString length];
        [[attrString mutableString] appendString:NSLocalizedString(@"\nDocumentation:\n", @"heading in info panel")];
        [attrString addAttribute:NSFontAttributeName value:boldFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        
        for (NSURL *docURL in docURLs) {
            previousLength = [attrString length];
            [[attrString mutableString] appendString:[[docURL path] lastPathComponent]];
            [attrString addAttribute:NSFontAttributeName value:userFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            [attrString addAttribute:NSLinkAttributeName value:docURL range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            [attrString addAttribute:NSCursorAttributeName value:[NSCursor pointingHandCursor] range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            
            previousLength = [attrString length];
            [[attrString mutableString] appendString:@"\n"];
            [attrString removeAttribute:NSLinkAttributeName range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        }        
    }
    
    NSArray *runURLs = [package runFiles];
    if ([runURLs count]) {
        previousLength = [attrString length];
        [[attrString mutableString] appendString:NSLocalizedString(@"\nRun Files:\n", @"heading in info panel")];
        [attrString addAttribute:NSFontAttributeName value:boldFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        
        for (NSURL *aURL in runURLs) {
            previousLength = [attrString length];
            [[attrString mutableString] appendString:[[aURL path] lastPathComponent]];
            [attrString addAttribute:NSFontAttributeName value:userFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            [attrString addAttribute:NSLinkAttributeName value:aURL range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            [attrString addAttribute:NSCursorAttributeName value:[NSCursor pointingHandCursor] range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            
            previousLength = [attrString length];
            [[attrString mutableString] appendString:@"\n"];
            [attrString removeAttribute:NSLinkAttributeName range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        }        
    }
    
    NSArray *sourceURLs = [package sourceFiles];
    if ([sourceURLs count]) {
        previousLength = [attrString length];
        [[attrString mutableString] appendString:NSLocalizedString(@"\nSource Files:\n", @"heading in info panel")];
        [attrString addAttribute:NSFontAttributeName value:boldFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        
        for (NSURL *aURL in sourceURLs) {
            previousLength = [attrString length];
            [[attrString mutableString] appendString:[[aURL path] lastPathComponent]];
            [attrString addAttribute:NSFontAttributeName value:userFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            [attrString addAttribute:NSLinkAttributeName value:aURL range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            [attrString addAttribute:NSCursorAttributeName value:[NSCursor pointingHandCursor] range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            
            previousLength = [attrString length];
            [[attrString mutableString] appendString:@"\n"];
            [attrString removeAttribute:NSLinkAttributeName range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        }        
    }
    
    docURLs = [package docFiles];
    if ([docURLs count]) {
        previousLength = [attrString length];
        [[attrString mutableString] appendString:NSLocalizedString(@"\nDoc Files:\n", @"heading in info panel")];
        [attrString addAttribute:NSFontAttributeName value:boldFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        
        for (NSURL *aURL in docURLs) {
            previousLength = [attrString length];
            [[attrString mutableString] appendString:[[aURL path] lastPathComponent]];
            [attrString addAttribute:NSFontAttributeName value:userFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            [attrString addAttribute:NSLinkAttributeName value:aURL range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            [attrString addAttribute:NSCursorAttributeName value:[NSCursor pointingHandCursor] range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            
            previousLength = [attrString length];
            [[attrString mutableString] appendString:@"\n"];
            [attrString removeAttribute:NSLinkAttributeName range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        }        
    }
    
    return attrString;
}

- (void)_updateWithPackage:(TLMDatabasePackage *)package
{    
    NSArray *docURLs = [self _texdocForPackage:package];
    // let texdoc handle the sort order (if any)
    if ([docURLs count]) [[self window] setRepresentedURL:[docURLs objectAtIndex:0]];
    NSMutableArray *fileObjects = [NSMutableArray array];
    for (NSURL *aURL in docURLs) {
        _TLMFileObject *obj = [_TLMFileObject new];
        [obj setURL:aURL];
        [obj setName:[package name]];
        [fileObjects addObject:obj];
        [obj release];
    }
    [self setFileObjects:fileObjects];
    [_fileView reloadIcons];
    
    [[self window] setTitle:[package name]];
    [_textView setSelectedRange:NSMakeRange(0, 0)];
    [[_textView textStorage] setAttributedString:[self _attributedStringForPackage:package docURLs:docURLs]];
    
    [_runfiles setArray:[package runFiles]];
    [_sourcefiles setArray:[package sourceFiles]];
    [_docfiles setArray:[package docFiles]];
    
    [_outlineView reloadData];
    [_outlineView expandItem:nil expandChildren:YES];

    if ([[self window] isVisible] == NO)
        [self showWindow:self];
    
}

- (void)showInfoForPackage:(id <TLMInfo>)package location:(NSURL *)mirrorURL
{
    // always clear the queue; this will trigger notifications for any cancelled operations
    [_infoQueue cancelAllOperations]; 
    
    if (nil != package) {
        
        TLMInfoOperation *op = [[[TLMInfoOperation alloc] initWithPackageName:[package infoName] location:mirrorURL] autorelease];
        if (op) {
            
            // clear previous title and file proxy icon
            [[self window] setTitle:[NSString stringWithFormat:NSLocalizedString(@"Searching%C", @"info panel title"), TLM_ELLIPSIS]];
            [[self window] setRepresentedURL:nil];
            
            NSMutableSet *packages = [NSMutableSet set];
            // !!! what to do if the db hasn't been loaded yet for this mirror?
            [packages addObjectsFromArray:[[TLMDatabase databaseForMirrorURL:mirrorURL] packages]];
            [packages addObjectsFromArray:[[TLMDatabase localDatabase] packages]];
            
            for (TLMDatabasePackage *pkg in packages) {
                
                if ([[pkg name] isEqualToString:[package infoName]]) {
                    TLMLog(__func__, @"%@ found in database; bypassing tlmgr.", [pkg name]);
                    [self _updateWithPackage:pkg];
                    return;
                }
            }
        
            TLMLog(__func__, @"%@ not found in database; reverting to `tlmgr show`.", [package infoName]);

            [self setFileObjects:nil];
            [_fileView reloadIcons];
            
            [_runfiles removeAllObjects];
            [_sourcefiles removeAllObjects];
            [_docfiles removeAllObjects];
            [_outlineView reloadData];
            
            [_tabView selectLastTabViewItem:nil];
            [self _recenterSpinner];
            [_spinner startAnimation:nil];
            
            [[NSNotificationCenter defaultCenter] addObserver:self 
                                                     selector:@selector(_handleInfoOperationFinishedNotification:) 
                                                         name:TLMOperationFinishedNotification 
                                                       object:op];
            [_infoQueue addOperation:op];
            
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
        [_runfiles removeAllObjects];
        [_sourcefiles removeAllObjects];
        [_docfiles removeAllObjects];
        [_outlineView reloadData];
        [_tabView selectFirstTabViewItem:nil];
    }        
}

- (BOOL)textView:(NSTextView *)aTextView clickedOnLink:(id)aLink atIndex:(NSUInteger)charIndex
{
    if ([aLink isKindOfClass:[NSURL class]])
        return [[NSWorkspace sharedWorkspace] openURL:aLink];
    else if ([aLink isKindOfClass:[NSString class]] && (aLink = [NSURL URLWithString:aLink]) != nil)
        return [[NSWorkspace sharedWorkspace] openURL:aLink];
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
    return [(_TLMFileObject *)[_fileObjects objectAtIndex:anIndex] name];
}

#pragma mark FileView delegate

- (void)fileView:(FileView *)aFileView willPopUpMenu:(NSMenu *)aMenu onIconAtIndex:(NSUInteger)anIndex
{
    NSInteger idx = [aMenu indexOfItemWithTag:FVOpenMenuItemTag];
    if (-1 != idx)
        [aMenu insertOpenWithMenuForURL:[[_fileObjects objectAtIndex:anIndex] URL] atIndex:(idx + 1)];
}

#pragma mark Outline view

/*
 NB: there is a fair amount of stuff dependent on having 3 categories here, and also a bunch
 of checks for isKindOfClass:.  I'd generally eschew that, but in this case it's simpler than
 writing another treenode class, and this isn't intended to do anything fancy.  Performance
 is also fine, again since there are so few nodes to deal with.
 */

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)idx ofItem:(id)item;
{
    if (nil == item) {
         switch (idx) {
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
    return [item objectAtIndex:idx];
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
        return NSLocalizedString(@"RUN FILES", @"all caps tableview group title");
    if (item == _sourcefiles)
        return NSLocalizedString(@"SOURCE FILES", @"all caps tableview group title");
    if (item == _docfiles)
        return NSLocalizedString(@"DOC FILES", @"all caps tableview group title");
    return item;
}

- (void)pathCell:(NSPathCell *)pathCell willPopUpMenu:(NSMenu *)menu;
{
    [_clickedCell autorelease];
    _clickedCell = [pathCell retain];
}

- (void)_pathCellAction:(id)sender
{
    /*
     The sender is the outline view, and the URL is nil, so this doesn't work at all.  This is almost certainly
     because the clickedPathComponentCell isn't set on the cell returned from preparedCellAtColumn:row:, which
     is quite understandable.  There's no way to get at the menu or cell without stashing it in an ivar, though,
     which doesn't fit with the documented/intended design.
     
    NSLog(@"sender = %@", sender);
    id clickedCell = [_outlineView preparedCellAtColumn:0 row:[_outlineView clickedRow]];
    NSLog(@"%@", [[clickedCell clickedPathComponentCell] URL]); 
     */
    
    NSURL *clickedURL = [[_clickedCell clickedPathComponentCell] URL];
    if ([[NSWorkspace sharedWorkspace] openURL:clickedURL] == NO)
        NSBeep();
}

// optional methods
- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(id)item { return [item isKindOfClass:[NSURL class]] == NO; }

- (NSCell *)outlineView:(NSOutlineView *)outlineView dataCellForTableColumn:(NSTableColumn *)tableColumn item:(id)item;
{
    NSCell *dataCell = [tableColumn dataCell];
    if ([item isKindOfClass:[NSURL class]]) {
        dataCell = [[NSPathCell new] autorelease];
        /*
         NSPathStylePopUp is the only one that doesn't look like crap in a table, and the popup is
         probably the most useful variant for the UI.
         */
        [(NSPathCell *)dataCell setPathStyle:NSPathStylePopUp];
        [dataCell setEditable:NO];
        [dataCell setTarget:self];
        [dataCell setAction:@selector(_pathCellAction:)];
        [(NSPathCell *)dataCell setDelegate:self];
    }
    
    // small size fits better with the UI here; changing from system font looks funny, though
    [dataCell setControlSize:NSSmallControlSize];
    [dataCell setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];

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
