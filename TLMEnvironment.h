//
//  TLMEnvironment.h
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 06/14/11.
/*
 This software is Copyright (c) 2008-2016
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

#import <Cocoa/Cocoa.h>
#import "TLMDatabase.h"

extern NSString * const TLMDefaultRepositoryChangedNotification;

@interface TLMEnvironment : NSObject 
{
@private
    NSURL               *_legacyRepositoryURL;
    NSString            *_installDirectory;
    FSEventStreamRef     _fseventStream;
    BOOL                 _rootRequired;
    NSConditionLock     *_rootRequiredLock;
    TLMDatabaseYear      _installedYear;
}

// call when prefs change for tlmgr path or TeX distribution
+ (void)updateEnvironment;

// should be the only object needed for external usage
+ (TLMEnvironment *)currentEnvironment;

// not useful when instantiated directly
- (id)initWithInstallDirectory:(NSString *)absolutePath;

// for UI validation
+ (BOOL)isValidTexbinPath:(NSString *)absolutePath;

// main thread only; sets defaults
+ (void)setDefaultRepository:(NSURL *)absoluteURL;

// returns nil when no server can be reached; pass nil to use default URL from prefs
- (NSURL *)validServerURLFromURL:(NSURL *)fromURL;

/*
 NOTE: although property syntax is used, these keys are not necessarily
 observable with KVO at present.  Since no bindings are currently used, 
 and I only use KVO in code when there's no other option, this is not
 a problem.
 */

// composes the URL as needed
@property (readonly) NSURL *defaultServerURL;

// returns the local installation directory (/usr/local/texlive/2009)
@property (readonly, copy) NSString *installDirectory;

// adds tlmgr to TLMTexBinPathPreferenceKey, standardizes path
@property (readonly) NSString *tlmgrAbsolutePath;

// adds updmap to TLMTexBinPathPreferenceKey, standardizes path
@property (readonly) NSString *updmapAbsolutePath;

// absolute URL to backupdir option
@property (readonly) NSURL *backupDirectory;

// adds texdoc to TLMTexBinPathPreferenceKey, standardizes path
@property (readonly) NSString *texdocAbsolutePath;

// adds kpsewhich to TLMTexBinPathPreferenceKey, standardizes path
@property (readonly) NSString *kpsewhichAbsolutePath;

// adds gpg to TLMTexBinPathPreferenceKey, standardizes path
@property (readonly) NSString *gpgAbsolutePath;

// checks permission on installDirectory
@property (readonly) BOOL installRequiresRootPrivileges;

// tlmgr 2009 modifiers to update action
@property (readonly) BOOL autoInstall;
@property (readonly) BOOL autoRemove;

@property (readonly) TLMDatabaseYear texliveYear;


@end
