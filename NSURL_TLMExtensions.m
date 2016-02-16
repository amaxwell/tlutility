//
//  NSURL_TLMExtensions.m
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 07/15/11.
/*
 This software is Copyright (c) 2010-2016
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

#import "NSURL_TLMExtensions.h"
#import "TLMLogServer.h"

#define TLPDB_PATH  @"tlpkg/texlive.tlpdb"
#define MULTIPLEXER @"mirror.ctan.org"
#define TLNET_PATH  @"systems/texlive/tlnet"

@implementation NSURL (TLMExtensions)

+ (NSURL *)databaseURLForTLNetURL:(NSURL *)mirrorURL;
{
    return [[mirrorURL tlm_URLByAppendingPathComponent:TLPDB_PATH] tlm_normalizedURL];
}

+ (NSURL *)TLNetURLForMirror:(NSURL *)mirrorURL;
{
    return [[mirrorURL tlm_URLByAppendingPathComponent:TLNET_PATH] tlm_normalizedURL];
}

+ (BOOL)writeURLs:(NSArray *)array toPasteboard:(NSPasteboard *)pboard;
{
    OSStatus err;
    
    PasteboardRef carbonPboard;
    err = PasteboardCreate((CFStringRef)[pboard name], &carbonPboard);
    
    if (noErr == err)
        err = PasteboardClear(carbonPboard);
    
    if (noErr == err)
        (void)PasteboardSynchronize(carbonPboard);
    
    if (noErr != err) {
        TLMLog(__func__, @"failed to setup pboard %@: %s", [pboard name], GetMacOSStatusErrorString(err));
        return NO;
    }
    
    for (NSURL *aURL in array) {
        
        CFDataRef utf8Data = (CFDataRef)[[aURL absoluteString] dataUsingEncoding:NSUTF8StringEncoding];
        
        // any pointer type; private to the creating application
        PasteboardItemID itemID = (void *)aURL;
        
        // Finder adds a file URL and destination URL for weblocs, but only a file URL for regular files
        // could also put a string representation of the URL, but Finder doesn't do that
        
        if ([aURL isFileURL]) {
            err = PasteboardPutItemFlavor(carbonPboard, itemID, kUTTypeFileURL, utf8Data, kPasteboardFlavorNoFlags);
        }
        else {
            err = PasteboardPutItemFlavor(carbonPboard, itemID, kUTTypeURL, utf8Data, kPasteboardFlavorNoFlags);
        }
        
        if (noErr != err)
            TLMLog(__func__, @"failed to write to pboard %@: %s", [pboard name], GetMacOSStatusErrorString(err));
    }
    
    ItemCount itemCount;
    err = PasteboardGetItemCount(carbonPboard, &itemCount);
    
    if (carbonPboard) 
        CFRelease(carbonPboard);
    
    return noErr == err && itemCount > 0;
}

+ (NSArray *)URLsFromPasteboard:(NSPasteboard *)pboard;
{
    OSStatus err;
    
    PasteboardRef carbonPboard;
    err = PasteboardCreate((CFStringRef)[pboard name], &carbonPboard);
    
    if (noErr == err)
        (void)PasteboardSynchronize(carbonPboard);
    
    ItemCount itemCount, itemIndex;
    if (noErr == err)
        err = PasteboardGetItemCount(carbonPboard, &itemCount);
    
    if (noErr != err)
        itemCount = 0;
    
    NSMutableArray *toReturn = [NSMutableArray arrayWithCapacity:itemCount];
    
    // this is to avoid duplication in the last call to NSPasteboard
    NSMutableSet *allURLsReadFromPasteboard = [NSMutableSet setWithCapacity:itemCount];
    
    // Pasteboard has 1-based indexing!
    
    for (itemIndex = 1; itemIndex <= itemCount; itemIndex++) {
        
        PasteboardItemID itemID;
        CFArrayRef flavors = NULL;
        CFIndex flavorIndex, flavorCount = 0;
        
        err = PasteboardGetItemIdentifier(carbonPboard, itemIndex, &itemID);
        if (noErr == err)
            err = PasteboardCopyItemFlavors(carbonPboard, itemID, &flavors);
        
        if (noErr == err)
            flavorCount = CFArrayGetCount(flavors);
        
        // webloc has file and non-file URL, and we may only have a string type
        CFURLRef destURL = NULL;
        CFURLRef fileURL = NULL;
        CFURLRef textURL = NULL;
        
        // flavorCount will be zero in case of an error...
        for (flavorIndex = 0; flavorIndex < flavorCount; flavorIndex++) {
            
            CFStringRef flavor;
            CFDataRef data;
            
            flavor = CFArrayGetValueAtIndex(flavors, flavorIndex);
            
            // !!! I'm assuming that the URL bytes are UTF-8, but that should be checked...
            
            /*
             UTIs determined with PasteboardPeeker
             Assert NULL URL on each branch; this will always be true since the pasteboard can only contain
             one flavor per type.  Using UTTypeConforms instead of UTTypeEqual could lead to a memory
             leak if there were multiple flavors conforming to kUTTypeURL (other than kUTTypeFileURL).
             The assertion silences a clang warning.
             */
            if (UTTypeEqual(flavor, kUTTypeFileURL)) {
                
                err = PasteboardCopyItemFlavorData(carbonPboard, itemID, flavor, &data);
                if (noErr == err && NULL != data) {
                    NSParameterAssert(NULL == fileURL);
                    fileURL = CFURLCreateWithBytes(NULL, CFDataGetBytePtr(data), CFDataGetLength(data), kCFStringEncodingUTF8, NULL);
                    CFRelease(data);
                }
                
            } else if (UTTypeEqual(flavor, kUTTypeURL)) {
                
                err = PasteboardCopyItemFlavorData(carbonPboard, itemID, flavor, &data);
                if (noErr == err && NULL != data) {
                    NSParameterAssert(NULL == destURL);
                    destURL = CFURLCreateWithBytes(NULL, CFDataGetBytePtr(data), CFDataGetLength(data), kCFStringEncodingUTF8, NULL);
                    CFRelease(data);
                }
                
            } else if (UTTypeEqual(flavor, kUTTypeUTF8PlainText)) {
                
                // this is a string that may be a URL; FireFox and other apps don't use any of the standard URL pasteboard types
                err = PasteboardCopyItemFlavorData(carbonPboard, itemID, kUTTypeUTF8PlainText, &data);
                if (noErr == err && NULL != data) {
                    NSParameterAssert(NULL == textURL);
                    textURL = CFURLCreateWithBytes(NULL, CFDataGetBytePtr(data), CFDataGetLength(data), kCFStringEncodingUTF8, NULL);
                    CFRelease(data);
                    
                    // CFURLCreateWithBytes will create a URL from any arbitrary string
                    if (NULL != textURL && nil == [(NSURL *)textURL scheme]) {
                        CFRelease(textURL);
                        textURL = NULL;
                    }
                }
                
            }
            
            // ignore any other type; we don't care
            
        }
        
        // only add the textURL if the destURL or fileURL were not found
        if (NULL != textURL) {
            if (NULL == destURL && NULL == fileURL)
                [toReturn addObject:(id)textURL];
            
            [allURLsReadFromPasteboard addObject:(id)textURL];
            CFRelease(textURL);
        }
        // only add the fileURL if the destURL (target of a remote URL or webloc) was not found
        if (NULL != fileURL) {
            if (NULL == destURL) 
                [toReturn addObject:(id)fileURL];
            
            [allURLsReadFromPasteboard addObject:(id)fileURL];
            CFRelease(fileURL);
        }
        // always add this if it exists
        if (NULL != destURL) {
            [toReturn addObject:(id)destURL];
            [allURLsReadFromPasteboard addObject:(id)destURL];
            CFRelease(destURL);
        }
        
        if (NULL != flavors)
            CFRelease(flavors);
    }
    
    if (carbonPboard) CFRelease(carbonPboard);
    
    // NSPasteboard only allows a single NSURL for some idiotic reason, and NSURLPboardType isn't automagically coerced to a Carbon URL pboard type.  This step handles a program like BibDesk which presently adds a webloc promise + NSURLPboardType, where we want the NSURLPboardType data and ignore the HFS promise.  However, Finder puts all of these on the pboard, so don't add duplicate items to the array...since we may have already added the content (remote URL) if this is a webloc file.
    if ([[pboard types] containsObject:NSURLPboardType]) {
        NSURL *nsURL = [NSURL URLFromPasteboard:pboard];
        if (nsURL && [allURLsReadFromPasteboard containsObject:nsURL] == NO)
            [toReturn addObject:nsURL];
    }
    
    // ??? On 10.5, NSStringPboardType and kUTTypeUTF8PlainText point to the same data, according to pasteboard peeker; if that's the case on 10.4, we can remove this and the registration for NSStringPboardType.
    if ([[pboard types] containsObject:NSStringPboardType]) {
        // this can (and does) return nil under some conditions, so avoid an exception
        NSString *stringURL = [pboard stringForType:NSStringPboardType];
        NSURL *nsURL = stringURL ? [NSURL URLWithString:stringURL] : nil;
        if ([nsURL scheme] != nil && [allURLsReadFromPasteboard containsObject:nsURL] == NO)
            [toReturn addObject:nsURL];
    }
    
    return toReturn;
}

- (BOOL)isMultiplexer;
{
    return [[[self host] lowercaseString] isEqualToString:MULTIPLEXER];
}

- (NSURL *)tlm_URLByDeletingLastPathComponent;
{
    return [(id)CFURLCreateCopyDeletingLastPathComponent(CFGetAllocator((CFURLRef)self), (CFURLRef)self) autorelease];
}

- (NSURL *)tlm_URLByAppendingPathComponent:(NSString *)pathComponent;
{
    NSParameterAssert(pathComponent);
    CFAllocatorRef alloc = CFGetAllocator((CFURLRef)self);
    return [(id)CFURLCreateCopyAppendingPathComponent(alloc, (CFURLRef)self, (CFStringRef)pathComponent, FALSE) autorelease];
}

// CFURL is pretty stupid about equality.  Among other things, it considers a double slash directory separator significant.
- (NSURL *)tlm_normalizedURL;
{
    NSURL *aURL = self;
    NSMutableString *str = [[aURL absoluteString] mutableCopy];
    NSRange startRange = [str rangeOfString:@"//"];
    NSUInteger start = NSMaxRange(startRange);
    if (startRange.length && [str replaceOccurrencesOfString:@"//" withString:@"/" options:NSLiteralSearch range:NSMakeRange(start, [str length] - start)])
        aURL = [NSURL URLWithString:str];
    [str release];
    return aURL;
}

@end
