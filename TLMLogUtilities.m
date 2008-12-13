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
#import "TLMLogMessage.h"
#import <unistd.h>
#import <asl.h>

#define TLM_ASL_SENDER "com.googlecode.mactlmgr"        /* common to all mactlmgr programs */
#define TLM_ASL_FACILITY "com.googlecode.mactlmgr.gui"  /* specific to a given binary      */

NSArray * TLMLogMessagesSinceDate(NSDate *date)
{
    aslmsg query, msg;
    aslresponse response;
    
    int err;
    
    aslclient client = asl_open(TLM_ASL_SENDER, TLM_ASL_FACILITY, ASL_OPT_NO_DELAY);
    
    NSMutableArray *messages = [NSMutableArray array];
    
    query = asl_new(ASL_TYPE_QUERY);
    if (NULL == query)
        perror("asl_new");
    
    // round time up to ensure that we don't lose anything
    NSUInteger secondsAgo = [NSDate timeIntervalSinceReferenceDate] - [date timeIntervalSinceReferenceDate] + 1;
    const char *time_string = [[NSString stringWithFormat:@"-%lus", secondsAgo] UTF8String];
    err = asl_set_query(query, ASL_KEY_TIME, time_string, ASL_QUERY_OP_GREATER_EQUAL);
    if (err != 0)
        fprintf(stderr, "asl_set_query ASL_KEY_TIME failed with error %d (%s)\n", err, strerror(err));
        
    // now search for sender; all binaries use this prefix
    err = asl_set_query(query, ASL_KEY_SENDER, TLM_ASL_SENDER, ASL_QUERY_OP_EQUAL | ASL_QUERY_OP_PREFIX);
    if (err != 0) 
        fprintf(stderr, "asl_set_query ASL_KEY_SENDER failed with error %d (%s)\n", err, strerror(err));

    // now search for <= notice
    err = asl_set_query(query, ASL_KEY_LEVEL, ASL_STRING_NOTICE, ASL_QUERY_OP_LESS_EQUAL);
    if (err != 0) 
        fprintf(stderr, "asl_set_query ASL_LEVEL_NOTICE failed with error %d (%s)\n", err, strerror(err));
  
    // now search for >= error
    err = asl_set_query(query, ASL_KEY_LEVEL, ASL_STRING_ERR, ASL_QUERY_OP_GREATER_EQUAL);
    if (err != 0) 
        fprintf(stderr, "asl_set_query ASL_LEVEL_ERR failed with error %d (%s)\n", err, strerror(err));
    
    response = asl_search(client, query);
    TLMLogMessage *logMessage;
    
    while (NULL != (msg = aslresponse_next(response))) {
        logMessage = [[TLMLogMessage alloc] initWithASLMessage:msg];
        if (logMessage)
            [messages addObject:logMessage];
        [logMessage release];
    }
    
    aslresponse_free(response);
    asl_free(query);
    asl_close(client);
    
    return messages;
}

NSString * TLMLogStringSinceTime(NSTimeInterval absoluteTime)
{    
    NSArray *sortedMessages = TLMLogMessagesSinceDate([NSDate dateWithTimeIntervalSinceReferenceDate:absoluteTime]);
    
    // sends -description to each object    
    return [sortedMessages componentsJoinedByString:@"\n"];
}
