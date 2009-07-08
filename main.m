//
//  main.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/6/08.
/*
 This software is Copyright (c) 2008-2009
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

int main(int argc, char *argv[])
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    /*
     The old bundle identifier was "com.google.mactlmgr.TeX_Live_Utility", which has an incorrect domain and is annoying to type.
     We need to preserve previously-set preferences, though, so we'll manually copy the preferences file over.  This has to be done
     in main(), since +[TLMAppController initialize] is too late.  CFPreferencesCopyMultiple() returns an empty dictionary, so it's
     useless for getting the old prefs.  Copying them one-by-one with CFPreferencesCopyAppValue() works, but we want the Apple
     settings also, and don't have an exhaustive list of those.  Hence, moving the file is the only way to do this.
     */
    FSRef prefsFolder;
    NSString *prefsFolderPath = nil;
    if (noErr == FSFindFolder(kUserDomain, kPreferencesFolderType, TRUE, &prefsFolder))
        prefsFolderPath = [[(id)CFURLCreateFromFSRef(CFAllocatorGetDefault(), &prefsFolder) autorelease] path];
    
    NSString *oldPrefsPath = nil;
    if (prefsFolderPath)
        oldPrefsPath = [prefsFolderPath stringByAppendingPathComponent:@"com.google.mactlmgr.TeX_Live_Utility.plist"];
    NSString *newPrefsPath = [prefsFolderPath stringByAppendingPathComponent:[[NSBundle mainBundle] objectForInfoDictionaryKey:(id)kCFBundleIdentifierKey]];
    if (newPrefsPath)
        newPrefsPath = [newPrefsPath stringByAppendingPathExtension:@"plist"];
    
    if (oldPrefsPath && newPrefsPath && [[NSFileManager defaultManager] isReadableFileAtPath:oldPrefsPath]) {
        if ([[NSFileManager defaultManager] isReadableFileAtPath:newPrefsPath] == NO) {
            [[NSFileManager defaultManager] moveItemAtPath:oldPrefsPath toPath:newPrefsPath error:NULL];
            NSLog(@"Migrating old preferences%C", 0x2026);
        }
    }
    [pool release];
    
    return NSApplicationMain(argc,  (const char **) argv);
}
