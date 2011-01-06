//
//  TLMLaunchAgentController.m
//  TeX Live Manager
//
//  Created by Adam R. Maxwell on 10/07/10.
/*
 This software is Copyright (c) 2010-2011
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
@synthesize _allUsersCheckbox;
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

+ (BOOL)agentInstalled:(NSSearchPathDomainMask *)domains;
{
    *domains = 0;
    if ([[NSFileManager defaultManager] fileExistsAtPath:__TLMPlistPath(NSLocalDomainMask)]) {
        *domains |= NSLocalDomainMask;
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:__TLMPlistPath(NSUserDomainMask)]) {
        *domains |= NSUserDomainMask;
    }
    return (*domains != 0);
}

- (id)init { return [self initWithWindowNibName:[self windowNibName]]; }

- (void)dealloc
{
    [_scheduleMatrix release];
    [_allUsersCheckbox release];
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
#define ALL_USERS      ((_status & TLMLaunchAgentAllUsers) != 0)

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
    
    [_allUsersCheckbox setState:(ALL_USERS ? NSOnState : NSOffState)];
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
    if (allUsers) _status |= TLMLaunchAgentAllUsers;
    
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
    if ([[NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL] writeToFile:plistPath atomically:NO])
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

- (IBAction)allUsersAction:(id)sender;
{
    _status |= TLMLaunchAgentChanged;
    switch ([_allUsersCheckbox state]) {
        case NSOnState:
            _status |= TLMLaunchAgentAllUsers;
            break;
        case NSOffState:
            _status &= ~TLMLaunchAgentAllUsers;
            break;
        default:
            break;
    }
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
