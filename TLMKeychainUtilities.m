//
//  KeychainUtilities.m
//  TeX Live Manager
//
//  Created by Adam R. Maxwell on 12/10/09.
/*
 This software is Copyright (c) 2009
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

#import "TLMKeychainUtilities.h"
#import "TLMLogServer.h"
#import <CoreServices/CoreServices.h>
#import <Security/Security.h>

bool TLMGetUserAndPassForProxy(NSString **user, NSString **pass, NSString *host, const uint16_t port)
{
    NSCParameterAssert(user);
    NSCParameterAssert(pass);
    NSCParameterAssert(host);
    OSStatus err;
    
    const char *server = [host UTF8String];
    UInt32 len;
    void *pw;
    SecKeychainItemRef item;
    
    /*
     We're trying to get info on a proxy, so passing e.g. kSecProtocolTypeHTTPProxy seems to make sense.
     However, that doesn't work, so we go with the more general rule of being as vague as reasonably
     possible when finding the password.
     */
    err = SecKeychainFindInternetPassword(NULL, strlen(server), server, 0, NULL, 0, NULL, 0, NULL, port, kSecProtocolTypeAny, kSecAuthenticationTypeAny, &len, &pw, &item);
    
    /*
     Should return failure if the user's proxy doesn't have a password in the keychain.  Note that
     removing a proxy in Sys Prefs or unchecking the password box will remove the proxy password
     from the keychain.
     */
    if (noErr != err) {
        TLMLog(__func__, @"SecKeychainFindInternetPassword: %s", GetMacOSStatusErrorString(err));
        return false;
    }
    
    *pass = nil;
    if (pw) *pass = [[[NSString alloc] initWithBytes:pw length:len encoding:NSUTF8StringEncoding] autorelease];
    
    
    /*
     The remaining code is required to read the account name from the keychain item.  Much of
     it was borrowed from
     
     http://www.opensource.apple.com/source/SecurityTool/SecurityTool-32482/keychain_utilities.c?f=text
     
     since this stuff is not really well documented.
     
     Asserts are used in place of error handling, since in most cases I'm not sure how to handle the
     errors in a useful way.
     */
    
    SecKeychainItemFreeContent(NULL, pw);
    
    // call this first to get the item class
    // http://lists.apple.com/archives/Apple-cdsa/2008/Nov/msg00046.html
    SecItemClass itemClass;
    err = SecKeychainItemCopyAttributesAndData(item, NULL, &itemClass, NULL, NULL, NULL);
    assert(noErr == err);
    
    UInt32 itemID;
    switch (itemClass) {
            
        case kSecInternetPasswordItemClass:
            itemID = CSSM_DL_DB_RECORD_INTERNET_PASSWORD;
            break;
        case kSecGenericPasswordItemClass:
            itemID = CSSM_DL_DB_RECORD_GENERIC_PASSWORD;
            break;
        case kSecAppleSharePasswordItemClass:
            itemID = CSSM_DL_DB_RECORD_APPLESHARE_PASSWORD;
            break;
        default:
            itemID = itemClass;
            break;
	}
    
    SecKeychainRef keychain = NULL;
    err = SecKeychainItemCopyKeychain(item, &keychain);
    assert(noErr == err);
    
    SecKeychainAttributeInfo *attrInfo = NULL;
    err = SecKeychainAttributeInfoForItemID(NULL, itemID, &attrInfo);
    assert(noErr == err);
    
    SecKeychainAttributeList *attrList = NULL;
    void *attrs;
    
    // finally, we can actually copy the attributes out of this thing
    err = SecKeychainItemCopyAttributesAndData(item, attrInfo, NULL, &attrList, &len, &attrs);
    assert(noErr == err);
    assert(attrInfo->count == attrList->count);
    
    UInt32 ix;
    *user = nil;
    
    // keychain items appear to have no introspection, so we just have to loop until we find the right tag
    for (ix = 0; ix < attrInfo->count; ix++) {
        
        UInt32 tag = attrInfo->tag[ix];
        UInt32 format = attrInfo->format[ix];
        SecKeychainAttribute *attribute = &attrList->attr[ix];
        assert(tag == attribute->tag);
        
        // CSSM_DB_ATTRIBUTE_FORMAT_BLOB determined by debugging
        if (CSSM_DB_ATTRIBUTE_FORMAT_BLOB != format && CSSM_DB_ATTRIBUTE_FORMAT_STRING != format) continue;
        
        if (0 == attribute->length && NULL == attribute->data) continue;
        
        if (attribute->tag == kSecAccountItemAttr) {
            *user = [[[NSString alloc] initWithBytes:attribute->data length:attribute->length encoding:NSUTF8StringEncoding] autorelease];
            break;
        }
    }
    
    if (keychain) CFRelease(keychain);
    (void) SecKeychainFreeAttributeInfo(attrInfo);
    (void) SecKeychainItemFreeAttributesAndData(attrList, attrs);
    
    return true;
}
