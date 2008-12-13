//
//  TLMLogDataSource.h
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/12/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface TLMLogDataSource : NSObject 
{
@private
    NSTableView *_tableView;
    NSArray     *_messages;
    NSUInteger   _updateCount;
    NSTimer     *_updateTimer;
}

- (void)startUpdates;
- (void)stopUpdates;

@property (nonatomic, retain) IBOutlet NSTableView *_tableView;

@end
