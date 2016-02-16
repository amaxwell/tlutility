//
//  TLMFaviconCache.m
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 07/27/11.
/*
 This software is Copyright (c) 2011-2016
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

#define FAVICON_TIMEOUT 10.0

@interface _TLMFaviconQueueItem : NSObject
{
    NSURL        *_iconURL;
    NSMutableSet *_delegates;
    NSMutableSet *_otherURLs;
}

@property (nonatomic, retain) NSURL *iconURL;
@property (nonatomic, retain) NSMutableSet *delegates;
@property (nonatomic, retain) NSMutableSet *otherURLs;
@end

@implementation _TLMFaviconQueueItem

@synthesize iconURL = _iconURL;
@synthesize delegates = _delegates;
@synthesize otherURLs = _otherURLs;

- (id)initWithURL:(NSURL *)aURL;
{
    self = [super init];
    if (self) {
        _iconURL = [aURL retain];
        _delegates = [NSMutableSet new];
        _otherURLs = [NSMutableSet new];
    }
    return self;
}

- (void)dealloc
{
    [_iconURL release];
    [_delegates release];
    [_otherURLs release];
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

- (NSImage *)_defaultFavicon
{    
    static bool didInit = false;
    static NSImage *icon = nil;
    if (false == didInit) {
        NSString *imgPath = [[NSBundle bundleForClass:[WebView class]] pathForResource:@"url_icon" ofType:@"tiff"];
        icon = [[NSImage alloc] initWithContentsOfFile:imgPath];
    }
    return icon;
}

- (id)init
{
    self = [super init];
    if (self) {
        _queue = [NSMutableArray new];
        _webview = [[WebView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        [_webview setFrameLoadDelegate:self];
        /*
         The first call to mainFrameIcon always results in the default icon,
         even if you've loaded a site that has a favicon (e.g., utah.edu).
         This was a nightmare to debug, since it only appeared if the first
         site loaded had a favicon.  Calling it once here takes care of the
         problem, and as a bonus it provides us with the default favicon.
         */
        _defaultFavicon = [[_webview mainFrameIcon] retain];
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
    [_defaultFavicon release];
    [super dealloc];
}

- (NSImage *)defaultFavicon
{
    return _defaultFavicon ? _defaultFavicon : [self _defaultFavicon];
}

- (_TLMFaviconQueueItem *)_currentItem
{
    return [_queue lastObject];
}    

- (void)_downloadItems
{
    if ([_queue count] && NO == _downloading) {
        _TLMFaviconQueueItem *item = [self _currentItem];
        NSURLRequest *request = [NSURLRequest requestWithURL:[item iconURL] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:FAVICON_TIMEOUT];
        [[_webview mainFrame] loadRequest:request];
        _downloading = YES;
        
        // retain cycle here; not a problem, since it expires quickly (and this is a singleton anyway)
        _cancelTimer = [NSTimer scheduledTimerWithTimeInterval:FAVICON_TIMEOUT target:self selector:@selector(_cancelFaviconLoad:) userInfo:nil repeats:NO];
    }
}

- (void)_cancelFaviconLoad:(NSTimer *)timer
{
    _TLMFaviconQueueItem *item = [self _currentItem];
    if (timer)
        TLMLog(__func__, @"Stopping favicon download from %@ due to timeout", [item iconURL]);
    // can run into partial URLs from editing, though the formatter should disallow that...
    if ([[item iconURL] host])
        [_iconsByURL setObject:[NSNull null] forKey:[[item iconURL] host]];
    [_webview stopLoading:nil];
    if ([_queue count])
        [_queue removeLastObject];
    _downloading = NO;
    [_cancelTimer invalidate];
    _cancelTimer = nil;
    
    [self _downloadItems];
}

- (void)webView:(WebView *)sender didReceiveServerRedirectForProvisionalLoadForFrame:(WebFrame *)frame
{
    [[[self _currentItem] otherURLs] addObject:[[[frame provisionalDataSource] request] URL]];
}

- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame;
{
    TLMLog(__func__, @"Failed to download favicon for %@", [[self _currentItem] iconURL]);
    [self _cancelFaviconLoad:nil];
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame;
{
    if ([frame isEqual:[sender mainFrame]]) {
        id icon = [sender mainFrameIcon];
        if (nil == icon)
            icon = [NSNull null];
        _TLMFaviconQueueItem *item = [self _currentItem];

        /*
         Hit an exception here once when item was nil; no idea why, but likely the delegate
         messages are sent when I don't expect them.  Or something.  Maybe when download is
         cancelled by the timer?
        */
        if (item ) {
            [_iconsByURL setObject:icon forKey:[[item iconURL] host]];
                    
            // take care of redirects
            for (NSURL *otherURL in [item otherURLs])
                [_iconsByURL setObject:icon forKey:[otherURL host]];
            
            if (icon != [NSNull null]) {
                for (id <TLMFaviconCacheDelegate> obj in [item delegates])
                    [obj iconCache:self downloadedIcon:icon forURL:[item iconURL]];
            }
        }
        else {
            TLMLog(__func__, @"No current item loading for main frame URL %@", [sender mainFrameURL]);
        }

        [_webview stopLoading:nil];
        if ([_queue count])
            [_queue removeLastObject];
        _downloading = NO;
        [_cancelTimer invalidate];
        _cancelTimer = nil;
        
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
    // return nil for non-http icons, for symmetry with downloadIcon:delegate:
    return [aURL host] && [[aURL scheme] hasPrefix:@"http"] ? [_iconsByURL objectForKey:[aURL host]] : [self defaultFavicon];
}

- (NSImage *)downloadIconForURL:(NSURL *)aURL delegate:(id)delegate;
{
    NSParameterAssert(aURL);
    NSParameterAssert(nil == delegate || [delegate conformsToProtocol:@protocol(TLMFaviconCacheDelegate)]);
    
    // !!! early return for non-http URLs
    if ([[aURL scheme] hasPrefix:@"http"] == NO) return [self defaultFavicon];
    
    // !!! early return in case of invalid URL
    if ([aURL host] == nil) return [self defaultFavicon];
    
    // !!! early return: don't let it redirect and give the wrong icon
    if ([aURL isMultiplexer]) return [self defaultFavicon];
    
    aURL = [aURL tlm_normalizedURL];
    
    id icon = [_iconsByURL objectForKey:[aURL host]];
    
    if (icon) {
        
        if ([NSNull null] == icon)
            icon = [self defaultFavicon];
    }
    else {
        _TLMFaviconQueueItem *item = [[_TLMFaviconQueueItem alloc] initWithURL:aURL];
        [item setIconURL:aURL];
        if (delegate) [[item delegates] addObject:delegate];
        const NSUInteger idx = [_queue indexOfObject:item];
        if (NSNotFound != idx) {
            if (delegate) [[[_queue objectAtIndex:idx] delegates] addObject:delegate];
        }
        else {
            [_queue insertObject:item atIndex:0];
            [self _downloadItems];
        }
        [item release];
        icon = [self defaultFavicon];
    }
    return icon;
}

@end
