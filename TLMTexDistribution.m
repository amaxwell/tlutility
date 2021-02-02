//
//  TLMTexDistribution.m
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 04/30/15.
/*
 This software is Copyright (c) 2015-2016
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
@synthesize installPath = _installPath;
@synthesize texdistPath = _texdistPath;

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

- (id)initWithPath:(NSString *)absolutePath architecture:(NSString *)arch
{
    self = [super init];
    if (self) {
        _texdistPath = [absolutePath copy];
        NSString *rootPath = [[_texdistPath stringByAppendingPathComponent:@"Contents"] stringByAppendingPathComponent:@"Root"];
        _name = [[[_texdistPath lastPathComponent] stringByDeletingPathExtension] copy];
        // for macports, this points to /opt/local/share, which always exists
        _installPath = [[rootPath stringByResolvingSymlinksInPath] copy];
    }
    return self;
}

-  (void)dealloc
{
    [_name release];
    [_installPath release];
    [_texdistPath release];
    [super dealloc];
}

- (NSArray *)texbinPaths
{
    /*
     Looks like the texbin symlink doesn't exist in early texdist bundles, so that's not
     always the right one. Damn it.
     
     $ ll ../.FactoryDefaults/TeXLive-2014/Contents/Programs/
     total 40
     lrwxr-xr-x  1 root  wheel  64 Oct 17  2014 i386 -> ../../../../../../../usr/local/texlive/2014/bin/universal-darwin
     lrwxr-xr-x  1 root  wheel  64 Oct 17  2014 powerpc -> ../../../../../../../usr/local/texlive/2014/bin/universal-darwin
     lrwxr-xr-x  1 root  wheel  64 Oct 17  2014 ppc -> ../../../../../../../usr/local/texlive/2014/bin/universal-darwin
     lrwxr-xr-x  1 root  wheel   6 Oct 17  2014 texbin -> x86_64
     lrwxr-xr-x  1 root  wheel  61 Oct 17  2014 x86_64 -> ../../../../../../../usr/local/texlive/2014/bin/x86_64-darwin
     
     $ ll ../.FactoryDefaults/TeXLive-2009/Contents/Programs/
     total 24
     lrwxr-xr-x@ 1 root  wheel  64 Jul 15 21:03 i386 -> ../../../../../../../usr/local/texlive/2009/bin/universal-darwin
     lrwxr-xr-x@ 1 root  wheel  64 Jul 15 21:03 powerpc -> ../../../../../../../usr/local/texlive/2009/bin/universal-darwin
     lrwxr-xr-x@ 1 root  wheel  64 Jul 15 21:03 ppc -> ../../../../../../../usr/local/texlive/2009/bin/universal-darwin
     */
    NSString *texbinDirectory = [NSString pathWithComponents:[NSArray arrayWithObjects:[self texdistPath], @"Contents", @"Programs", nil]];
    NSMutableArray *paths = [NSMutableArray arrayWithCapacity:5];
    for(NSString *last in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:texbinDirectory error:NULL]) {
        [paths addObject:[texbinDirectory stringByAppendingPathComponent:last]];
    }
    return paths;
}

- (NSString *)architecture
{
    // !!! currently unused, but if texbin, need to resolve; if not, it's the architecture directly?
    return [[[[self texbinPaths] lastObject] stringByResolvingSymlinksInPath] lastPathComponent];
}

- (BOOL)isInstalled
{
    // originally checked for _installPath existence, but it always exists for macports
    for (NSString *path in [self texbinPaths]) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path])
            return YES;
    }
    return NO;
}

/*
 
 Need to try this for each path in -texbinPaths, I guess?
 
 */

- (BOOL)_isMactexPath:(NSString *)absolutePath
{
    NSString *resolvedTexbin = [absolutePath stringByResolvingSymlinksInPath];
    
    // check against old and new (TL 2015 and later) locations
    NSString *resolvedUsrTexbin = [@"/usr/texbin" stringByResolvingSymlinksInPath];
    NSString *resolvedLibTexbin = [@"/Library/TeX/texbin" stringByResolvingSymlinksInPath];
    
    NSURL *resolvedTexbinURL = [NSURL fileURLWithPath:resolvedTexbin];

    if ([resolvedTexbinURL tlm_isEqualToFileURL:[NSURL fileURLWithPath:resolvedUsrTexbin]])
        return YES;
    else if ([resolvedTexbinURL tlm_isEqualToFileURL:[NSURL fileURLWithPath:resolvedLibTexbin]])
        return YES;
    
    return NO;
}

- (BOOL)isDefault
{
    for (NSString *path in [self texbinPaths]) {
        if ([self _isMactexPath:path])
            return YES;
    }
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

