//
//  TLMDatabase.m
//  TeX Live Manager
//
//  Created by Adam R. Maxwell on 09/13/10.
/*
 This software is Copyright (c) 2008-2010
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

#import "TLMDatabase.h"
#import <regex.h>
#import "TLMLogServer.h"
#import "TLMPreferenceController.h"

@interface _TLMDatabase : NSObject {
    NSURL           *_tlpdbURL;
    NSMutableData   *_tlpdbData;
    NSURLConnection *_connection;
    BOOL             _failed;
}

- (id)initWithURL:(NSURL *)tlpdbURL;
- (NSUInteger)versionNumber;

@end

@implementation TLMDatabase

+ (NSUInteger)yearForMirrorURL:(NSURL *)aURL;
{
    if (nil == aURL)
        aURL = [[TLMPreferenceController sharedPreferenceController] defaultServerURL];
    NSURL *tlpdbURL = [NSURL URLWithString:[[aURL absoluteString] stringByAppendingPathComponent:@"tlpkg/texlive.tlpdb"]];
    _TLMDatabase *db = [[_TLMDatabase alloc] initWithURL:tlpdbURL];
    NSUInteger version = [db versionNumber];
    [db release];
    return version;
}

@end

@implementation _TLMDatabase

#define MIN_DATA_LENGTH 2048

- (id)initWithURL:(NSURL *)tlpdbURL;
{
    NSParameterAssert(tlpdbURL);
    self = [super init];
    if (self) {
        _tlpdbURL = [tlpdbURL copy];
        _tlpdbData = [NSMutableData new];
    }
    return self;
}

- (void)dealloc
{
    [_connection release];
    [_tlpdbURL release];
    [_tlpdbData release];
    [super dealloc];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    _failed = YES;
    TLMLog(__func__, @"Failed to download tlpdb: %@", error);
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data;
{
    [_tlpdbData appendData:data];
    TLMLog(__func__, @"%d bytes", [_tlpdbData length]);
    if ([_tlpdbData length] >= MIN_DATA_LENGTH)
        [connection cancel];
}

- (void)_downloadDatabaseHead
{
    if ([_tlpdbData length] == 0) {
        NSParameterAssert(nil == _connection);
        NSURLRequest *request = [NSURLRequest requestWithURL:_tlpdbURL];
        _failed = NO;
        TLMLog(__func__, @"Downloading tlpdb%C", 0x2026);
        _connection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
        do {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.5, TRUE);
        } while ([_tlpdbData length] < MIN_DATA_LENGTH && NO == _failed);
        TLMLog(__func__, @"Downloaded %lu bytes", (unsigned long)[_tlpdbData length]);
    }
}

- (NSUInteger)versionNumber;
{
    [self _downloadDatabaseHead];
    NSUInteger version = NSNotFound;
    if ([_tlpdbData length] >= MIN_DATA_LENGTH) {
        /*
         name 00texlive.config
         category TLCore
         revision 15388
         shortdesc TeX Live network archive option settings
         longdesc This package contains configuration options for the TeX Live
         longdesc archive If container_split_{doc,src}_files occurs in the depend
         longdesc lines the {doc,src} files are split into separate containers
         longdesc (.tar.xz)  during container build time. Note that this has NO
         longdesc effect on the appearance within the texlive.tlpdb. It is only
         longdesc on container level. The container_format/XXXXX specifies the
         longdesc format, currently allowed is only "xz", which generates .tar.xz
         longdesc files. zip can be supported. release/NNNN specifies the release
         longdesc number as used in the installer.  These values are taken from
         longdesc TeXLive::TLConfig::TLPDBConfigs hash at tlpdb creation time.
         longdesc For information on the 00texlive prefix see
         longdesc 00texlive.installation(.tlpsrc)
         depend container_format/xz
         depend container_split_doc_files/1
         depend container_split_src_files/1
         depend release/2010
         depend revision/19668
         */
        [_tlpdbData appendBytes:"\0" length:1];
        const char *tlpdb_str = [_tlpdbData bytes];
        regex_t regex;
        regmatch_t match[3];
        int err = regcomp(&regex, "^depend release\\/([0-9]{4})$", REG_NEWLINE|REG_EXTENDED);
        if (err) {
            char err_msg[1024] = {'\0'};
            regerror(err, &regex, err_msg, sizeof(err_msg));
            TLMLog(__func__, @"Unable to compile regex: %s", err_msg);
        }
        else if (0 == (err = regexec(&regex, tlpdb_str, 2, match, 0))) {
            size_t matchLength = match[1].rm_eo - match[1].rm_so;
            char *year = NSZoneMalloc(NSDefaultMallocZone(), matchLength + 1);
            memset(year, 0, matchLength + 1);
            memcpy(year, &tlpdb_str[match[1].rm_so], matchLength);
            version = strtoul(year, NULL, 0);
            NSZoneFree(NSDefaultMallocZone(), year);
        }
        else {
            char err_msg[1024] = {'\0'};
            regerror(err, &regex, err_msg, sizeof(err_msg));
            TLMLog(__func__, @"Unable to find year in tlpdb: %s", err_msg);
        }
        regfree(&regex);

    }
    return version;
}

@end
