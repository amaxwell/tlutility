//
//  NSMenu_TLMExtensions.m
//  Bibdesk
//
//  Created by Adam Maxwell on 07/09/06.
/*
 This software is Copyright (c) 2006-2016
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

#import "NSMenu_TLMExtensions.h"

static NSString *TLMMenuTargetURL = @"TLMMenuTargetURL";
static NSString *TLMMenuApplicationURL = @"TLMMenuApplicationURL";

@interface TLMOpenWithMenuController : NSObject <NSMenuDelegate>
+ (id)sharedInstance;
- (void)openURLWithApplication:(id)sender;
@end

@interface NSMenu (TLMPrivate)
- (void)replaceAllItemsWithApplicationsForURL:(NSURL *)aURL;
@end

@implementation NSMenu (TLMExtensions)

- (NSMenuItem *)insertItemWithTitle:(NSString *)itemTitle submenu:(NSMenu *)submenu atIndex:(NSUInteger)idx;
{
    NSMenuItem *item = [[NSMenuItem allocWithZone:[self zone]] initWithTitle:itemTitle action:NULL keyEquivalent:@""];
    [item setSubmenu:submenu];
    [self insertItem:item atIndex:idx];
    [item release];
    return item;
}

- (NSMenuItem *)insertOpenWithMenuForURL:(NSURL *)theURL atIndex:(NSUInteger)idx;
{
    NSString *itemTitle = NSLocalizedString(@"Open With", @"menu title");
    if (theURL == nil) {
        // just return an empty item
        return [self insertItemWithTitle:itemTitle action:NULL keyEquivalent:@"" atIndex:idx];
    }
    
    NSMenu *submenu;
    NSMenuItem *item;
    NSDictionary *representedObject;
    TLMOpenWithMenuController *controller = [TLMOpenWithMenuController sharedInstance];
    
    submenu = [[[NSMenu allocWithZone:[self zone]] initWithTitle:@""] autorelease];
    [submenu setDelegate:controller];
    
    // add the choose... item, the other items are inserted lazily by TLMOpenWithMenuController
    item = [submenu addItemWithTitle:[NSString stringWithFormat:@"%@%C", NSLocalizedString(@"Choose", @"Menu item title"), TLM_ELLIPSIS] action:@selector(openURLWithApplication:) keyEquivalent:@""];
    [item setTarget:controller];
    representedObject = [[NSDictionary alloc] initWithObjectsAndKeys:theURL, TLMMenuTargetURL, nil];
    [item setRepresentedObject:representedObject];
    [representedObject release];
    
    return [self insertItemWithTitle:itemTitle submenu:submenu atIndex:idx];
}

@end


@implementation NSMenu (TLMPrivate)

- (void)replaceAllItemsWithApplicationsForURL:(NSURL *)aURL;
{    
    // assumption: last item is "Choose..." item; note that this item may be the only thing retaining aURL
    NSParameterAssert([self numberOfItems] > 0);
    while([self numberOfItems] > 1)
        [self removeItemAtIndex:0];
    
    NSZone *menuZone = [NSMenu menuZone];
    NSMenuItem *item;
    
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    NSURL *defaultEditorURL;
    if (noErr == LSGetApplicationForURL((CFURLRef)aURL, kLSRolesEditor|kLSRolesViewer, NULL, (CFURLRef *)&defaultEditorURL))
        defaultEditorURL = [defaultEditorURL autorelease];
    else
        defaultEditorURL = nil;
    
    NSArray *appURLs = [(id)LSCopyApplicationURLsForURL((CFURLRef)aURL, kLSRolesEditor|kLSRolesViewer) autorelease];
    
    NSURL *appURL;
    NSString *appName;
    NSString *menuTitle;
    NSString *version;
    NSDictionary *representedObject;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *appNames = [NSMutableArray array];
    NSMutableArray *titles = [NSMutableArray array];
    NSMutableIndexSet *versionedIndexes = [NSMutableIndexSet indexSet];
    NSUInteger idx, i, count = [appURLs count];
    
    for (i = 0; i < count; i++) {
        appURL = [appURLs objectAtIndex:i];
        appName = [fm displayNameAtPath:[appURL path]];
        menuTitle = appName;
        idx = [appNames indexOfObject:appName];
        
        if (idx != NSNotFound) {
            [versionedIndexes addIndex:i];
            if ((version = [[[NSBundle bundleWithPath:[appURL path]] infoDictionary] objectForKey:@"CFBundleShortVersionString"]))
                menuTitle = [appName stringByAppendingFormat:@" (%@)", version];
            if ([versionedIndexes containsIndex:idx] == NO) {
                [versionedIndexes addIndex:idx];
                if ((version = [[[NSBundle bundleWithPath:[[appURLs objectAtIndex:idx] path]] infoDictionary] objectForKey:@"CFBundleShortVersionString"])) {
                    [titles replaceObjectAtIndex:idx withObject:[[appNames objectAtIndex:idx] stringByAppendingFormat:@" (%@)", version]];
                }
            }
        }
        [titles addObject:menuTitle];
        [appNames addObject:appName];
    }
    
    for (i = 0; i < count; i++) {
        appURL = [appURLs objectAtIndex:i];
        menuTitle = [titles objectAtIndex:i];
        
        // mark the default app, if we have one
        if([defaultEditorURL isEqual:appURL])
            menuTitle = [menuTitle stringByAppendingString:NSLocalizedString(@" (Default)", @"Menu item title, Need a single leading space")];
        
        // TLMOpenWithMenuController singleton implements openURLWithApplication:
        item = [[NSMenuItem allocWithZone:menuZone] initWithTitle:menuTitle action:@selector(openURLWithApplication:) keyEquivalent:@""];        
        [item setTarget:[TLMOpenWithMenuController sharedInstance]];
        representedObject = [[NSDictionary alloc] initWithObjectsAndKeys:aURL, TLMMenuTargetURL, appURL, TLMMenuApplicationURL, nil];
        [item setRepresentedObject:representedObject];
        
        // use NSWorkspace to get an image; using [NSImage imageForURL:] doesn't work for some reason
        [item setImageAndSize:[workspace iconForFile:[appURL path]]];
        [representedObject release];
        if([defaultEditorURL isEqual:appURL]){
            [self insertItem:item atIndex:0];
            [self insertItem:[NSMenuItem separatorItem] atIndex:1];
        }else{
            [self insertItem:item atIndex:[self numberOfItems] - 1];
        }
        [item release];
    }
    
    if ([self numberOfItems] > 1 && [[self itemAtIndex:[self numberOfItems] - 2] isSeparatorItem] == NO)
        [self insertItem:[NSMenuItem separatorItem] atIndex:[self numberOfItems] - 1];
}

@end

#pragma mark -

/* Private singleton to act as target for the "Open With..." menu item, or run a modal panel to choose a different application.
*/

@implementation TLMOpenWithMenuController

static id sharedOpenWithController = nil;

+ (id)sharedInstance
{
    if(nil == sharedOpenWithController)
        sharedOpenWithController = [[self alloc] init];
    return sharedOpenWithController;
}

- (id)copyWithZone:(NSZone *)zone{
    return [sharedOpenWithController retain];
}

- (void)encodeWithCoder:(NSCoder *)coder{}

- (id)initWithCoder:(NSCoder *)decoder{
    [self release];
    self = [sharedOpenWithController retain];
    return self;
}

- (void)chooseApplicationToOpenURL:(NSURL *)aURL;
{
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    [openPanel setCanChooseDirectories:NO];
    [openPanel setAllowsMultipleSelection:NO];
    [openPanel setPrompt:NSLocalizedString(@"Choose Viewer", @"Prompt for Choose panel")];
    [openPanel setAllowedFileTypes:[NSArray arrayWithObjects:@"app", nil]];
    
    if(NSFileHandlingPanelOKButton == [openPanel runModal])
        [[NSWorkspace sharedWorkspace] openFile:[aURL path] withApplication:[[openPanel URL] path]];
}

// action for opening a file with a specific application
- (void)openURLWithApplication:(id)sender;
{
    NSURL *applicationURL = [[sender representedObject] valueForKey:TLMMenuApplicationURL];
    NSURL *targetURL = [[sender representedObject] valueForKey:TLMMenuTargetURL];
    
    if(nil == applicationURL)
        [self chooseApplicationToOpenURL:targetURL];
    else if([[NSWorkspace sharedWorkspace] openFile:[targetURL path] withApplication:[applicationURL path]] == NO)
        NSBeep();
}

- (void)menuNeedsUpdate:(NSMenu *)menu{
    NSParameterAssert([menu numberOfItems] > 0);
    NSURL *theURL = [[[[menu itemArray] lastObject] representedObject] valueForKey:TLMMenuTargetURL];
    NSParameterAssert(theURL);
    if(theURL != nil)
        [menu replaceAllItemsWithApplicationsForURL:theURL];
}

// this is needed to prevent the menu from being updated just to look for key equivalents, 
// which would lead to considerable slowdown of key events
- (BOOL)menuHasKeyEquivalent:(NSMenu *)menu forEvent:(NSEvent *)event target:(id *)target action:(SEL *)action{
    return NO;
}
 
- (BOOL)validateMenuItem:(NSMenuItem*)menuItem{
    if ([menuItem action] == @selector(openURLWithApplication:)) {
        NSURL *theURL = [[menuItem representedObject] valueForKey:TLMMenuTargetURL];
        return (theURL == nil ? NO : YES);
    }
    return YES;
}

@end

@implementation NSMenuItem (TLMImageExtensions)

- (void)setImageAndSize:(NSImage *)image;
{
    NSLayoutManager *lm = [NSLayoutManager new];
    [lm setTypesetterBehavior:NSTypesetterLatestBehavior];
    CGFloat lineHeight = [lm defaultLineHeightForFont:[NSFont menuFontOfSize:0]];
    [lm release];
    NSSize dstSize = NSMakeSize(lineHeight, lineHeight);

    NSSize srcSize = [image size];
    if (NSEqualSizes(srcSize, dstSize)) {
        [self setImage:image];
    } else {
        NSImage *newImage = [[NSImage alloc] initWithSize:dstSize];
        [newImage lockFocus];
        [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
        [image drawInRect:NSMakeRect(0, 0, dstSize.width, dstSize.height) fromRect:NSZeroRect operation:NSCompositeCopy fraction:1.0];
        [newImage unlockFocus];
        [self setImage:newImage];
        [newImage release];
    }
}
        
@end
