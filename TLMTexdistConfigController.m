//
//  TLMTexdistConfigController.m
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 09/08/14.
/*
 This software is Copyright (c) 2014
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

#import "TLMTexdistConfigController.h"

@interface TLMTexDistribution : NSObject
{
    NSString           *_name;
    NSArray            *_scripts;
    NSString           *_installPath;
    NSString           *_texdistVersion;
    NSAttributedString *_texdistDescription;
}

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSArray *scripts;
@property (nonatomic, readonly) NSString *installPath;
@property (nonatomic, readonly) NSString *texdistVersion;
@property (nonatomic, readonly) NSAttributedString *texdistDescription;

@end

@implementation TLMTexDistribution

@synthesize name = _name;
@synthesize scripts = _scripts;
@synthesize installPath = _installPath;
@synthesize texdistVersion = _texdistVersion;
@synthesize texdistDescription = _texdistDescription;

- (id)initWithPropertyList:(NSDictionary *)plist
{
    self = [super init];
    if (self) {
        _name = [[plist objectForKey:@"name"] copy];
        _scripts = [[plist objectForKey:@"scripts"] copy];
        _installPath = [[plist objectForKey:@"path"] copy];
        NSDictionary *auxiliary = [plist objectForKey:@"auxiliary"];
        _texdistVersion = [[auxiliary objectForKey:@"TeXDistVersion"] copy];
        NSData *htmlData = [[auxiliary objectForKey:@"Description"] dataUsingEncoding:NSUTF8StringEncoding];
        _texdistDescription = [[NSAttributedString alloc] initWithHTML:htmlData baseURL:nil documentAttributes:NULL];
    }
    return self;
}

-  (void)dealloc
{
    [_name release];
    [_scripts release];
    [_installPath release];
    [_texdistVersion release];
    [_texdistDescription release];
    [super dealloc];
}

- (BOOL)isInstalled
{
    return [[NSFileManager defaultManager] fileExistsAtPath:[self installPath]];
}

@end

@interface TLMTexdistConfigController ()

@end

@implementation TLMTexdistConfigController

@synthesize _distributionPopup;
@synthesize _okButton;
@synthesize _cancelButton;

- (id)initWithWindowNibName:(NSString *)windowNibName
{
    self = [super initWithWindowNibName:windowNibName];
    if (self) {
        NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"texdist" ofType:@"plist"]];
        NSMutableArray *distributions = [NSMutableArray array];
        for (NSString *key in plist) {
            TLMTexDistribution *dist = [[TLMTexDistribution alloc] initWithPropertyList:[plist objectForKey:key]];
            if ([dist isInstalled])
                [distributions addObject:dist];
            [dist release];
        }
        _distributions = [distributions copy];
    }
    return self;
}

- (void)dealloc
{
    [_distributions release];
    [_distributionPopup release];
    [_okButton release];
    [_cancelButton release];
    [super dealloc];
}

- (NSString *)windowNibName { return @"TLMTexdistConfigController"; }

- (void)windowDidLoad {
    [super windowDidLoad];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
}

@end
