//
//  TLMProgressIndicatorCell.h
//  FileView
//
//  Created by Adam Maxwell on 2/15/08.
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

/*
 */

/** @file TLMProgressIndicatorCell.h Circular determinate progress indicator. */
enum {
    TLMProgressIndicatorIndeterminate = -1,
    TLMProgressIndicatorDeterminate   = 0
};
typedef NSInteger TLMProgressIndicatorStyle;

/** @brief Filled arc progress indicator
 
 TLMProgressIndicatorCell is a custom progress indicator that draws a filled arc in a circle.  It exists to work around a number of deficiencies in NSProgressIndicator:
 
 @li TLMProgressIndicatorCell allows a determinate progress indicator in a small area
 @li we can modify TLMProgressIndicatorCell slightly to draw an indeterminate indicator
 @li performance of spinning NSProgressIndicator sucks (they flicker when scrolling)
 @li spinning NSProgressIndicator has some undocumented maximum size (32x32?) 
 */
@interface TLMProgressIndicatorCell : NSCell
{
@private
    CGColorRef               _fillColor;
    CGColorRef               _strokeColor;
    CGFloat                  _currentProgress;
    CGFloat                  _currentRotation;
    TLMProgressIndicatorStyle _style;
}

+ (NSImage *)applicationIconBadgedWithProgress:(CGFloat)progress;

/** @brief Initializer.
 
 Initializes a new progress indicator with TLMProgressIndicatorDeterminate style
 @return The progress indicator. */
- (id)init;

/** @brief Change the progress value.
 
 Sets the value of the progress indicator (size of the filled sector) as a percentage.  A value of 1.00 will fill the entire circle.
 @param progress The progress value. */
- (void)setCurrentProgress:(CGFloat)progress;

/** @brief Current progress value.
 
 @return Current progress value. */
- (CGFloat)currentProgress;

/** @brief Change the style.
 
 Set the style of the progress indicator to determinate or indeterminate.  This should generally be set before updating currentProgress.
 @param style Progress indicator style. */
- (void)setStyle:(TLMProgressIndicatorStyle)style;

@end

/** @var TLMProgressIndicatorIndeterminate
 Indeterminate progress indicatory style
 */
/** @var TLMProgressIndicatorDeterminate
 Determinate progress indicator style
 */
