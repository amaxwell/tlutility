//
//  TLMPreferenceController.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/08/08.
//

#import "TLMPreferenceController.h"
#import "TLMURLFormatter.h"

NSString * const TLMServerURLPreferenceKey = @"TLMServerURLPreferenceKey";     /* http://mirror.ctan.org      */
NSString * const TLMTexBinPathPreferenceKey = @"TLMTexBinPathPreferenceKey";   /* /usr/texbin                 */
NSString * const TLMServerPathPreferenceKey = @"TLMServerPathPreferenceKey";   /* systems/texlive/tlnet/2008  */
NSString * const TLMUseRootHomePreferenceKey = @"TLMUseRootHomePreferenceKey"; /* YES                         */

#define TLMGR_CMD @"tlmgr"

@implementation TLMPreferenceController

@synthesize _texbinPathControl;
@synthesize _serverComboBox;
@synthesize _rootHomeCheckBox;

+ (id)sharedPreferenceController;
{
    static id sharedInstance = nil;
    if (nil == sharedInstance)
        sharedInstance = [self new];
    return sharedInstance;
}

- (id)init
{
    return [self initWithWindowNibName:[self windowNibName]];
}

- (id)initWithWindowNibName:(NSString *)name
{
    self = [super initWithWindowNibName:name];
    if (self) {
        NSMutableArray *servers = [NSMutableArray array];
        // current server from prefs seems to be added automatically when setting stringValue
        [servers addObject:@"http://mirror.ctan.org"];
        [servers addObject:@"http://ctan.math.utah.edu/tex-archive"];
        [servers addObject:@"http://gentoo.chem.wisc.edu/tex-archive"];
        [servers addObject:@"ftp://ftp.heanet.ie/pub/CTAN/tex"];
        [servers addObject:@"http://mirrors.ircam.fr/pub/CTAN"];
        _servers = [servers copy];
    }
    return self;
}

- (void)dealloc
{
    [_texbinPathControl release];
    [_serverComboBox release];
    [_rootHomeCheckBox release];
    [_servers release];
    [super dealloc];
}

- (void)awakeFromNib
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *texbinPath = [defaults objectForKey:TLMTexBinPathPreferenceKey];
    [_texbinPathControl setURL:[NSURL fileURLWithPath:texbinPath]];    
    // only display the hostname part
    [_serverComboBox setStringValue:[defaults objectForKey:TLMServerURLPreferenceKey]];
    [_serverComboBox setFormatter:[[TLMURLFormatter new] autorelease]];
    [_serverComboBox setDelegate:self];
    
    if ([defaults boolForKey:TLMUseRootHomePreferenceKey])
        [_rootHomeCheckBox setState:NSOnState];
    else
        [_rootHomeCheckBox setState:NSOffState];         
}

- (IBAction)toggleUseRootHome:(id)sender;
{
    [[NSUserDefaults standardUserDefaults] setBool:([sender state] == NSOnState) forKey:TLMUseRootHomePreferenceKey];
}

- (void)updateTeXBinPathWithURL:(NSURL *)aURL
{
    [_texbinPathControl setURL:aURL];
    [[NSUserDefaults standardUserDefaults] setObject:[aURL path] forKey:TLMTexBinPathPreferenceKey];
}

- (void)openPanelDidEnd:(NSOpenPanel*)panel returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    [panel orderOut:self];
    
    if (NSOKButton == returnCode) {
        [self updateTeXBinPathWithURL:[panel URL]];
    }
}

- (IBAction)changeTexBinPath:(id)sender
{
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    [openPanel setCanChooseDirectories:YES];
    // avoid resolving symlinks
    [openPanel setResolvesAliases:NO];
    [openPanel setCanChooseFiles:NO];
    [openPanel setAllowsMultipleSelection:NO];
    [openPanel setPrompt:NSLocalizedString(@"Choose", @"")];
    [openPanel beginSheetForDirectory:@"/usr" file:nil 
                       modalForWindow:[self window] modalDelegate:self 
                       didEndSelector:@selector(openPanelDidEnd:returnCode:contextInfo:) contextInfo:NULL];
}

- (IBAction)changeServerURL:(id)sender
{
    NSString *serverURLString = [[sender cell] stringValue];
    [[NSUserDefaults standardUserDefaults] setObject:serverURLString forKey:TLMServerURLPreferenceKey];
}

- (NSString *)windowNibName { return @"Preferences"; }

- (NSURL *)defaultServerURL
{
    // There's a race here if the server path is ever user-settable, but at present it's only for future-proofing.
    NSURL *base = [NSURL URLWithString:[[NSUserDefaults standardUserDefaults] objectForKey:TLMServerURLPreferenceKey]];
    NSString *path = [[NSUserDefaults standardUserDefaults] objectForKey:TLMServerPathPreferenceKey];
    CFURLRef fullURL = CFURLCreateCopyAppendingPathComponent(CFGetAllocator(base), (CFURLRef)base, (CFStringRef)path, TRUE);
    return [(id)fullURL autorelease];
}

- (NSString *)tlmgrAbsolutePath
{
    NSString *texbinPath = [[NSUserDefaults standardUserDefaults] objectForKey:TLMTexBinPathPreferenceKey];
    return [[texbinPath stringByAppendingPathComponent:TLMGR_CMD] stringByStandardizingPath];
}


#pragma mark Server combo box datasource

- (NSInteger)numberOfItemsInComboBox:(NSComboBox *)aComboBox;
{
    return [_servers count];
}

- (id)comboBox:(NSComboBox *)aComboBox objectValueForItemAtIndex:(NSInteger)idx;
{
    return [_servers objectAtIndex:idx];
}

- (NSUInteger)comboBox:(NSComboBox *)aComboBox indexOfItemWithStringValue:(NSString *)string;
{
    NSUInteger i = 0;
    for (NSString *value in _servers) {
        if ([string isEqualToString:value])
            return i;
        i++;
    }
    return NSNotFound;
}

# pragma mark Input validation

- (BOOL)control:(NSControl *)control didFailToFormatString:(NSString *)string errorDescription:(NSString *)error
{
    NSAlert *alert = [NSAlert alertWithMessageText:error defaultButton:NSLocalizedString(@"Edit", @"") 
                                   alternateButton:NSLocalizedString(@"Ignore", @"") 
                                       otherButton:nil 
                         informativeTextWithFormat:NSLocalizedString(@"Choose \"Edit\" to fix the value, or \"Ignore\" to use the invalid URL.", @"")];
    NSInteger rv = [alert runModal];
    
    // return YES to accept as-is, NO to edit again
    return NSAlertDefaultReturn != rv;
}

// make sure to end editing on close
- (BOOL)windowShouldClose:(id)sender;
{
    return [[self window] makeFirstResponder:nil];
}

#pragma mark Path control delegate

- (NSDragOperation)pathControl:(NSPathControl*)pathControl validateDrop:(id <NSDraggingInfo>)info
{
    NSURL *dragURL = [NSURL URLFromPasteboard:[info draggingPasteboard]];
    BOOL isDir = NO;
    if (dragURL)
        [[NSFileManager defaultManager] fileExistsAtPath:[dragURL path] isDirectory:&isDir];
    return isDir ? NSDragOperationCopy : NSDragOperationNone;
}

-(BOOL)pathControl:(NSPathControl*)pathControl acceptDrop:(id <NSDraggingInfo>)info
{
    NSURL *dragURL = [NSURL URLFromPasteboard:[info draggingPasteboard]];
    if (dragURL) [self updateTeXBinPathWithURL:dragURL];
    return (nil != dragURL);
}

@end
