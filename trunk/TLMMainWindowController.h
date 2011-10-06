//
//  TLMMainWindowController.h
//  TeX Live Utility
//
//  Created by Adam Maxwell on 12/6/08.
/*
 This software is Copyright (c) 2008-2011
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
#import "TLMTabView.h"
#import "TLMLogWindowController.h"

@class TLMStatusWindow;
@class TLMPackageListDataSource;
@class TLMUpdateListDataSource;
@class TLMInstallDataSource;
@class TLMBackupDataSource;
@class TLMAddressTextField;

enum {
    TLMDockedEdgeNone   = 0,
    TLMDockedEdgeBottom = 1,
    TLMDockedEdgeRight  = 2
};
typedef NSUInteger TLMDockedEdge;

@protocol TLMListDataSource <NSObject>
@property (nonatomic, retain) TLMStatusWindow *statusWindow;
@property (nonatomic) BOOL needsUpdate;
@end

@interface TLMMainWindowController : NSWindowController <TLMTabViewDelegate, NSWindowDelegate, TLMDockingWindowDelegate>
{
@private
    NSProgressIndicator      *_progressIndicator;
    NSProgressIndicator      *_progressBar;
    TLMTabView               *_tabView;
    TLMAddressTextField       *_URLField;
    NSURL                    *_serverURL;
    
    NSUInteger                _operationCount;
    CGFloat                   _lastTextViewHeight;
    BOOL                      _updateInfrastructure;
    NSDictionary             *_previousInfrastructureVersions;

    TLMUpdateListDataSource  *_updateListDataSource;
    TLMPackageListDataSource *_packageListDataSource;
    TLMInstallDataSource     *_installDataSource;
    TLMBackupDataSource      *_backupDataSource;
    id <TLMListDataSource>    _currentListDataSource;
    TLMDockedEdge             _dockedEdge;
}

// IB 3.2 is losing the first @property declaration unless I move this ahead of it
- (IBAction)changePapersize:(id)sender;
- (IBAction)changeAutobackup:(id)sender;
- (IBAction)automaticUpdateCheck:(id)sender;
- (IBAction)cancelAllOperations:(id)sender;
- (IBAction)changeServerURL:(id)sender;
- (IBAction)goHome:(id)sender;

@property (nonatomic, retain) IBOutlet NSProgressIndicator *_progressIndicator;
@property (nonatomic, retain) IBOutlet NSProgressIndicator *_progressBar;
@property (nonatomic, retain) IBOutlet TLMAddressTextField *_URLField;
@property (nonatomic, retain) IBOutlet TLMPackageListDataSource *_packageListDataSource;
@property (nonatomic, retain) IBOutlet TLMUpdateListDataSource *_updateListDataSource;
@property (nonatomic, retain) IBOutlet TLMInstallDataSource *_installDataSource;
@property (nonatomic, retain) IBOutlet TLMBackupDataSource *_backupDataSource;
@property (nonatomic, retain) IBOutlet TLMTabView *_tabView;
@property (nonatomic, readonly) BOOL infrastructureNeedsUpdate;
@property (nonatomic, copy) NSURL *serverURL;

// install/update actions will use serverURL
- (void)updateAllPackages;
- (void)installPackagesWithNames:(NSArray *)packageNames reinstall:(BOOL)reinstall;
- (void)updatePackagesWithNames:(NSArray *)packageNames;
- (void)netInstall;

// action to manually reinstall tlmgr itself
- (void)updateInfrastructure:(id)sender;

// alternate action to manually install tlmgr from tlcritical repo
- (void)updateInfrastructureFromCriticalRepository:(id)sender;

- (void)removePackagesWithNames:(NSArray *)packageNames force:(BOOL)force;

- (void)restorePackage:(NSString *)packageName version:(NSNumber *)version;

// both of these will use the default server URL
- (void)refreshFullPackageList;
- (void)refreshUpdatedPackageList;

// pass in a URL or nil to use default
- (void)refreshUpdatedPackageListWithURL:(NSURL *)aURL;

- (void)refreshBackupList;

@end
