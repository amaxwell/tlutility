//
//  TLMAddressTextField.m
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 07/24/11.
/*
 This software is Copyright (c) 2011
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

#import "TLMAddressTextField.h"
#import "TLMMirrorCell.h"
#import "BDSKTextViewCompletionController.h"

@implementation TLMMirrorFieldEditor

- (void)handleTextDidBeginEditingNotification:(NSNotification *)note { _isEditing = YES; }

- (void)handleTextDidEndEditingNotification:(NSNotification *)note { _isEditing = NO; }

- (void)viewWillMoveToWindow:(NSWindow *)newWindow
{
    [super viewWillMoveToWindow:newWindow];
    if (newWindow) {
        [self registerForDraggedTypes:[NSArray arrayWithObjects:NSURLPboardType, (id)kUTTypeURL, NSStringPboardType, nil]];
        [[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(handleTextDidBeginEditingNotification:)
													 name:NSTextDidBeginEditingNotification
												   object:self];
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(handleTextDidEndEditingNotification:)
													 name:NSTextDidEndEditingNotification
												   object:self];
    }
    else {
        [self unregisterDraggedTypes];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSTextDidBeginEditingNotification object:self];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSTextDidEndEditingNotification object:self];
    }
}

- (BOOL)isFieldEditor { return YES; }

- (BOOL)dragChangedText { return _dragChangedText; }

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender { 
    _dragChangedText = NO;
    return [sender draggingSource] == [self delegate] ? NSDragOperationNone : NSDragOperationCopy; 
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender { 
    [[self window] makeFirstResponder:nil];
    _dragChangedText = NO;
}

- (BOOL)setStringFromDragOperation:(NSString *)aString
{
    if ([[self string] isEqualToString:aString])
        return NO;

    [self setString:aString];
    _dragChangedText = YES;
    return YES;
}

- (BOOL)performDragOperation:(id < NSDraggingInfo >)sender
{
    NSPasteboard *pboard = [sender draggingPasteboard];
    NSString *type = [pboard availableTypeFromArray:[NSArray arrayWithObjects:NSURLPboardType, (id)kUTTypeURL, NSStringPboardType, nil]];
    BOOL rv = NO;
    if ([type isEqualToString:NSURLPboardType]) {
        rv = [self setStringFromDragOperation:[[NSURL URLFromPasteboard:pboard] absoluteString]];
    }
    else if ([type isEqualToString:(id)kUTTypeURL]) {
        rv = [self setStringFromDragOperation:[pboard stringForType:type]];
    }
    else if ([type isEqualToString:NSStringPboardType]) {
        rv = [self setStringFromDragOperation:[pboard stringForType:type]];
    }
    return rv;
}

- (BOOL)prepareForDragOperation:(id < NSDraggingInfo >)sender { return YES; }

#pragma mark Completion methods

static inline BOOL completionWindowIsVisibleForTextView(NSTextView *textView)
{
    BDSKTextViewCompletionController *controller = [BDSKTextViewCompletionController sharedController];
    return ([[controller completionWindow] isVisible] && [[controller currentTextView] isEqual:textView]);
}

static inline BOOL forwardSelectorForCompletionInTextView(SEL selector, NSTextView *textView)
{
    if(completionWindowIsVisibleForTextView(textView)){
        [[BDSKTextViewCompletionController sharedController] performSelector:selector withObject:nil];
        return YES;
    }
    return NO;
}

- (void)doAutoCompleteIfPossible {
	if (completionWindowIsVisibleForTextView(self) == NO && _isEditing) {
        if ([[self delegate] respondsToSelector:@selector(textViewShouldAutoComplete:)] &&
            [(id <BDSKFieldEditorDelegate>)[self delegate] textViewShouldAutoComplete:self])
            [self complete:self]; // NB: the self argument is critical here (see comment in complete:)
    }
} 

// insertText: and deleteBackward: affect the text content, so we send to super first, then autocomplete unconditionally since the completion controller needs to see the changes
- (void)insertText:(id)insertString {
    [super insertText:insertString];
    [self doAutoCompleteIfPossible];
    // passing a nil argument to the completion controller's insertText: is safe, and we can ensure the completion window is visible this way
    forwardSelectorForCompletionInTextView(_cmd, self);
}

- (void)deleteBackward:(id)sender {
    [super deleteBackward:(id)sender];
    // deleting a spelling error should also show the completions again
    [self doAutoCompleteIfPossible];
    forwardSelectorForCompletionInTextView(_cmd, self);
}

// moveLeft and moveRight should happen regardless of completion, or you can't navigate the line with arrow keys
- (void)moveLeft:(id)sender {
    forwardSelectorForCompletionInTextView(_cmd, self);
    [super moveLeft:sender];
}

- (void)moveRight:(id)sender {
    forwardSelectorForCompletionInTextView(_cmd, self);
    [super moveRight:sender];
}

// the following movement methods are conditional based on whether the autocomplete window is visible
- (void)moveUp:(id)sender {
    if(forwardSelectorForCompletionInTextView(_cmd, self) == NO)
        [super moveUp:sender];
}

- (void)moveDown:(id)sender {
    if(forwardSelectorForCompletionInTextView(_cmd, self) == NO)
        [super moveDown:sender];
}

- (void)insertTab:(id)sender {
    if(forwardSelectorForCompletionInTextView(_cmd, self) == NO)
        [super insertTab:sender];
}

- (void)insertNewline:(id)sender {
    if(forwardSelectorForCompletionInTextView(_cmd, self) == NO)
        [super insertNewline:sender];
}

- (NSRange)rangeForUserCompletion {
    // @@ check this if we have problems inserting accented characters; super's implementation can mess that up
    NSParameterAssert([self markedRange].length == 0);    
    NSRange charRange = [super rangeForUserCompletion];
	if ([[self delegate] respondsToSelector:@selector(textView:rangeForUserCompletion:)]) 
		return [(id <BDSKFieldEditorDelegate>)[self delegate] textView:self rangeForUserCompletion:charRange];
	return charRange;
}

#pragma mark Auto-completion methods

- (NSArray *)completionsForPartialWordRange:(NSRange)charRange indexOfSelectedItem:(NSInteger *)idx;
{
    id delegate = [self delegate];
    SEL delegateSEL = @selector(control:textView:completions:forPartialWordRange:indexOfSelectedItem:);
    NSParameterAssert(delegate == nil || [delegate isKindOfClass:[NSControl class]]); // typically the NSForm
    
    NSArray *completions = nil;
    
    if([delegate respondsToSelector:delegateSEL])
        completions = [delegate control:delegate textView:self completions:nil forPartialWordRange:charRange indexOfSelectedItem:idx];
    else if([[[self window] delegate] respondsToSelector:delegateSEL])
        completions = [(id)[[self window] delegate] control:delegate textView:self completions:nil forPartialWordRange:charRange indexOfSelectedItem:idx];
    
    // Default is to call -[NSSpellChecker completionsForPartialWordRange:inString:language:inSpellDocumentWithTag:], but this apparently sends a DO message to CocoAspell (in a separate process), and we block the main runloop until it returns a long time later.  Lacking a way to determine whether the system speller (which works fine) or CocoAspell is in use, we'll just return our own completions.
    return completions;
}

- (void)complete:(id)sender;
{
    // forward this method so the controller can handle cancellation and undo
    if(forwardSelectorForCompletionInTextView(_cmd, self))
        return;
    
    NSRange selRange = [self rangeForUserCompletion];
    NSString *string = [self string];
    if(selRange.location == NSNotFound || [string isEqualToString:@""] || selRange.length == 0)
        return;
    
    // make sure to initialize this
    NSInteger idx = 0;
    NSArray *completions = [self completionsForPartialWordRange:selRange indexOfSelectedItem:&idx];
    
    if(sender == self) // auto-complete, don't select an item
		idx = -1;
	
    [[BDSKTextViewCompletionController sharedController] displayCompletions:completions indexOfSelectedItem:idx forPartialWordRange:selRange originalString:[string substringWithRange:selRange] atPoint:[self locationForCompletionWindow] forTextView:self];
}

- (NSRange)selectionRangeForProposedRange:(NSRange)proposedSelRange granularity:(NSSelectionGranularity)granularity {
    if(completionWindowIsVisibleForTextView(self))
        [[BDSKTextViewCompletionController sharedController] endDisplayNoComplete];
    return [super selectionRangeForProposedRange:proposedSelRange granularity:granularity];
}

- (BOOL)becomeFirstResponder {
    if(completionWindowIsVisibleForTextView(self))
        [[BDSKTextViewCompletionController sharedController] endDisplayNoComplete];
    return [super becomeFirstResponder];
}

- (BOOL)resignFirstResponder {
    if(completionWindowIsVisibleForTextView(self))
        [[BDSKTextViewCompletionController sharedController] endDisplayNoComplete];
    return [super resignFirstResponder];
}

@end



@implementation TLMAddressTextField

/*
 I tried NSTrackingArea, but it only works on the fringes of the icon, or if you enter the
 icon area from inside the cell.  Entering from the bottom, left, or top of the icon did
 not work.  Since this works and is a single line of code instead of multiple overrides
 and an ivar to get something partially functional...I say NSTrackingArea officially sucks.
 */
- (void)resetCursorRects
{
    [self addCursorRect:[[self cell] iconRectForBounds:[self bounds]] cursor:[NSCursor arrowCursor]];
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow
{
    [super viewWillMoveToWindow:newWindow];
    if (newWindow) {
        [self registerForDraggedTypes:[NSArray arrayWithObjects:NSURLPboardType, (id)kUTTypeURL, NSStringPboardType, nil]];
    }
    else {
        [self unregisterDraggedTypes];
    }
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender { 
    _dragChangedText = NO;
    return [sender draggingSource] == self ? NSDragOperationNone : NSDragOperationCopy; 
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender { 
    if ([[self window] makeFirstResponder:nil])
        [self sendAction:[self action] to:[self target]];
    _dragChangedText = NO;
}

- (BOOL)setStringFromDragOperation:(NSString *)aString
{
    if ([[self stringValue] isEqualToString:aString])
        return NO;
    
    [self setStringValue:aString];
    _dragChangedText = YES;
    return YES;
}

- (BOOL)performDragOperation:(id < NSDraggingInfo >)sender
{
    NSPasteboard *pboard = [sender draggingPasteboard];
    NSString *type = [pboard availableTypeFromArray:[NSArray arrayWithObjects:NSURLPboardType, (id)kUTTypeURL, NSStringPboardType, nil]];
    BOOL rv = NO;
    if ([type isEqualToString:NSURLPboardType]) {
        rv = [self setStringFromDragOperation:[[NSURL URLFromPasteboard:pboard] absoluteString]];
    }
    else if ([type isEqualToString:(id)kUTTypeURL]) {
        rv = [self setStringFromDragOperation:[pboard stringForType:type]];
    }
    else if ([type isEqualToString:NSStringPboardType]) {
        rv = [self setStringFromDragOperation:[pboard stringForType:type]];
    }
    return rv;
}

- (BOOL)prepareForDragOperation:(id < NSDraggingInfo >)sender { return YES; }

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)flag { return NSDragOperationCopy; }

- (void)textDidChange:(NSNotification *)notification
{
    [super textDidChange:notification];
    _dragChangedText = YES;
}

/*
 The _dragChangedText business is to avoid sending spurious action messages
 when text hasn't actually changed due to drag-and-drop or direct editing.
 By default, it sends it every time you click on the icon, which is a bit
 much if the action does anything nontrivial.
 */
- (void)textDidEndEditing:(NSNotification *)notification
{
    TLMMirrorFieldEditor *editor = [notification object];
    if ([editor dragChangedText] || _dragChangedText)
        [super textDidEndEditing:notification];
}

- (NSRange)textView:(NSTextView *)textView rangeForUserCompletion:(NSRange)charRange {
	if (textView == [self currentEditor] && [[self delegate] respondsToSelector:@selector(control:textView:rangeForUserCompletion:)]) 
		return [(id)[self delegate] control:self textView:textView rangeForUserCompletion:charRange];
	return charRange;
}

- (BOOL)textViewShouldAutoComplete:(NSTextView *)textView {
	if (textView == [self currentEditor] && [[self delegate] respondsToSelector:@selector(control:textViewShouldAutoComplete:)]) 
		return [(id)[self delegate] control:self textViewShouldAutoComplete:textView];
	return NO;
}

- (void)setButtonImage:(NSImage *)image { [[self cell] setButtonImage:image]; }
- (void)setButtonAction:(SEL)action { [[self cell] setButtonAction:action]; }
- (void)setButtonTarget:(id)target { [[self cell] setButtonTarget:target]; }

@end
