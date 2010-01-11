//
//  TLMReleaseNotesController.h
//  TeX Live Manager
//
//  Created by Adam Maxwell on 1/12/09.
/*
 This software is Copyright (c) 2009-2010
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
#import <WebKit/WebKit.h>

#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
@interface TLMReleaseNotesController : NSWindowController <NSTableViewDelegate>
#else
@interface TLMReleaseNotesController : NSWindowController
#endif
{
@private
    NSArray             *_versions;
    NSDictionary        *_notes;
    NSTableView         *_versionsTable;
    WebView             *_notesView;
    NSProgressIndicator *_progressIndicator;
    NSString            *_downloadPath;
    NSTextField         *_statusField;
}

+ (TLMReleaseNotesController *)sharedInstance;

@property (nonatomic, retain) IBOutlet NSTableView *_versionsTable;
@property (nonatomic, retain) IBOutlet WebView *_notesView;
@property (nonatomic, retain) IBOutlet NSProgressIndicator *_progressIndicator;
@property (nonatomic, retain) IBOutlet NSTextField *_statusField;

@property (nonatomic, copy) NSDictionary *notes;
@property (nonatomic, copy) NSArray *versions;

@end
