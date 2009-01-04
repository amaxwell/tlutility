//
//  TLMPreferenceController.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/08/08.
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

#import "TLMPreferenceController.h"
#import "TLMURLFormatter.h"
#import "TLMAppController.h"
#import "TLMLogServer.h"

NSString * const TLMServerURLPreferenceKey = @"TLMServerURLPreferenceKey";     /* http://mirror.ctan.org      */
NSString * const TLMTexBinPathPreferenceKey = @"TLMTexBinPathPreferenceKey";   /* /usr/texbin                 */
NSString * const TLMServerPathPreferenceKey = @"TLMServerPathPreferenceKey";   /* systems/texlive/tlnet/2008  */
NSString * const TLMUseRootHomePreferenceKey = @"TLMUseRootHomePreferenceKey"; /* YES                         */
NSString * const TLMInfraPathPreferenceKey = @"TLMInfraPathPreferenceKey";     /* update-tlmgr-latest.sh      */
NSString * const TLMUseSyslogPreferenceKey = @"TLMUseSyslogPreferenceKey";     /* NO                          */

#define TLMGR_CMD @"tlmgr"

@implementation TLMPreferenceController

@synthesize _texbinPathControl;
@synthesize _serverComboBox;
@synthesize _rootHomeCheckBox;
@synthesize _useSyslogCheckBox;

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
        NSString *plistPath = [[NSBundle mainBundle] pathForResource:@"DefaultMirrors" ofType:@"plist"];
        if (plistPath)
            [servers addObjectsFromArray:[NSArray arrayWithContentsOfFile:plistPath]];
        _servers = [servers copy];
    }
    return self;
}

- (void)dealloc
{
    [_texbinPathControl release];
    [_serverComboBox release];
    [_rootHomeCheckBox release];
    [_useSyslogCheckBox release];
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
    
    [_rootHomeCheckBox setState:[defaults boolForKey:TLMUseRootHomePreferenceKey]];
    [_useSyslogCheckBox setState:[defaults boolForKey:TLMUseSyslogPreferenceKey]];
}

- (IBAction)toggleUseRootHome:(id)sender;
{
    [[NSUserDefaults standardUserDefaults] setBool:([sender state] == NSOnState) forKey:TLMUseRootHomePreferenceKey];
}

- (IBAction)toggleUseSyslog:(id)sender;
{
    [[NSUserDefaults standardUserDefaults] setBool:([sender state] == NSOnState) forKey:TLMUseSyslogPreferenceKey];
}

- (void)updateTeXBinPathWithURL:(NSURL *)aURL
{
    [_texbinPathControl setURL:aURL];
    [[NSUserDefaults standardUserDefaults] setObject:[aURL path] forKey:TLMTexBinPathPreferenceKey];
    
    // update environment, or tlmgr will be non-functional
    [TLMAppController updatePathEnvironment];
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
    [openPanel setPrompt:NSLocalizedString(@"Choose", @"button title in open panel (must be short)")];
    [openPanel beginSheetForDirectory:@"/usr" file:nil 
                       modalForWindow:[self window] modalDelegate:self 
                       didEndSelector:@selector(openPanelDidEnd:returnCode:contextInfo:) contextInfo:NULL];
}

#define URL_CONNECTION_TIMEOUT 30

- (BOOL)_canConnectToDefaultServer
{
    TLMLog(__func__, @"Checking for a connection to %@%C", [[self defaultServerURL] absoluteString], 0x2026);
    
    // see if we have a network connection
    CFNetDiagnosticRef diagnostic = CFNetDiagnosticCreateWithURL(NULL, (CFURLRef)[self defaultServerURL]);
    [(id)diagnostic autorelease];
    if (kCFNetDiagnosticConnectionDown == CFNetDiagnosticCopyNetworkStatusPassively(diagnostic, NULL)) {
        TLMLog(__func__, @"net diagnostic reports the connection is down");
        return NO;
    }
    
    NSURLRequest *request = [NSURLRequest requestWithURL:[self defaultServerURL] 
                                             cachePolicy:NSURLRequestReloadIgnoringCacheData 
                                         timeoutInterval:URL_CONNECTION_TIMEOUT];
    NSHTTPURLResponse *response;
    NSError *error = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    
    // response will not be an NSHTTPURLResponse for ftp: hosts, but data is empty
    if ([response respondsToSelector:@selector(statusCode)] && [response statusCode] != 200) {
        TLMLog(__func__, @"http response from %@ was %d", [self defaultServerURL], [response statusCode]);
        data = nil;
    }
    else if ([data length] == 0) {
        TLMLog(__func__, @"no data from %@", [self defaultServerURL]);
    }
    
    // this gets screwed up by "http://mirror.ctan.orgs/" getting redirected to opendns.com, but
    // even if we can check for a 302, that's the same response that mirror.ctan.org gives...
    
    return ([data length] != 0);
}

- (IBAction)changeServerURL:(id)sender
{
    // save the old value, then set new value in prefs, so -defaultServerURL can be used in _canConnectToDefaultServer
    NSString *oldValue = [[[[NSUserDefaults standardUserDefaults] objectForKey:TLMServerURLPreferenceKey] copy] autorelease];
    NSString *serverURLString = [[sender cell] stringValue];
    [[NSUserDefaults standardUserDefaults] setObject:serverURLString forKey:TLMServerURLPreferenceKey];
    
    /*
     It's not immediately obvious how to compose the URL, since each mirror has a different path.
     Do a quick check if this isn't one of the URLs from the bundled plist.
     */
    if ([_servers containsObject:serverURLString] == NO && [self _canConnectToDefaultServer] == NO) {
        
        NSAlert *alert = [[NSAlert new] autorelease];
        [alert setMessageText:[NSString stringWithFormat:NSLocalizedString(@"Unable to connect to server after %d seconds.", @"alert title"), (int)URL_CONNECTION_TIMEOUT]];
        [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Either a network connection could not be established, or the directory \"%@\" does not exist at the specified CTAN root URL.  Would you like to keep this URL, or revert to the previous one?", @"alert message text"), [[NSUserDefaults standardUserDefaults] objectForKey:TLMServerPathPreferenceKey]]];
        [alert addButtonWithTitle:NSLocalizedString(@"Revert", @"")];
        [alert addButtonWithTitle:NSLocalizedString(@"Keep", @"")];
        
        // don't run as a sheet, since this may need to block a window close
        NSInteger rv = [alert runModal];
        
        if (NSAlertFirstButtonReturn == rv) {
            [[NSUserDefaults standardUserDefaults] setObject:oldValue forKey:TLMServerURLPreferenceKey];
            [[sender cell] setStringValue:oldValue];
        }
    }
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
    NSAlert *alert = [NSAlert alertWithMessageText:error 
                                     defaultButton:NSLocalizedString(@"Edit", @"button title") 
                                   alternateButton:NSLocalizedString(@"Ignore", @"button title") 
                                       otherButton:nil 
                         informativeTextWithFormat:NSLocalizedString(@"Choose \"Edit\" to fix the value, or \"Ignore\" to use the invalid URL.", @"alert message text, Edit and Ignore are button titles")];
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
