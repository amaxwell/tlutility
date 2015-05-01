//
//  TLMLogWindowController.h
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 07/17/11.
/*
 This software is Copyright (c) 2008-2015
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
#import "TLMTableView.h"

@protocol TLMDockingWindowDelegate
- (void)dockableWindowGeometryDidChange:(NSWindow *)window;
- (void)dockableWindowWillClose:(NSWindow *)window;
@end

@class TLMSplitView;

@interface TLMLogWindowController : NSWindowController <NSWindowDelegate, TLMTableDataSource, NSTableViewDelegate>
{
@private
    TLMSplitView                  *_splitView;
    TLMTableView                  *_sessionTableView;
    TLMTableView                  *_messageTableView;
    CFMutableDictionaryRef         _rowHeights;
    BOOL                           _updateScheduled;
    BOOL                           _windowDidLoad;
    NSDate                        *_displayedSessionDate;
    NSMutableDictionary           *_messagesByDate;
    NSUInteger                     _lastArchiveCount;
    id <TLMDockingWindowDelegate>  _dockingDelegate;
    NSSearchField                 *_searchField;
    NSMutableArray                *_displayedMessages;
}

@property (nonatomic, retain) IBOutlet TLMTableView *_messageTableView;
@property (nonatomic, retain) IBOutlet TLMTableView *_sessionTableView;
@property (nonatomic, retain) IBOutlet TLMSplitView *_splitView;
@property (nonatomic, retain) IBOutlet NSSearchField *_searchField;
@property (nonatomic, assign) id <TLMDockingWindowDelegate> dockingDelegate;
@property (nonatomic, readonly) BOOL isWindowLoaded;

- (void)search:(id)sender;

@end

@interface TLMLogMessageCell : NSTextFieldCell
@end


