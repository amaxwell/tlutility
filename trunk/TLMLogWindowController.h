//
//  TLMLogWindowController.h
//  TeX Live Manager
//
//  Created by Adam R. Maxwell on 07/17/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class TLMTableView;

@interface TLMLogWindowController : NSWindowController
{
@private
    TLMTableView           *_tableView;
    NSMutableArray         *_messages;
    CFMutableDictionaryRef  _rowHeights;
    BOOL                    _updateScheduled;
}

@property (nonatomic, retain) IBOutlet TLMTableView *_tableView;

@end

@interface TLMLogMessageCell : NSTextFieldCell
@end
