#!/usr/bin/env python

#
# This software is Copyright (c) 2010-2016
# Adam Maxwell. All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 
# - Redistributions of source code must retain the above copyright
# notice, this list of conditions and the following disclaimer.
# 
# - Redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in
# the documentation and/or other materials provided with the
# distribution.
# 
# - Neither the name of Adam Maxwell nor the names of any
# contributors may be used to endorse or promote products derived
# from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# 

from optparse import OptionParser
import os
import sys
from subprocess import call as sync_task
from shutil import copy2 as copyfile
import plistlib

LAUNCHCTL_PATH = "/bin/launchctl"
SCRIPT_NAME = "texliveupdatecheck"
PLIST_NAME = "com.googlecode.mactlmgr.update_check.plist"

def log_message(msg):
    """write a message to standard output"""
    sys.stderr.write("%s: %s\n" % (os.path.basename(sys.argv[0]), msg))

def installed_plist_path():
    """absolute path to the installed plist for the process owner"""
    
    plist_dir = "/Library/LaunchAgents" if os.geteuid() == 0 else os.path.expanduser("~/Library/LaunchAgents")
    return os.path.join(plist_dir, PLIST_NAME)
    
def installed_script_path():
    """absolute path to the installed script for the process owner"""
    
    script_dir = "/Library/Application Support/TeX Live Utility" 
    if os.geteuid() != 0:
        script_dir = os.path.expanduser("~" + script_dir)
    return os.path.join(script_dir, SCRIPT_NAME)

def unload_agent():
    """returns zero in case of success or if the plist does not exist"""
    
    plist_path = installed_plist_path()
    ret = 0
    if os.path.exists(plist_path):
        ret = sync_task([LAUNCHCTL_PATH, "unload", "-w", "-S", "Aqua", plist_path])
    else:
        log_message("nothing to unload")

    if ret:
        log_message("unable to unload agent %s" % (plist_path))
    return ret
    
def load_agent():
    """returns zero if the plist was loaded, raises if it does not exist"""
    
    plist_path = installed_plist_path()
    assert os.path.exists(plist_path), "%s does not exist" % (plist_path)
    ret = sync_task([LAUNCHCTL_PATH, "load", "-w", "-S", "Aqua", plist_path])
    if ret:
        log_message("unable to load agent %s" % (plist_path))
    return ret
    
def uninstall_agent():
    """returns nonzero if the plist exists and could not be unloaded"""
    
    plist_path = installed_plist_path()
    ret = 0
    
    # nonexistence is not a failure
    if os.path.exists(plist_path):  
        try:
            os.remove(plist_path)
        except Exception as e:
            log_message("ERROR: failed to remove %s" % (plist_path))
            ret = 1
    else:
        log_message("nothing to remove")
        
    return ret

def sync_agent_program_name():
    """ensure the launch agent plist has the current program name"""
    plist_path = installed_plist_path()
    
    exec_path = installed_script_path()
    
    # mainly for the change from Python update checker to Obj-C
    if os.path.exists(plist_path) and os.path.exists(exec_path):
        unload_agent()
        try:
            # Now edit the plist in-memory so it points to the correct path,
            # then save it out to the destination directory (avoids modifying
            # the passed-in file).
            with open(plist_path, "rb") as plfile:
                plist = plistlib.load(plfile)
            # rewrite entire array
            plist["ProgramArguments"] = [exec_path]
            with open(plist_path, "wb") as plfile:
                plistlib.dump(plist, plfile, fmt=plistlib.FMT_XML)
        except Exception as e:
            log_message("ERROR: failed to regenerate launchd plist %s with exception %s" % (plist_path, e))
        else:
            load_agent()

def install_agent(source_path):
    """argument is absolute path to the source property list"""
    
    plist_path = installed_plist_path()
    plist_dir = os.path.dirname(plist_path)
    ret = 0
    
    if os.path.exists(plist_dir) == False:
        try:
            os.makedirs(plist_dir)
        except Exception as e:
            log_message("ERROR: failed to create %s" % (plist_dir))
            ret = 1
    
    if ret == 0:
        assert os.path.isdir(plist_dir), "%s is not a directory" % (plist_dir)
        try:
            # Now edit the plist in-memory so it points to the correct path,
            # then save it out to the destination directory (avoids modifying
            # the passed-in file).
            with open(source_path, "rb") as plfile:
                plist = plistlib.load(plfile)
            # rewrite entire array
            plist["ProgramArguments"] = [installed_script_path()]
            with open(plist_path, "wb") as plfile:
                plistlib.dump(plist, plfile, fmt=plistlib.FMT_XML)
        except Exception as e:
            log_message("ERROR: failed to copy %s --> %s" % (source_path, plist_path))
            ret = 1
            
    return ret
    
def install_script(source_path):
    """argument is absolute path to the source script"""
    
    script_path = installed_script_path()
    script_dir = os.path.dirname(script_path)
    ret = 0
    
    if os.path.exists(script_dir) == False:
        try:
            os.makedirs(script_dir)
        except Exception as e:
            log_message("ERROR: failed to create %s" % (script_dir))
            ret = 1
    
    if ret == 0:
        assert os.path.isdir(script_dir), "%s is not a directory" % (script_dir)
        try:
            copyfile(source_path, script_path)
        except Exception as e:
            log_message("ERROR: failed to copy %s --> %s" % (source_path, script_path))
            ret = 1
            
    return ret    

if __name__ == '__main__':
        
    parser = OptionParser()
    parser.add_option("-i", "--install", help="install agent", action="store_true", dest="install", default=False)
    parser.add_option("-r", "--remove", help="remove agent", action="store_true", dest="remove", default=False)
    parser.add_option("-p", "--plist", help="path of property list to install", action="store", type="string", dest="source_plist")
    parser.add_option("-s", "--script", help="path of script to install", action="store", type="string", dest="source_script")
    
    (options, args) = parser.parse_args()
    
    if options.install == options.remove:
        if options.install == False:
            parser.error("an action (install or remove) must be specified")
        else:
            parser.error("only one action may be specified")
    
    if options.install:
        if options.source_plist is None and options.source_script is None:
            parser.error("at least one of option -p or -s is required")
        # if os.path.isabs(options.source_plist) == False or os.path.isabs(options.source_script) == False:
        #     parser.error("path arguments must be absolute")
        if options.source_plist and not os.path.isfile(options.source_plist):
            parser.error("path arguments cannot point to a directory")
            assert os.path.basename(options.source_plist) == PLIST_NAME, "incorrect plist name defined"
        if options.source_script and not os.path.isfile(options.source_script):
            parser.error("path arguments cannot point to a directory")
            assert os.path.basename(options.source_script) == SCRIPT_NAME, "incorrect script name defined"
        
    status = 0
      
    if options.remove:
        status += unload_agent()
        status += uninstall_agent()
    else:
        assert options.install, "inconsistent option checking"
        # unload a previous version before installing
        if options.source_plist:
            status += unload_agent()
            
        if options.source_script:
            status += install_script(options.source_script)
                        
        # if unloaded and we have a plist, now try to install and load it
        if status == 0 and options.source_plist:
            status = install_agent(options.source_plist)
            if status == 0:
                status = load_agent()
                
        # in case the name of the script has changed; will also unload/reload
        if 0 == status:
            sync_agent_program_name()
        
    
    exit(status)

