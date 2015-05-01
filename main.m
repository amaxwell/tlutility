//
//  main.m
//  TeX Live Utility
//
//  Created by Adam Maxwell on 12/6/08.
/*
 This software is Copyright (c) 2008-2015
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

#import <Cocoa/Cocoa.h>
#import <crt_externs.h>

int main(int argc, char *argv[])
{
    // http://lists.apple.com/archives/cocoa-dev/2011/Jan/msg00169.html
    signal(SIGPIPE, SIG_IGN);
    
    /*
     Workaround for Yosemite environment variable bug, whereby all
     variables are duplicated for processes launched in Finder, and
     setenv/getenv don't modify the ones that are passed to fork/exec
     via (char ** environ). My original workaround was to let Foundation
     pick variables by using NSProcessInfo, but this is more efficient;
     credit to Joe Cheng of RStudio for the idea.
     
     http://tex.stackexchange.com/questions/208181/why-did-my-tex-related-gui-program-stop-working-in-mac-os-x-yosemite/
     
     */
    
    char ***original_env = _NSGetEnviron();
    unsigned int idx, original_count = 0;
    char **env = *original_env;
    
    // count items in the original environment
    while (NULL != *env) {
        original_count++;
        env++;
    }
    
    /*
     Make a copy of the environment, but don't worry about
     NULL-terminating this array; we'll access it by index.
     */
    char **new_env = original_count ? calloc(original_count, sizeof(char *)) : NULL;
    env = *original_env;
    for (idx = 0; idx < original_count; idx++)
        new_env[idx] = strdup(env[idx]);
    
    /*
     This should be only half the length of the original
     environment, as long as we have this bug.
     */
    char **keys_seen = original_count ? calloc(original_count, sizeof(char *)) : NULL;
    unsigned number_of_keys_seen = 0;
    
    // iterate our copy of environ, not the original
    for (idx = 0; idx < original_count; idx++) {
        
        char *key, *value = new_env[idx];
        key = strsep(&value, "=");
        
        if (NULL != key && NULL != value) {
            
            bool duplicate_key = false;
            unsigned sidx;
            /*
             A linear search is okay, since the number of keys is small
             and this is a one-time cost.
             */
            for (sidx = 0; sidx < number_of_keys_seen; sidx++) {
                
                if (strcmp(key, keys_seen[sidx]) == 0) {
                    duplicate_key = true;
                    break;
                }
            }
            
            if (false == duplicate_key) {
                (void) unsetenv(key);
                setenv(key, value, 1);
                keys_seen[number_of_keys_seen] = strdup(key);
                number_of_keys_seen++;
            }
        }
        
        // strdup'ed, and we're not using it again
        free(new_env[idx]);
        
    }
    
    free(new_env);
    
    // free each of these strdup'ed keys
    for (idx = 0; idx < number_of_keys_seen; idx++)
        free(keys_seen[idx]);
    free(keys_seen);
    
    return NSApplicationMain(argc,  (const char **) argv);
}
