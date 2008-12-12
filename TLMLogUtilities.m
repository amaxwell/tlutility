//
//  TLMLogUtilities.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/11/08.
/*
 This software is Copyright (c) 2008
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

#import "TLMLogUtilities.h"
#import <unistd.h>
#import <asl.h>

#define TLM_ASL_SENDER "tlmgr"
#define TLM_ASL_FACILITY NULL

@interface BDSKLogMessage : NSObject
{
    NSDate *date;
    NSString *message;
    NSString *sender;
    pid_t pid;
    NSUInteger hash;
}
- (id)initWithASLMessage:(aslmsg)msg;
@end

static int new_default_asl_query(aslmsg *newQuery, NSTimeInterval absoluteTime)
{
    int err;
    aslmsg query;
    
    query = asl_new(ASL_TYPE_QUERY);
    if (NULL == query)
        perror("asl_new");
    
    const char *level_string = [[NSString stringWithFormat:@"%d", ASL_LEVEL_DEBUG] UTF8String];
    err = asl_set_query(query, ASL_KEY_LEVEL, level_string, ASL_QUERY_OP_LESS_EQUAL | ASL_QUERY_OP_NUMERIC);
    if (err != 0)
        perror("asl_set_query level");
    
    // absolute time difference
    NSUInteger secondsAgo = [NSDate timeIntervalSinceReferenceDate] - absoluteTime;
    const char *time_string = [[NSString stringWithFormat:@"-%lus", secondsAgo] UTF8String];
    err = asl_set_query(query, ASL_KEY_TIME, time_string, ASL_QUERY_OP_GREATER_EQUAL);
    if (err != 0)
        perror("asl_set_query time");
    
    *newQuery = query;
    
    return err;
}

NSString * TLMLogStringSinceTime(NSTimeInterval absoluteTime)
{    
    aslmsg query, msg;
    aslresponse response;
    
    int err;
    
    aslclient client = asl_open(TLM_ASL_SENDER, TLM_ASL_FACILITY, ASL_OPT_NO_DELAY);
    asl_set_filter(client, ASL_FILTER_MASK_UPTO(ASL_LEVEL_DEBUG));
    
    NSMutableSet *messages = [NSMutableSet set];
    NSString *stderrString = nil;
        
    err = new_default_asl_query(&query, absoluteTime);
    
    BDSKLogMessage *logMessage;

    // search for anything with our sender name as substring; captures some system logging
    err = asl_set_query(query, ASL_KEY_MSG, TLM_ASL_SENDER, ASL_QUERY_OP_CASEFOLD | ASL_QUERY_OP_SUBSTRING | ASL_QUERY_OP_EQUAL);
    if (err != 0)
        fprintf(stderr, "asl_set_query message failed with error %d (%s)\n", err, strerror(err));
    
    response = asl_search(client, query);
    
    
    while (NULL != (msg = aslresponse_next(response))) {
        logMessage = [[BDSKLogMessage alloc] initWithASLMessage:msg];
        if (logMessage)
            [messages addObject:logMessage];
        [logMessage release];
    }
    
    aslresponse_free(response);
    asl_free(query);

    err = new_default_asl_query(&query, absoluteTime);
    
    // now search for messages that we've logged directly
    err = asl_set_query(query, ASL_KEY_SENDER, TLM_ASL_SENDER, ASL_QUERY_OP_EQUAL);
    if (err != 0)
        fprintf(stderr, "asl_set_query sender failed with error %d (%s)\n", err, strerror(err));
    
    response = asl_search(client, query);
    
    while (NULL != (msg = aslresponse_next(response))) {
        logMessage = [[BDSKLogMessage alloc] initWithASLMessage:msg];
        if (logMessage)
            [messages addObject:logMessage];
        [logMessage release];
    }
    
    aslresponse_free(response);
    asl_free(query);
    asl_close(client);
    
    // sort by date so we have a coherent list...
    NSArray *sortedMessages = [[messages allObjects] sortedArrayUsingSelector:@selector(compare:)];
    
    // sends -description to each object
    stderrString = [sortedMessages componentsJoinedByString:@"\n"];

    
    return stderrString;
}

#pragma mark -

@implementation BDSKLogMessage

- (id)initWithASLMessage:(aslmsg)msg
{
    self = [super init];
    if (self) {
        const char *val;
        
        val = asl_get(msg, ASL_KEY_TIME);
        if (NULL == val) val = "0";
        time_t theTime = strtol(val, NULL, 0);
        date = [[NSDate dateWithTimeIntervalSince1970:theTime] copy];
        hash = [date hash];
        
        val = asl_get(msg, ASL_KEY_SENDER);
        if (NULL == val) val = "Unknown";
        sender = [[NSString alloc] initWithCString:val encoding:NSUTF8StringEncoding];
        
        val = asl_get(msg, ASL_KEY_PID);
        if (NULL == val) val = "-1";
        pid = strtol(val, NULL, 0);
        
        val = asl_get(msg, ASL_KEY_MSG);
        if (NULL == val) val = "Empty log message";
        message = [[NSString alloc] initWithCString:val encoding:NSUTF8StringEncoding];
    }
    return self;
}

- (void)dealloc
{
    [date release];
    [sender release];
    [message release];
    [super dealloc];
}

- (NSUInteger)hash { return hash; }
- (NSDate *)date { return date; }
- (NSString *)message { return message; }
- (NSString *)sender { return sender; }
- (int)pid { return pid; }

- (BOOL)isEqual:(id)other
{
    if ([other isKindOfClass:[self class]] == NO)
        return NO;
    if ([other pid] != pid)
        return NO;
    if ([[other message] isEqualToString:message] == NO)
        return NO;
    if ([(NSString *)[other sender] isEqualToString:sender] == NO)
        return NO;
    if ([[other date] compare:date] != NSOrderedSame)
        return NO;
    return YES;
}
- (NSString *)description { return [NSString stringWithFormat:@"%@ %@[%d]\t%@", date, sender, pid, message]; }
- (NSComparisonResult)compare:(BDSKLogMessage *)other { return [[self date] compare:[other date]]; }

@end
