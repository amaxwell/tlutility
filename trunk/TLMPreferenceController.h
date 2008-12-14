//
//  TLMPreferenceController.h
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/08/08.
//

#import <Cocoa/Cocoa.h>

extern NSString * const TLMServerURLPreferenceKey;
extern NSString * const TLMTexBinPathPreferenceKey;
extern NSString * const TLMServerPathPreferenceKey;
extern NSString * const TLMUseRootHomePreferenceKey;

@interface TLMPreferenceController : NSWindowController 
{
@private
    NSPathControl *_texbinPathControl;
    NSComboBox    *_serverComboBox;
    NSButton      *_rootHomeCheckBox;
    NSArray       *_servers;
}

+ (id)sharedPreferenceController;
- (IBAction)changeTexBinPath:(id)sender;
- (IBAction)changeServerURL:(id)sender;
- (IBAction)toggleUseRootHome:(id)sender;

@property (nonatomic, retain) IBOutlet NSPathControl *_texbinPathControl;
@property (nonatomic, retain) IBOutlet NSComboBox *_serverComboBox;
@property (nonatomic, retain) IBOutlet NSButton *_rootHomeCheckBox;

// composes TLMServerURLPreferenceKey and TLMServerPathPreferenceKey
@property (readonly) NSURL *defaultServerURL;

// adds tlmgr to TLMTexBinPathPreferenceKey, standardizes path
@property (readonly) NSString *tlmgrAbsolutePath;

@end
