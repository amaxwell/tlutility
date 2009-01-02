//
//  TLMOperations.h
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

// delivered on the main thread when -isFinished returns YES
extern NSString * const TLMOperationFinishedNotification;

@interface TLMOperation : NSOperation
{
@private
    NSTask   *_task;
    NSData   *_outputData;
    NSData   *_errorData;
    NSString *_errorMessages;
    BOOL      _failed;
}

// call -init to just get notification setup if creating a subclass that overrides -main
- (id)init;

// call to set up NSTask to be executed by -main
- (id)initWithCommand:(NSString *)absolutePath options:(NSArray *)options;

@property (readwrite, copy) NSData *outputData;
@property (readwrite, copy) NSData *errorData;
@property (readonly, copy) NSString *errorMessages;

// set if underlying task fails; check isCancelled for cancel condition
@property (readwrite) BOOL failed;

@end
