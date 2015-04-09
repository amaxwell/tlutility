//
//  TLMDatabasePackage.m
//  tlpdb_test
//
//  Created by Adam R. Maxwell on 06/08/11.
/*
 This software is Copyright (c) 2011-2015
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

#import "TLMDatabasePackage.h"
#import "TLMLogServer.h"
#import "TLMEnvironment.h"

@implementation TLMDatabasePackage

#define TLM_METHOD(_rettype_, _mname_) \
- (_rettype_)_mname_ { \
    return [_dictionary objectForKey:@#_mname_]; \
}

- (TLMDatabasePackage *)initWithDictionary:(NSDictionary *)dict;
{
    self = [super init];
    if (self) {
        _dictionary = [dict mutableCopy];
    }
    return self;
}

- (void)dealloc
{
    [_dictionary release];
    [super dealloc];
}

- (NSUInteger)hash { return [[self name] hash]; }

- (BOOL)isEqual:(id)object
{
    if ([object isKindOfClass:[self class]] == NO) return NO;
    return [[self name] isEqualToString:[object name]];
}

- (NSAttributedString *)attributedString;
{
    NSString *desc = [_dictionary objectForKey:@"longDescription"] ? [_dictionary objectForKey:@"longDescription"] : [self shortDescription];
    if (nil == desc)
        desc = [self name];
    return [[[NSAttributedString alloc] initWithString:desc attributes:nil] autorelease];
}

- (NSArray *)_absoluteURLsFromDatabaseFiles:(NSArray *)dbfiles
{
    NSString *installPath = [[TLMEnvironment currentEnvironment] installDirectory];
    NSFileManager *fm = [NSFileManager new];
    
    NSMutableArray *files = [dbfiles mutableCopy];
    
    // iterate backwards to modify the array in-place
    NSUInteger fidx = [files count];
    while (fidx--) {
        NSString *path = [files objectAtIndex:fidx];
        
        // have to munge paths with RELOC from the remote tlpdb
        if ([path hasPrefix:@"RELOC"])
            path = [path stringByReplacingCharactersInRange:NSMakeRange(0, 5) withString:@"texmf-dist"];
        path = [installPath stringByAppendingPathComponent:path];
        
        if ([fm fileExistsAtPath:path]) {
            NSURL *furl = [[NSURL alloc] initFileURLWithPath:path];
            if (furl) {
                [files replaceObjectAtIndex:fidx withObject:furl];
                [furl release];
            }
            else {
                // invalid URL
                [files removeObjectAtIndex:fidx];
            }
        }
        else {
            // nonexistent file
            [files removeObjectAtIndex:fidx];
        }                    
    }
    [fm release];
    return [files autorelease];
}

TLM_METHOD(NSString*, name)
TLM_METHOD(NSString*, category)
TLM_METHOD(NSString*, shortDescription)
TLM_METHOD(NSString*, longDescription)
TLM_METHOD(NSString*, catalogue)
TLM_METHOD(NSNumber*, relocated)
TLM_METHOD(NSNumber*, revision)
TLM_METHOD(NSArray*, depends);

/*
 <key>catalogueData</key>
 <dict>
 <key>ctan</key>
 <string>/fonts/Asana-Math</string>
 <key>date</key>
 <string>2012-06-11 11:02:36 +0200</string>
 <key>license</key>
 <string>ofl</string>
 <key>version</key>
 <string>000.949</string>
 </dict>
 */

- (NSString *)catalogueVersion;
{
    return [[_dictionary objectForKey:@"catalogueData"] objectForKey:@"version"];
}

// override to return arrays of URL objects (only for files that exist on-disk)
- (NSArray *)runFiles
{
    return [self _absoluteURLsFromDatabaseFiles:[_dictionary objectForKey:@"runFiles"]];
}

- (NSArray *)sourceFiles
{
    return [self _absoluteURLsFromDatabaseFiles:[_dictionary objectForKey:@"sourceFiles"]];    
}

- (NSArray *)docFiles
{
    return [self _absoluteURLsFromDatabaseFiles:[_dictionary objectForKey:@"docFiles"]];    
}

@end
