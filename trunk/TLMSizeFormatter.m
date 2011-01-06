//
//  TLMSizeFormatter.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 8/9/09.
/*
 This software is Copyright (c) 2009-2011
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

#import "TLMSizeFormatter.h"


@implementation TLMSizeFormatter

- (NSString *)stringForObjectValue:(id)obj
{
    NSString *string = nil;
    if ([obj isKindOfClass:[NSNumber class]]) {
        
        float totalSize = [obj floatValue];
        NSString *sizeUnits = @"B";
        
        if (totalSize > 1000.0) {
            totalSize /= 1000.0;
            sizeUnits = @"KB";
        }
        
        if (totalSize > 1000.0) {
            totalSize /= 1000.0;
            sizeUnits = @"MB";
        }
        
        if (totalSize > 1000.0) {
            totalSize /= 1000.0;
            sizeUnits = @"GB";
        }
        
        string = [NSString stringWithFormat:@"%.1f %@", totalSize, sizeUnits];        
    }
    else {
        string = [obj description];
    }
    return string;
}

- (BOOL)getObjectValue:(id *)obj forString:(NSString *)string errorDescription:(NSString **)error;
{
    NSScanner *scanner = [[NSScanner alloc] initWithString:string];
    NSInteger size;
    BOOL ret = NO;
    if ([scanner scanInteger:&size] && size > 0) {
       
        NSString *units = [[scanner string] substringFromIndex:[scanner scanLocation]];
        units = [units stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([units hasPrefix:@"G"])
            size *= (1000 * 1000 * 1000);
        if ([units hasPrefix:@"K"])
            size *= (1000 * 1000);
        else if ([units isEqualToString:@"M"])
            size *= 1000;
        *obj = [NSNumber numberWithInteger:size];
        ret = YES;
    }
    else if (error) {
        *error = NSLocalizedString(@"Unable to convert to a number", @"");
        *obj = nil;
    }
    [scanner release];
    return ret;
}

@end
