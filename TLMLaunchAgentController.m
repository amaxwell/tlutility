//
//  TLMLaunchAgentController.m
//  TeX Live Utility
//
//  Created by Adam R. Maxwell on 10/07/10.
/*
 This software is Copyright (c) 2010-2013
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

#import "TLMLaunchAgentController.h"
#import "TLMLogServer.h"
#import "TLMTask.h"
#import "TLMAuthorizedOperation.h"
#import "TLMReadWriteOperationQueue.h"
#import "TLMEnvironment.h"

enum {
    TLMScheduleMatrixNever  = 0,
    TLMScheduleMatrixWeekly = 1,
    TLMScheduleMatrixDaily  = 2
};

@interface TLMLaunchAgentController ()
@property (nonatomic, copy) NSString *propertyListPath;
@end

@implementation TLMLaunchAgentController

@synthesize _scheduleMatrix;
@synthesize _dayField;
@synthesize _datePicker;
@synthesize propertyListPath =_propertyListPath;

#define PLIST_NAME @"com.googlecode.mactlmgr.update_check"

static NSString *__TLMPlistPath(NSSearchPathDomainMask domain)
{
    NSString *baseDir = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, domain, YES) lastObject];
    return [[[baseDir stringByAppendingPathComponent:@"LaunchAgents"] stringByAppendingPathComponent:PLIST_NAME] stringByAppendingPathExtension:@"plist"];
}

static NSDictionary * __TLMGetPlist(BOOL *isInstalled, BOOL *allUsers, NSString **outPath)
{
    NSString *plistPath;
    if ([[NSFileManager defaultManager] fileExistsAtPath:__TLMPlistPath(NSLocalDomainMask)]) {
        if (isInstalled) *isInstalled = YES;
        if (allUsers) *allUsers = YES;
        plistPath = __TLMPlistPath(NSLocalDomainMask);
    }
    else if ([[NSFileManager defaultManager] fileExistsAtPath:__TLMPlistPath(NSUserDomainMask)]) {
        if (isInstalled) *isInstalled = YES;
        if (allUsers) *allUsers = NO;
        plistPath = __TLMPlistPath(NSUserDomainMask);
    }
    else {
        if (isInstalled) *isInstalled = NO;
        if (allUsers) *allUsers = NO;
        plistPath = [[NSBundle mainBundle] pathForResource:PLIST_NAME ofType:@"plist"];
    }
    
    if (outPath) *outPath = plistPath;
    return [NSDictionary dictionaryWithContentsOfFile:plistPath];
}

static NSString * __TLMGetTemporaryDirectory()
{
    static NSString *tmpDir = nil;
    if (nil == tmpDir)
        tmpDir = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"TLMLaunchAgentController"] copy];
    return tmpDir;
}

+ (void)_removeTemporaryDirectory:(NSNotification *)aNote
{
    BOOL isDir;
    if ([[NSFileManager defaultManager] fileExistsAtPath:__TLMGetTemporaryDirectory() isDirectory:&isDir] && isDir)
        [[NSFileManager defaultManager] removeItemAtPath:__TLMGetTemporaryDirectory() error:NULL];
}

+ (void)initialize
{
    if (self == [TLMLaunchAgentController class]) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_removeTemporaryDirectory:)
                                                     name:NSApplicationWillTerminateNotification
                                                   object:nil];
    }
}

+ (BOOL)_agentInstalled:(NSSearchPathDomainMask *)outDomains;
{
    NSSearchPathDomainMask domains = 0;
    if ([[NSFileManager defaultManager] fileExistsAtPath:__TLMPlistPath(NSLocalDomainMask)]) {
        domains |= NSLocalDomainMask;
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:__TLMPlistPath(NSUserDomainMask)]) {
        domains |= NSUserDomainMask;
    }
    if (outDomains) *outDomains = domains;
    return (domains != 0);
}

+ (BOOL)agentInstalled { return [self _agentInstalled:NULL]; }

+ (BOOL)migrateLocalToUserIfNeeded;
{
    NSSearchPathDomainMask domains;
    BOOL ret = NO;
    if ([self _agentInstalled:&domains] && (domains & NSLocalDomainMask)) {
        
        NSMutableArray *options = [NSMutableArray array];
        TLMOperation *copyOperation = nil;
            
        if ((domains & NSUserDomainMask) == 0) {
            // have to copy local to user before removing the local one

            [options addObject:@"--install"];
            
            [options addObject:@"--plist"];
            [options addObject:__TLMPlistPath(NSLocalDomainMask)];
            
            [options addObject:@"--script"];
            [options addObject:[[NSBundle mainBundle] pathForResource:@"update_check" ofType:@"py"]];
        
            copyOperation = [[TLMOperation alloc] initWithCommand:[[NSBundle mainBundle] pathForAuxiliaryExecutable:@"agent_installer.py"] options:options];
        }
        
        // always remove the local agent
        [options removeAllObjects];
        [options addObject:[[NSBundle mainBundle] pathForAuxiliaryExecutable:@"uninstall_local_agent.sh"]];
        TLMAuthorizedOperation *removeOperation = [[TLMAuthorizedOperation alloc] initWithAuthorizedCommand:@"/bin/sh" options:options];
        if (copyOperation) {
            [removeOperation addDependency:copyOperation];
            [[TLMReadWriteOperationQueue defaultQueue] addOperation:copyOperation];
        }
        [[TLMReadWriteOperationQueue defaultQueue] addOperation:removeOperation];
        
        [copyOperation release];
        [removeOperation release];
        ret = YES;
    }
    return ret;
}

CGFloat __TLMScriptVersionAtPath(NSString *absolutePath)
{
    NSString *parent = [absolutePath stringByDeletingLastPathComponent];
    NSString *script = [NSString stringWithFormat:@"import sys; sys.path.append(\"%@\"); import update_check as uc; sys.stdout.write(str(uc.VERSION))", parent];
    TLMTask *task = [[TLMTask new] autorelease];
    [task setLaunchPath:@"/usr/bin/python"];
    [task setArguments:[NSArray arrayWithObjects:@"-c", script, nil]];
    [task launch];
    [task waitUntilExit];
    CGFloat version = 0;
    if ([task terminationStatus] == 0) {
        version = [[task outputString] floatValue];
    }
    else {
        TLMLog(__func__, @"Failed to get version of script at %@", absolutePath);
    }
    return version;
}

+ (BOOL)scriptNeedsUpdate;
{
    BOOL needsUpdate = NO;
    if ([self agentInstalled]) {
        
        NSString *internalScript = [[NSBundle mainBundle] pathForResource:@"update_check" ofType:@"py"];
        CGFloat internalVersion = __TLMScriptVersionAtPath(internalScript);        
        
        NSArray *applicationSupportPaths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
        NSString *appSupportPath = [[applicationSupportPaths lastObject] stringByAppendingPathComponent:@"TeX Live Utility"];
        appSupportPath = [appSupportPath stringByAppendingPathComponent:@"update_check.py"];
        CGFloat version = __TLMScriptVersionAtPath(appSupportPath);
        if (version < internalVersion) {
            TLMLog(__func__, @"Update checker v%1.1f at %@ needs to be updated to v%1.1f", version, [appSupportPath stringByAbbreviatingWithTildeInPath], internalVersion);
            needsUpdate = YES;
        }
    }
    return needsUpdate;
}

- (id)init { return [self initWithWindowNibName:[self windowNibName]]; }

- (void)dealloc
{
    [_scheduleMatrix release];
    [_dayField release];
    [_datePicker release];
    [_propertyListPath release];
    [_gregorianCalendar release];
    [super dealloc];
}

- (NSString *)windowNibName { return @"LaunchAgentSheet"; }

#define AGENT_DISABLED ((_status & TLMLaunchAgentEnabled) == 0)
#define AGENT_ENABLED  ((_status & TLMLaunchAgentEnabled) != 0)
#define CHECK_WEEKLY   ((_status & TLMLaunchAgentDaily) == 0)

- (void)_updateUI
{
    if (AGENT_DISABLED) {
        [_scheduleMatrix selectCellWithTag:TLMScheduleMatrixNever];
        [_dayField setEnabled:NO];
        [_datePicker setEnabled:NO];
    }
    else {
        
        [_datePicker setEnabled:YES];

        if (CHECK_WEEKLY) {
            [_scheduleMatrix selectCellWithTag:TLMScheduleMatrixWeekly];
            [_dayField setEnabled:YES];
        }
        else {
            [_scheduleMatrix selectCellWithTag:TLMScheduleMatrixDaily];
            [_dayField setEnabled:NO];
        }
        
    }    
}

- (void)awakeFromNib
{
    if (nil == _gregorianCalendar) {
        _gregorianCalendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
        [_gregorianCalendar setTimeZone:[NSTimeZone localTimeZone]];
    }
    [[_dayField formatter] setTimeZone:[NSTimeZone localTimeZone]];
    
    BOOL isInstalled, allUsers;
    NSString *plistPath;
    NSDictionary *plist = __TLMGetPlist(&isInstalled, &allUsers, &plistPath);
    // user could have disabled with launchctl, but that's not my problem (yet)
    if (isInstalled) _status |= TLMLaunchAgentEnabled;
    
    // need to set from a full date, or the day of week ends up being off by one
    NSDateComponents *comps = [_gregorianCalendar components:NSWeekdayCalendarUnit|NSYearCalendarUnit|NSMonthCalendarUnit|NSDayCalendarUnit fromDate:[NSDate date]];
    
    NSDictionary *intervalDict = [plist objectForKey:@"StartCalendarInterval"];
    [comps setHour:[[intervalDict objectForKey:@"Hour"] integerValue]];
    [comps setMinute:[[intervalDict objectForKey:@"Minute"] integerValue]];

    // only shows hour and minute
    [_datePicker setDateValue:[_gregorianCalendar dateFromComponents:comps]];
    [_dayField setObjectValue:[_gregorianCalendar dateFromComponents:comps]];

    if ([[plist objectForKey:@"StartCalendarInterval"] objectForKey:@"Weekday"]) {
        // 0 and 7 are Sunday, according to launchd.plist(5)
        NSInteger launchdWeekday = [[intervalDict objectForKey:@"Weekday"] integerValue];
        // NSDateComponents thinks that 1 is Sunday, in the Gregorian calendar
        NSInteger nsdcWeekday = launchdWeekday + 1;
        
        /*
         Compute the offset manually, since NSCalendar returns a crap date if NSDateComponents is specified
         with year/month/weekday.  I could file a bug report with Apple, but it'll either be "works as designed"
         or ignored until NSCalendar is deprecated in favor of something else...
         */
        NSInteger currentWeekday = [comps weekday];
        NSDateComponents *offsetComponents = [[NSDateComponents new] autorelease];
        [offsetComponents setWeekday:(nsdcWeekday - currentWeekday)];
        NSDate *weekdayDate = [_gregorianCalendar dateByAddingComponents:offsetComponents toDate:[NSDate date] options:0];
        [_dayField setObjectValue:weekdayDate];
        
        _status &= ~TLMLaunchAgentDaily;
    }
    else {
        _status |= TLMLaunchAgentDaily;
    }
    
    [_datePicker sizeToFit];
    [self setPropertyListPath:plistPath];
    [self _updateUI];
}

- (void)_savePropertyList
{
    if ([[NSFileManager defaultManager] fileExistsAtPath:__TLMGetTemporaryDirectory()] == NO)
        [[NSFileManager defaultManager] createDirectoryAtPath:__TLMGetTemporaryDirectory() withIntermediateDirectories:YES attributes:nil error:NULL];
    
    // write to a temporary file, and then set that as the property list path
    NSString *plistPath = [[__TLMGetTemporaryDirectory() stringByAppendingPathComponent:PLIST_NAME] stringByAppendingPathExtension:@"plist"];
    NSMutableDictionary *plist = [NSMutableDictionary dictionary];
    [plist addEntriesFromDictionary:__TLMGetPlist(NULL, NULL, NULL)];
    
    NSDateComponents *comps = [_gregorianCalendar components:NSHourCalendarUnit|NSMinuteCalendarUnit fromDate:[_datePicker dateValue]];
    NSMutableDictionary *interval = [NSMutableDictionary dictionary];
    [interval setObject:[NSNumber numberWithInteger:[comps hour]] forKey:@"Hour"];
    [interval setObject:[NSNumber numberWithInteger:[comps minute]] forKey:@"Minute"];
    
    if (CHECK_WEEKLY) {
        comps = [_gregorianCalendar components:NSWeekdayCalendarUnit fromDate:[_dayField objectValue]];
        NSInteger launchdWeekday = [comps weekday] - 1;
        [interval setObject:[NSNumber numberWithInteger:launchdWeekday] forKey:@"Weekday"];
    }
    
    [plist setObject:interval forKey:@"StartCalendarInterval"];
    if ([[NSPropertyListSerialization dataFromPropertyList:plist format:NSPropertyListXMLFormat_v1_0 errorDescription:NULL] writeToFile:plistPath atomically:NO])
        [self setPropertyListPath:plistPath];    
}

- (IBAction)enableAction:(id)sender;
{
    _status |= TLMLaunchAgentChanged;
    switch ([[_scheduleMatrix selectedCell] tag]) {
        case TLMScheduleMatrixNever:
            _status &= ~TLMLaunchAgentEnabled;
            break;
        case TLMScheduleMatrixWeekly:
            _status &= ~TLMLaunchAgentDaily;
            _status |= TLMLaunchAgentEnabled;
            break;
        case TLMScheduleMatrixDaily:
            _status |= TLMLaunchAgentDaily;
            _status |= TLMLaunchAgentEnabled;
            break;
        default:
            break;
    }
    
    if (AGENT_ENABLED)
        [self _savePropertyList];

    [self _updateUI];
}

- (IBAction)changeDay:(id)sender;
{
    _status |= TLMLaunchAgentChanged;
    [self _savePropertyList];
}

- (IBAction)changeTime:(id)sender;
{
    _status |= TLMLaunchAgentChanged;
    [self _savePropertyList];
}

- (IBAction)cancel:(id)sender;
{
    [NSApp endSheet:[self window] returnCode:TLMLaunchAgentCancelled];
}

- (IBAction)accept:(id)sender;
{
    if ([[self window] makeFirstResponder:nil])
        [NSApp endSheet:[self window] returnCode:_status];
    else
        NSBeep();
}

@end
