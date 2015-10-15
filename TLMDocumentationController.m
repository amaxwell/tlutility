//
//  TLMDocumentationController.m
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 10/10/15.
//
//

#import "TLMDocumentationController.h"
#import "TLMOptionOperation.h"

@implementation TLMDocumentationController

@synthesize _enableCheckbox;
@synthesize _dismissButton;
@synthesize _installButton;

- (id)init
{
    return [super initWithWindowNibName:[self windowNibName]];
}

- (NSString *)windowNibName { return @"DocumentationSheet"; }

- (void)awakeFromNib
{
    _shouldInstall = [TLMOptionOperation boolValueOfOption:@"docfiles"];
    [_enableCheckbox setState:(_shouldInstall ? NSOnState : NSOffState)];
    [_installButton setEnabled:_shouldInstall];
}

- (void)dealloc
{
    [_enableCheckbox release];
    [_dismissButton release];
    [_installButton release];
    [super dealloc];
}

- (IBAction)enableAction:(id)sender;
{
    _changedOption = YES;
    _shouldInstall = [sender state] == NSOnState ? YES : NO;
    [_installButton setEnabled:_shouldInstall];
}

- (IBAction)dismiss:(id)sender;
{
    TLMDocumentationReturnCode rc = TLMDocumentationUnchanged;
    if (_changedOption)
        rc |= TLMDocumentationChanged;
    if (_shouldInstall)
        rc |= TLMDocumentationInstallLater;
    [NSApp endSheet:[self window] returnCode:rc];
}

- (IBAction)install:(id)sender;
{
    TLMDocumentationReturnCode rc = TLMDocumentationUnchanged;
    if (_changedOption)
        rc |= TLMDocumentationChanged;
    // required; can't install docs unless this is set (duh)
    if (_shouldInstall)
        rc |= TLMDocumentationInstallLater;
    rc |= TLMDocumentationInstallNow;
    [NSApp endSheet:[self window] returnCode:rc];
}

@end
