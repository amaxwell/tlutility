//
//  TLMInfraUpdateOperation.h
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/16/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "TLMUpdateOperation.h"

@interface TLMInfraUpdateOperation : TLMUpdateOperation
{
@private
    NSString *_updateDirectory;
    NSString *_scriptPath;
    NSURL    *_location;
}

- (id)initWithLocation:(NSURL *)location;

@end
