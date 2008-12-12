/*
 *  tlmgr_cwrapper.c
 *  TeX Live Manager
 *
 *  Created by Adam Maxwell on 12/7/08.
 *
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

#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <pwd.h>
#include <string.h>

#include <asl.h>
#include <sys/time.h>

extern char **environ;

#define STACK_BUFFER_SIZE 2048
#define TLM_ASL_SENDER "tlmgr_cwrapper"
#define TLM_ASL_FACILITY NULL


/* http://www.cocoabuilder.com/archive/message/cocoa/2001/6/15/21704 */

int main(int argc, char *argv[]) {
    setuid(geteuid());
    
    /* 
     argv[0]: tlmgr_cwrapper
     argv[1]: y or n
     argv[2]: tlmgr
     argv[n]: tlmgr arguments
     */
    if (argc < 2) {
        fprintf(stderr, "tlmgr_cwrapper: insufficient arguments\n");
        exit(1);
    }
    
    /* Require a single character argument 'y' || 'n'.      */
    /* Don't accept 'yes' or 'no' or 'nitwit' as arguments. */
    char *c = argv[1];
    if (strlen(c) != 1 || ('y' != *c && 'n' != *c)) {
        fprintf(stderr, "tlmgr_cwrapper: first argument '%s' was unrecognized\n", c);
        exit(1);
    }
    
    /* If yes, do what sudo -H does: read root's passwd entry and change HOME. */
    if ('y' == *c) {    
        struct passwd *pw = getpwuid(getuid());
        if (NULL == pw) {
            perror("getpwuid failed in tlmgr_cwrapper");
            exit(1);
        }
        setenv("HOME", pw->pw_dir, 1);
    }
    
    int i;
#if 0
    fprintf(stderr, "uid = %d, euid = %d\n", getuid(), geteuid());
    for (i = 0; i < argc; i++) {
        fprintf(stderr, "argv[%d] = %s\n", i, argv[i]);
    }
#endif
    
    int outpipe[2];
    int errpipe[2];
    
    if (pipe(outpipe) < 0 || pipe(errpipe) < 0) {
        perror("pipe failed");
        exit(1);
    }
    
    if (dup2(outpipe[1], STDOUT_FILENO) < 0) {
        perror("dup2 stdout failed");
        exit(1);
    }
    
    if (dup2(errpipe[1], STDERR_FILENO) < 0) {
        perror("dup2 stderr failed");
        exit(1);
    }
    
    fprintf(stderr, "tlmgr_cwrapper: HOME = '%s'\n", getenv("HOME"));

    int ret = 0;
    pid_t child = fork();
    if (0 == child) {
        i = execve(argv[2], &argv[2], environ);
        _exit(i);
    }
    else if (-1 == child) {
        perror("fork failed");
        exit(1);
    }
    else {
        
        char *line, buf[STACK_BUFFER_SIZE];        
        
        fd_set fdset;
        FD_ZERO(&fdset);
        FD_SET(outpipe[0], &fdset);
        FD_SET(errpipe[0], &fdset);
        
        aslclient client = asl_open(TLM_ASL_SENDER, TLM_ASL_FACILITY, ASL_OPT_NO_DELAY);
        aslmsg m = asl_new(ASL_TYPE_MSG);
        asl_set(m, ASL_KEY_SENDER, TLM_ASL_SENDER);
        
        struct timeval tv;
        tv.tv_sec = 0;
        tv.tv_usec = 100000;
        
        int max_fd = outpipe[0];
        if (errpipe[0] > max_fd) max_fd = errpipe[0];
        max_fd += 1;
        
        FILE *outstrm = fdopen(outpipe[0], "r");
        FILE *errstrm = fdopen(errpipe[0], "r");
        
        int childStatus;
        
        while (select(max_fd, &fdset, NULL, NULL, &tv) > 0 || waitpid(child, &childStatus, WNOHANG) == 0) {
            
            if (FD_ISSET(outpipe[0], &fdset)) {
                line = fgets(buf, sizeof(buf), outstrm);
                asl_log(client, m, ASL_LEVEL_ERR, "%s", buf);
            }
            
            if (FD_ISSET(errpipe[0], &fdset)) {
                line = fgets(buf, sizeof(buf), errstrm);
                asl_log(client, m, ASL_LEVEL_ERR, "%s", buf);
            }
            
            FD_SET(outpipe[0], &fdset);
            FD_SET(errpipe[0], &fdset);

            tv.tv_sec = 0;
            tv.tv_usec = 100000;
        }    
        fclose(errstrm);
        fclose(outstrm);
        asl_free(m);
        asl_close(client);
        
        ret = WIFEXITED(childStatus) ? WEXITSTATUS(childStatus) : EXIT_FAILURE;
    }
    return ret;
}
