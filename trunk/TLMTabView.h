//
//  TLMTabView.h
//  TabViewTest
//
//  Created by Adam Maxwell on 12/23/08.
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

#import <Cocoa/Cocoa.h>

/*
 Question:  Why not use an NSTabView and set everything up in IB?  Why reimplement it with fewer features?
 
 Answer:  Because positioning views inside a tabview is huge PITA.  NSTabView also draws an annoying bezel border unless you set up a tabless tabview and use a separate control.  When the tabview is inside a splitview, things are even worse, and there's basically no chance of getting the view geometry correct in IB...and if you take it apart and reassemble, you have to set everything up again.
 
 */

@protocol TLMTabViewDelegate;

@interface TLMTabView : NSView 
{
@private
    NSSegmentedControl      *_tabControl;
    NSMutableArray          *_views;
    NSView                  *_currentView;
    NSInteger                _selectedIndex;
    id <TLMTabViewDelegate>  _delegate;
    NSArray                 *_transitionViews;
}

- (void)addTabNamed:(NSString *)tabName withView:(NSView *)aView;
- (NSView *)viewAtIndex:(NSUInteger)anIndex;
- (void)selectViewAtIndex:(NSUInteger)anIndex;

@property (nonatomic, assign) id <TLMTabViewDelegate> delegate;

@end

@protocol TLMTabViewDelegate <NSObject>
@optional
- (void)tabView:(TLMTabView *)tabView didSelectViewAtIndex:(NSUInteger)anIndex;
@end
