//
//  TLMLogServer.h
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/13/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

extern NSString * const TLMLogServerUpdateNotification;

@interface TLMLogServer : NSObject 
{
@private
    NSMutableArray *_messages;
    NSConnection   *_connection;
}

+ (id)sharedServer;
@property(readonly, retain) NSArray *messages;

@end

__BEGIN_DECLS
extern void TLMLog(NSString *sender, NSString *format, ...);
__END_DECLS

