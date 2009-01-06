//
//  FVInvocationOperation.m
//  FileView
//
//  Created by Adam Maxwell on 2/23/08.
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

#import "FVInvocationOperation.h"

@implementation FVInvocationOperation

- (id)initWithInvocation:(NSInvocation *)inv;
{
    NSParameterAssert(nil != inv);
    self = [super init];
    if (self) {
        _invocation = [inv retain];
        
        // NSOperation is documented to do this
        [_invocation retainArguments];
        
        _exception = nil;
        _retdata = NULL;
        
        // spinlock since we don't expect multiple threads to ask for the return value at the same time
        _lock = OS_SPINLOCK_INIT;
    }
    return self;
}

- (id)initWithTarget:(id)target selector:(SEL)sel object:(id)arg;
{
    NSParameterAssert(nil != target);
    NSParameterAssert(NULL != sel);
    
    NSMethodSignature *sig = [target methodSignatureForSelector:sel];
    NSAssert2(nil != sig, @"%@ does not respond to %@", target, NSStringFromSelector(sel));
    
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
    [invocation setTarget:target];
    [invocation setSelector:sel];
    
    if (nil != arg) [invocation setArgument:&arg atIndex:2];
    
    return (nil != invocation) ? [self initWithInvocation:invocation] : nil;
}

- (void)dealloc
{
    if (_retdata) NSZoneFree([self zone], _retdata);
    [_invocation release];
    [_exception release];
    [super dealloc];
}

- (BOOL)isEqual:(FVInvocationOperation *)other
{
    return [other isMemberOfClass:[self class]] && [other->_invocation isEqual:_invocation];
}

- (NSUInteger)hash { return [_invocation hash]; }

- (NSInvocation *)invocation { return _invocation; }

- (void)main
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    @try {
        [_invocation invoke];
    }
    @catch (id exception) {
        _exception = [exception retain];
    }
    [self finished];
    [pool release];    
}

- (id)result;
{    
    if ([self isCancelled])
        [NSException raise:NSInvalidArgumentException format:@"asked for return value from cancelled operation"];

    id value = nil;

    NSMethodSignature *sig = [_invocation methodSignature];
    const char *returnType = [sig methodReturnType];
    
    if (strcmp(returnType, @encode(void)) == 0)
        [NSException raise:NSInvalidArgumentException format:@"asked for return value from a void method"];
            
    /* 
     Tested with -[FileView dataSource] and -[FileView bounds], so it at least works with id and NSRect return types.  I'm not terribly sanguine that it works in all cases, so it might be best just to use -invocation and extract the return value manually.  That's certainly a requirement if you use something nasty like -[(BOOL)obj getPtr:(void **)] in the invocation and are interested in the value returned by reference.
     */
    if ([self isFinished]) {
        
        if (nil != _exception)
            @throw _exception;
        
        if (strcmp(returnType, @encode(id)) == 0) {
            [_invocation getReturnValue:&value];
        }
        else {
         
            OSSpinLockLock(&_lock);
            if (NULL == _retdata) {
                _retdata = NSZoneMalloc([self zone], [sig methodReturnLength] * sizeof(char));
                [_invocation getReturnValue:&_retdata];
            }
            OSSpinLockUnlock(&_lock);
            value = [NSValue valueWithBytes:&_retdata objCType:returnType];
        }
    }
    return value;
}

@end
