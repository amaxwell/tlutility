//
//  TLMDocumentationController.h
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 10/10/15.
//
//

#import <Cocoa/Cocoa.h>

enum {
    TLMDocumentationUnchanged    = 0,        /* don't change option                 */
    TLMDocumentationChanged      = (1 << 1), /* need to change option               */
    TLMDocumentationInstallNow   = (1 << 2), /* run install for packages now        */
    TLMDocumentationInstallLater = (1 << 3)  /* if set, option = 1, else option = 0 */
};
typedef NSInteger TLMDocumentationReturnCode;

@interface TLMDocumentationController : NSWindowController
{
@private
    NSButton *_enableCheckbox;
    NSButton *_dismissButton;
    NSButton *_installButton;
    BOOL      _shouldInstall;
    BOOL      _changedOption;
}

@property (nonatomic, retain) IBOutlet NSButton *_enableCheckbox;
@property (nonatomic, retain) IBOutlet NSButton *_dismissButton;
@property (nonatomic, retain) IBOutlet NSButton *_installButton;

- (IBAction)dismiss:(id)sender;
- (IBAction)install:(id)sender;
- (IBAction)enableAction:(id)sender;

@end
