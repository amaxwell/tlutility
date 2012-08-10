#!/usr/bin/python
# -*- coding: utf-8 -*-

#
# This software is Copyright (c) 2010-2012
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

from subprocess import Popen, PIPE
import os, sys
from time import sleep

# dismiss alert after 12 hours of ignoring it (i.e., work computer running over the weekend)
_ALERT_TIMEOUT = 3600 * 12

# public attribute; can be checked from the shell with something like
# python -c 'import sys; sys.path.append("/Library/Application Support/TeX Live Utility"); import update_check as uc; sys.stdout.write("%s\n" % (uc.VERSION))'
VERSION = 0.1

def log_message(msg):
    """Writes to standard error, prepending the calling program name."""
    sys.stderr.write("%s: %s\n" % (os.path.basename(sys.argv[0]), msg))

def check_for_updates(tlmgr_path, repository=None):
    """Check for updates using TeX Live Manager.
    
    Arguments:
    tlmgr_path -- absolute path to tlmgr executable
    repository -- optional URL to be passed as the --repository argument to tlmgr
    
    Returns:
    Two-tuple with number of available updates and the actual repository used.
    
    Discussion:
    Launches the tlmgr executable and parses its machine-readable output.  Only
    updates and additions are counted towards the number of available updates
    returned.
    
    """
    
    assert os.path.isabs(tlmgr_path), "tlmgr_path must be absolute"
    assert os.path.exists(tlmgr_path), "%s does not exist" % (tlmgr_path)
    
    cmd = [tlmgr_path, "update", "--list", "--machine-readable"]
    
    if repository:
        log_message("tlmgr will use %s" % (repository))
        cmd += ("--repository", repository)
        
    tlmgr = Popen(cmd, stdout=PIPE, universal_newlines=True)
    (stdout, stderr) = tlmgr.communicate()
    
    output = "".join([c for c in stdout])
    is_list_line = False
    count = 0
    actual_repository = None
    for line in output.split("\n"):
        
        if line == "end-of-header":
            is_list_line = True
        elif line == "end-of-updates":
            is_list_line = False
        elif is_list_line:
            comps = line.split()
            #
            # d = deleted on server
            # u = updated on server
            # a = added on server
            # f = forcibly removed
            # r = reverse update
            #
            
            # ignore anything that's not an update or addition
            if len(comps) >= 2 and comps[1] in ("a", "u"):
                count += 1
        elif line.startswith("location-url"):
            actual_repository = line.strip().split()[-1]
    
    return count, actual_repository
    
def macosx_update_check():
    """Check for updates on Mac OS X.  Returns zero on success.
    
    Discussion:
    Requires PyObjC bindings for Python.  Works on Mac OS X 10.5 and later, only, unless
    the necessary PyObjC components can be installed manually on earlier systems.  An
    alert is displayed if updates are available, and the user is given an option to
    ignore it or launch TeX Live Utility to handle the updates.
    
    Some sanity checks are present to ensure a login session that can display the alert.
    They may not be sufficient to avoid showing the alert over a full-screen window,
    unless an application has captured the display.
    
    """
    
    assert sys.platform == "darwin", "incorrect platform"
    
    from CoreFoundation import CFUserNotificationDisplayNotice, CFUserNotificationDisplayAlert, CFBundleCreate, CFBundleCopyResourceURL, CFPreferencesCopyAppValue
    from CoreFoundation import kCFUserNotificationNoteAlertLevel, kCFUserNotificationAlternateResponse

    from Quartz import CGMainDisplayID, CGDisplayIsCaptured, CGSessionCopyCurrentDictionary
    from Quartz import kCGSessionOnConsoleKey, kCGSessionLoginDoneKey

    from LaunchServices import LSFindApplicationForInfo, LSOpenFromURLSpec
    from LaunchServices import kLSUnknownCreator, LSLaunchURLSpec

    from Foundation import NSURL, NSFoundationVersionNumber
    from math import floor
    
    # http://developer.apple.com/library/mac/#documentation/MacOSX/Conceptual/BPMultipleUsers/BPMultipleUsers.html
    sessionInfo = CGSessionCopyCurrentDictionary()
    if sessionInfo == None:
        log_message("unable to get session dictionary")
        return 0
        
    if sessionInfo[kCGSessionOnConsoleKey] is False:
        log_message("not running as console user; skipping update check")
        return 0
        
    if sessionInfo[kCGSessionLoginDoneKey] is False:
        log_message("login incomplete; skipping update check")
        return 0
            
    # check this first; no point in continuing if we can't show the alert
    # note: this doesn't help with Skim's full screen mode
    if CGDisplayIsCaptured(CGMainDisplayID()):
        log_message("main display not available for update alert")
        return 0

    # TeX Live Utility bundle identifier
    bundle_id = "com.googlecode.mactlmgr.tlu"
    
    # if this hasn't been set, try the default path
    texbin_path = CFPreferencesCopyAppValue("TLMTexBinPathPreferenceKey", bundle_id)
    if texbin_path == None and os.path.exists("/usr/texbin"):
        texbin_path = "/usr/texbin"
        
    if texbin_path == None:
        log_message("no tlmgr path set; TeX Live update check will not proceed")
        return 1
        
    repository = CFPreferencesCopyAppValue("TLMFullServerURLPreferenceKey", bundle_id)
    update_count, actual_repository = check_for_updates(os.path.join(texbin_path, "tlmgr"), repository=repository)

    if update_count == 0:
        return 0
        
    if floor(NSFoundationVersionNumber) > 833:

        bundle_id = "com.googlecode.mactlmgr.TLUNotifier"
        ret, tln_fsref, tln_url = LSFindApplicationForInfo(kLSUnknownCreator, bundle_id, None, None, None)

        # launch TLUNotifier, passing the URL as an odoc Apple Event
        if ret == 0 and tln_url:
            log_message("using notifier %s with URL %s" % (tln_url, actual_repository))
            spec = LSLaunchURLSpec()
            spec.appURL = tln_url
            spec.itemURLs = [NSURL.URLWithString_(actual_repository)] if actual_repository else None
            ret, launchedURL = LSOpenFromURLSpec(spec, None)
            if ret:
                log_message("unable to launch TLUNotifier at %s (%d)" % (tln_url, ret))
        else:
            log_message("unable to find TLUNotifier")
        
    else:
     
        title = "TeX Live updates available"
        msg = "Updates for %d %s are available for TeX Live.  Would you like to update with TeX Live Utility now, or at a later time?" % (update_count, "packages" if update_count > 1 else "package")
    
        # see if we can find TeX Live Utility...hopefully LaunchServices is working today
        ret, tlu_fsref, tlu_url = LSFindApplicationForInfo(kLSUnknownCreator, bundle_id, None, None, None)
            
        bundle = CFBundleCreate(None, tlu_url) if ret == 0 else None
        icon_url = CFBundleCopyResourceURL(bundle, "TeXDistTool", "icns", None) if bundle else None
    
        # show a modal alert, with options to update now or later
        cancel, response = CFUserNotificationDisplayAlert(_ALERT_TIMEOUT, kCFUserNotificationNoteAlertLevel, icon_url, None, None, title, msg, "Later", "Update", None, None)    
        if kCFUserNotificationAlternateResponse == response:
        
            # launch TeX Live Utility, passing the URL as an odoc Apple Event
            spec = LSLaunchURLSpec()
            spec.appURL = tlu_url
            spec.itemURLs = [NSURL.URLWithString_(actual_repository)] if actual_repository else None
            ret, launchedURL = LSOpenFromURLSpec(spec, None)

        else:
            log_message("user postponed TeX Live updates")
        
    return 0

if __name__ == '__main__':
    
    status = 0
    
    if sys.platform == "darwin":
        status = macosx_update_check()
    else:
        log_message("unhandled platform %s" % (sys.platform))
        tlmgr_path = "/usr/texbin/tlmgr"
        update_count, actual_repository = check_for_updates(tlmgr_path)
        log_message("%d updates available from %s" % (update_count, actual_repository))
        
    exit(status)      
     