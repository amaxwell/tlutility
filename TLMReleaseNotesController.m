//
//  TLMReleaseNotesController.m
//  TeX Live Utility
//
//  Created by Adam Maxwell on 1/12/09.
/*
 This software is Copyright (c) 2009-2016
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

#import "TLMReleaseNotesController.h"

#define RELNOTES_URL @"https://raw.githubusercontent.com/amaxwell/tlutility/master/appcast/tlu_appcast.xml"

@implementation TLMReleaseNotesController

@synthesize _versionsTable;
@synthesize _notesView;
@synthesize _progressIndicator;
@synthesize _statusField;

@synthesize notes = _notes;
@synthesize versions = _versions;

+ (TLMReleaseNotesController *)sharedInstance
{
    static id sharedInstance = nil;
    if (nil == sharedInstance)
        sharedInstance = [self new];
    return sharedInstance;
}

- (id)init
{
    self = [self initWithWindowNibName:[self windowNibName]];
    if (self) {
        _downloadPath = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"tlu_appcast.xml"] copy];
    }
    return self;
}

- (void)dealloc
{
    [_versions release];
    [_notes release];
    [_versionsTable release];
    [_notesView release];
    [_progressIndicator release];
    [_downloadPath release];
    [_statusField release];
    [super dealloc];
}

- (NSString *)windowNibName { return @"ReleaseNotes"; }

- (void)_startDownload
{
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:RELNOTES_URL]];
    NSURLDownload *download = [[NSURLDownload alloc] initWithRequest:request delegate:self];
    [download setDestination:_downloadPath allowOverwrite:YES];
    [download autorelease];
    [_progressIndicator startAnimation:nil];
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    [[self window] setTitle:NSLocalizedString(@"Release Notes", @"Window title")];
    if ([_versions count] == 0) {
        [_statusField setStringValue:NSLocalizedString(@"Downloading release notes", @"")];
        [self _startDownload];   
    }
}


- (void)downloadDidFinish:(NSURLDownload *)download;
{
    [_statusField setStringValue:NSLocalizedString(@"Download complete", @"")];
    [_progressIndicator stopAnimation:nil];
    
    NSURL *fileURL = [NSURL fileURLWithPath:_downloadPath];
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithContentsOfURL:fileURL options:0 error:NULL];
    [doc autorelease];
    
    NSMutableArray *notes = [NSMutableArray array];
    for (NSXMLNode *item in [doc nodesForXPath:@"//item" error:NULL]) {
        
        NSMutableDictionary *note = [NSMutableDictionary dictionary];
        for (NSXMLNode *child in [item children]) {
            
            NSString *name = [child name];
            if ([name isEqualToString:@"title"]) {
                [note setObject:[child stringValue] forKey:@"title"];
            }
            else if ([name isEqualToString:@"pubDate"]) {
                [note setObject:[child stringValue] forKey:@"pubDate"];
            }
            else if ([name isEqualToString:@"description"]) {
                NSMutableString *htmlString = [NSMutableString string];
                // use appendFormat: in case of nil string and to add newlines for logging
                for (NSXMLNode *htmlNode in [child children])
                    [htmlString appendFormat:@"%@\n", [htmlNode XMLStringWithOptions:NSXMLNodePrettyPrint]];
                [note setObject:htmlString forKey:@"description"];
            }
            else if ([name isEqualToString:@"enclosure"]) {
                NSXMLElement *el = (NSXMLElement *)child;
                NSString *version = [[el attributeForName:@"sparkle:version"] stringValue];
                if (version) {
                    [note setObject:[NSNumber numberWithFloat:[version floatValue]] forKey:@"version"];
                }
            }
        }
        [notes addObject:note];
    }
    
    // sort in descending order
    NSSortDescriptor *sort = [[[NSSortDescriptor alloc] initWithKey:@"self" ascending:NO] autorelease];
    [self setVersions:[[notes valueForKeyPath:@"version"] sortedArrayUsingDescriptors:[NSArray arrayWithObject:sort]]];
    
    NSMutableDictionary *noteStrings = [NSMutableDictionary dictionary];
    for (NSDictionary *note in notes) {
        if ([note objectForKey:@"description"] && [note objectForKey:@"version"])
            [noteStrings setObject:[note objectForKey:@"description"] forKey:[note objectForKey:@"version"]];
    }
    [self setNotes:noteStrings];
    [_versionsTable reloadData];
    
    // clean up the downloaded file
    [[NSFileManager defaultManager] removeItemAtPath:_downloadPath error:NULL];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
    [self tableViewSelectionDidChange:nil];
#pragma clang diagnostic pop
}

- (void)download:(NSURLDownload *)download didFailWithError:(NSError *)error;
{
    [_progressIndicator stopAnimation:nil];
    [_statusField setStringValue:[error localizedDescription]];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView;
{
    return [_versions count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row;
{
    return [NSString stringWithFormat:NSLocalizedString(@"Version %@", @""), [_versions objectAtIndex:row]];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    [_notesView setSelectedDOMRange:nil affinity:NSSelectionAffinityUpstream];
    NSString *htmlString = nil;
    
    if ([_versionsTable numberOfSelectedRows]) {
        NSNumber *row = [_versions objectAtIndex:[_versionsTable selectedRow]];
        if ([_notes objectForKey:row])
            htmlString = [_notes objectForKey:row];
        else
            htmlString = [NSString stringWithFormat:@"<h3>%@</h3>", NSLocalizedString(@"Error: no release notes for selected version.", @"")];
    }
    else {
        htmlString = [NSString stringWithFormat:@"<h3>%@</h3>", NSLocalizedString(@"Nothing selected.", @"")];
    }
    
    NSParameterAssert(htmlString);
    [[_notesView mainFrame] loadHTMLString:htmlString baseURL:nil];
}

@end
