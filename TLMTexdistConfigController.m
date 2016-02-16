//
//  TLMTexdistConfigController.m
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 09/08/14.
/*
 This software is Copyright (c) 2014-2016
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

#import "TLMLogServer.h"
#import "TLMTexDistribution.h"
#import "TLMTexdistConfigController.h"
#import "TLMReadWriteOperationQueue.h"
#import "TLMAuthorizedOperation.h"

@interface TLMTexdistConfigController ()

@end

@implementation TLMTexdistConfigController

@synthesize _okButton;
@synthesize _tableView;

- (id)init { return [self initWithWindowNibName:[self windowNibName]]; }

- (void)dealloc
{
    [_distributions release];
    [_okButton release];
    [_tableView release];
    [super dealloc];
}

- (NSString *)windowNibName { return @"TexdistConfigController"; }

- (void)chooseDistribution:(id)sender
{
    TLMLog(__func__, @"choose distribution %@ %@", [[sender representedObject] name], [[sender representedObject] installPath]);
}

- (void)_reloadDistributions
{
    NSMutableArray *distributions = [NSMutableArray array];
    NSArray *availableDistributions = [TLMTexDistribution knownDistributionsInLocalDomain];
    for (TLMTexDistribution *dist in availableDistributions) {
        if ([dist isInstalled])
            [distributions addObject:dist];
    }
    [_distributions release];
    _distributions = [distributions copy];
    [_tableView reloadData];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    [_tableView removeTableColumn:[_tableView tableColumnWithIdentifier:@"arch"]];
    [self _reloadDistributions];
}

- (void)dismissSheet
{
    [_tableView setDelegate:nil];
    [_tableView setDataSource:nil];
    [NSApp endSheet:[self window] returnCode:0];
}

- (void)repair:(id)sender
{
    [self dismissSheet];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView;
{
    return [_distributions count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row;
{
    NSString *ident = [tableColumn identifier];
    TLMTexDistribution *dist = [_distributions objectAtIndex:row];
    if ([ident isEqualToString:@"name"])
        return [dist name];
    else if ([ident isEqualToString:@"arch"])
        return [dist architecture];
    else if ([ident isEqualToString:@"state"])
        return [NSNumber numberWithInteger:([dist isDefault] ? NSOnState : NSOffState)];
    return nil;
}

- (void)_handleChangeFinishedNotification:(NSNotification *)aNote
{
    TLMAuthorizedOperation *op = [aNote object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TLMOperationFinishedNotification object:op];
    [_okButton setEnabled:YES];
    [self _reloadDistributions];
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row;
{
    if (row >= 0) {
        TLMTexDistribution *dist = [_distributions objectAtIndex:row];
        /*
         From Dick Koch on 17 Mar 2015:
         One final thing. When actually selecting a distribution, it should only be
         necessary to define one symbolic link. Such a link is shown below
         when TeXLive-2013 is chosen.
         
         /Library/Distributions/.DefaultTeX/Contents —> ../TeXLive-2013.texdist/Contents
         
         
         Let me talk about the contents of ../TeXLive-2013.texdist/Contents/Programs.
         This location contains five symbolic links:
         
         i386
         powerpc
         ppc
         x86_64
         texbin
         
         The first four point to paths to the corresponding binaries for that distribution.
         The final texbin is a link to one of the first four, choosing the actual distribution.
         
         I’d advise ignoring this, because the texbin link was set up at install time
         to point to an appropriate binary. But you can dip into this if you want the
         user to reselect the binaries (mainly to select x86 over universal-darwin).
         However, it is an added complication, and for what?
         */
        TLMLog(__func__, @"set %@ : %@", [[dist texdistPath] lastPathComponent], [dist architecture]);
        NSString *changeScript = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"texdist_change_default.sh"];
        NSArray *args = [NSArray arrayWithObject:[[dist texdistPath] lastPathComponent]];
        TLMAuthorizedOperation *op = [[TLMAuthorizedOperation alloc] initWithAuthorizedCommand:changeScript options:args];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_handleChangeFinishedNotification:) name:TLMOperationFinishedNotification object:op];
        [[TLMReadWriteOperationQueue defaultQueue] addOperation:op];
        [op release];
        [_okButton setEnabled:NO];
    }
}


@end
