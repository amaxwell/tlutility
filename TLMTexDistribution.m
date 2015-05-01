//
//  TLMTexDistribution.m
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 04/30/15.
/*
 This software is Copyright (c) 2015
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

#import "TLMTexDistribution.h"

@interface TLMTexLive : NSObject
{
    uint16_t  _year;
    NSString *_path;
    NSString *_installName; // e.g. 2014, 2014basic
}

@end

@implementation TLMTexLive

- (id)initWithPath:(NSString *)path
{
    self = [super init];
    if (self) {
        _path = [path copy];
        NSCharacterSet *numberSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789"];
        for (NSString *comp in [path pathComponents]) {
            NSString *yearString;
            NSScanner *scanner = [[NSScanner alloc] initWithString:comp];
            if ([scanner scanCharactersFromSet:numberSet intoString:&yearString] && [yearString length] == 4) {
                _year = (uint16_t)[yearString integerValue];
                _installName = [comp copy];
            }
            [scanner release];
        }
    }
    return self;
}

- (void)dealloc
{
    [_path release];
    [_installName release];
    [super dealloc];
}

@end

@implementation TLMTexDistribution

@synthesize name = _name;
@synthesize scripts = _scripts;
@synthesize installPath = _installPath;
@synthesize texdistPath = _texdistPath;
@synthesize texdistVersion = _texdistVersion;
@synthesize texdistDescription = _texdistDescription;

#define TEXDIST_LOCAL @"/Library/TeX/Distributions"

+ (NSArray *)knownDistributionsInLocalDomain
{
    NSMutableArray *distributions = [NSMutableArray array];
    for (NSString *tdPath in [[NSFileManager defaultManager] enumeratorAtPath:TEXDIST_LOCAL]) {
        tdPath = [TEXDIST_LOCAL stringByAppendingPathComponent:tdPath];
        if ([[tdPath pathExtension] caseInsensitiveCompare:@"texdist"] == NSOrderedSame) {
            TLMTexDistribution *dist = [[TLMTexDistribution alloc] initWithPath:tdPath architecture:nil];
            [distributions addObject:dist];
            [dist release];
        }
    }
    return distributions;
}

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

- (id)initWithPath:(NSString *)absolutePath architecture:(NSString *)arch
{
    self = [super init];
    if (self) {
        _texdistPath = [absolutePath copy];
        NSString *rootPath = [[_texdistPath stringByAppendingPathComponent:@"Contents"] stringByAppendingPathComponent:@"Root"];
        _name = [[[_texdistPath lastPathComponent] stringByDeletingPathExtension] copy];
        _installPath = [[rootPath stringByResolvingSymlinksInPath] copy];
    }
    return self;
}

-  (void)dealloc
{
    [_name release];
    [_scripts release];
    [_installPath release];
    [_texdistPath release];
    [_texdistVersion release];
    [_texdistDescription release];
    [super dealloc];
}

- (BOOL)isInstalled
{
    return [[NSFileManager defaultManager] fileExistsAtPath:[self installPath]];
}

- (NSString *)texbinPath
{
    return [NSString pathWithComponents:[NSArray arrayWithObjects:[self texdistPath], @"Contents", @"Programs", @"texbin", nil]];
}

- (NSString *)architecture
{
    return [[[self texbinPath] stringByResolvingSymlinksInPath] lastPathComponent];
}

- (BOOL)isDefault
{
    NSString *resolvedTexbin = [[self texbinPath] stringByResolvingSymlinksInPath];
    NSString *resolvedUsrTexbin = [@"/usr/texbin" stringByResolvingSymlinksInPath];
    FSRef fsA, fsB;
    if (CFURLGetFSRef((CFURLRef)[NSURL fileURLWithPath:resolvedTexbin], &fsA) &&
        CFURLGetFSRef((CFURLRef)[NSURL fileURLWithPath:resolvedUsrTexbin], &fsB))
        return (FSCompareFSRefs(&fsA, &fsB) == noErr);
    return NO;
}

- (NSArray *)installedArchitectures
{
    NSMutableArray *archs = nil;
    if ([self isInstalled]) {
        NSString *binPath = [[self installPath] stringByAppendingPathComponent:@"bin"];
        archs = [NSMutableArray array];
        for (NSString *arch in [[NSFileManager defaultManager] enumeratorAtPath:binPath]) {
            NSString *pdftex = [[binPath stringByAppendingPathComponent:arch] stringByAppendingPathComponent:@"pdftex"];
            if ([[NSFileManager defaultManager] isExecutableFileAtPath:pdftex]) {
                [archs addObject:arch];
            }
        }
    }
    return archs;
}

@end

