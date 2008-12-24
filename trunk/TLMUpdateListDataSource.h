//
//  TLMUpdateListDataSource.h
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/23/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class TLMMainWindowController;

@interface TLMUpdateListDataSource : NSResponder 
{
@private
    NSTableView             *_tableView;
    NSMutableArray          *_packages;
    NSArray                 *_allPackages;
    NSMutableArray          *_sortDescriptors;
    BOOL                     _sortAscending;
    NSSearchField           *_searchField;
    TLMMainWindowController *_controller;
}

@property (nonatomic, retain) IBOutlet NSTableView *tableView;
@property (nonatomic, assign) IBOutlet TLMMainWindowController *_controller;
@property (nonatomic, retain) IBOutlet NSSearchField *_searchField;
@property (readwrite, copy) NSArray *allPackages;

- (IBAction)listUpdates:(id)sender;
- (IBAction)installSelectedRow:(id)sender;
- (IBAction)removeSelectedRow:(id)sender;
- (IBAction)showInfo:(id)sender;

- (IBAction)search:(id)sender;

@end
