//
//  TLMFaviconCache.m
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 07/27/11.
/*
 This software is Copyright (c) 2011
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

#import "TLMFaviconCache.h"
#import "TLMLogServer.h"

#import <WebKit/WebKit.h>
#import <pthread.h>

@interface _TLMFaviconQueueItem : NSObject
{
    NSURL        *_iconURL;
    NSMutableSet *_delegates;
}

@property (nonatomic, retain) NSURL *iconURL;
@property (nonatomic, retain) NSMutableSet *delegates;
@end

@implementation _TLMFaviconQueueItem

@synthesize iconURL = _iconURL;
@synthesize delegates = _delegates;

- (id)initWithURL:(NSURL *)aURL;
{
    self = [super init];
    if (self) {
        _iconURL = [aURL retain];
        _delegates = [NSMutableSet new];
    }
    return self;
}

- (void)dealloc
{
    [_iconURL release];
    [_delegates release];
    [super dealloc];
}

- (BOOL)isEqual:(id)object
{
    return [self isKindOfClass:[object class]] && [[self iconURL] isEqual:[object iconURL]];
}

@end


@implementation TLMFaviconCache

// Do not use directly!  File scope only because pthread_once doesn't take an argument.
static id _sharedCache = nil;
static void __TLMFaviconCacheInit() { _sharedCache = [TLMFaviconCache new]; }

+ (id)sharedCache
{
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    (void) pthread_once(&once, __TLMFaviconCacheInit);
    return _sharedCache;
}

- (id)init
{
    self = [super init];
    if (self) {
        _queue = [NSMutableArray new];
        _webview = [[WebView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        [_webview setFrameLoadDelegate:self];
        _iconsByURL = [NSMutableDictionary new];
    }
    return self;
}

- (void)dealloc
{
    [_webview stopLoading:nil];
    [_webview setFrameLoadDelegate:nil];
    [_webview release];
    [_queue release];
    [_iconsByURL release];
    [super dealloc];
}

- (_TLMFaviconQueueItem *)_currentItem
{
    return [_queue lastObject];
}    

- (void)_downloadItems
{
    if ([_queue count] && NO == _downloading) {
        _TLMFaviconQueueItem *item = [self _currentItem];
        [[_webview mainFrame] loadRequest:[NSURLRequest requestWithURL:[item iconURL]]];
        TLMLog(__func__, @"Loading favicon for %@", [item iconURL]);
        _downloading = YES;
    }
}

- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame;
{
    _TLMFaviconQueueItem *item = [self _currentItem];
    TLMLog(__func__, @"Failed to download icon for %@", [item iconURL]);
    [_iconsByURL setObject:[NSNull null] forKey:[[item iconURL] host]];
    [_webview stopLoading:nil];
    [_queue removeLastObject];
    _downloading = NO;
    [self _downloadItems];
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame;
{
    if ([frame isEqual:[sender mainFrame]]) {
        id icon = [sender mainFrameIcon];
        if (nil == icon)
            icon = [NSNull null];
        _TLMFaviconQueueItem *item = [self _currentItem];
        [_iconsByURL setObject:icon forKey:[[item iconURL] host]];
        
        if (icon != [NSNull null]) {
            for (id <TLMFaviconCacheDelegate> obj in [item delegates])
                [obj iconCache:self downloadedIcon:icon forURL:[item iconURL]];
        }
        [_webview stopLoading:nil];
        [_queue removeLastObject];
        _downloading = NO;
        [self _downloadItems];
    }
}

# pragma mark API

/*
 Cache by host, since I ended up with a dictionary containing these entries:
 http://mirrors.med.harvard.edu/ctan/systems/texlive/tlnet != http://mirrors.med.harvard.edu/ctan/systems/texlive/tlnet/
 and calling tlm_normalizedURL doesn't get rid of the trailing slash (in fact,
 +[NSURL URLWithString:] addes it back on even if I delete it).
 Once again, NSURL sucks as a dictionary key.
 */

- (NSImage *)iconForURL:(NSURL *)aURL;
{
    NSParameterAssert(aURL);
    return [_iconsByURL objectForKey:[aURL host]];
}

- (void)downloadIconForURL:(NSURL *)aURL delegate:(id)object;
{
    NSParameterAssert(aURL);
    NSParameterAssert([object conformsToProtocol:@protocol(TLMFaviconCacheDelegate)]);
    
    // !!! early return for non-http URLs
    if ([[aURL scheme] hasPrefix:@"http"] == NO)
        return;
    
    aURL = [aURL tlm_normalizedURL];
    
    if ([_iconsByURL objectForKey:[aURL host]]) {
        id icon = [_iconsByURL objectForKey:[aURL host]];
        if (icon != [NSNull null])
            [object iconCache:self downloadedIcon:icon forURL:aURL];
    }
    else {
        _TLMFaviconQueueItem *item = [[_TLMFaviconQueueItem alloc] initWithURL:aURL];
        [item setIconURL:aURL];
        [[item delegates] addObject:object];
        const NSUInteger idx = [_queue indexOfObject:item];
        if (NSNotFound != idx) {
            [[[_queue objectAtIndex:idx] delegates] addObject:object];
        }
        else {
            [_queue insertObject:item atIndex:0];
            [self _downloadItems];
        }
        [item release];
    }

}

@end
