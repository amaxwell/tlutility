#!/usr/bin/python
# -*- coding: utf-8 -*-

from CoreFoundation import CFUserNotificationDisplayNotice, CFUserNotificationDisplayAlert, CFBundleCreate, CFBundleCopyResourceURL, CFPreferencesCopyAppValue
from CoreFoundation import kCFUserNotificationNoteAlertLevel, kCFUserNotificationAlternateResponse

from Quartz import CGMainDisplayID, CGDisplayIsCaptured, CGSessionCopyCurrentDictionary
from Quartz import kCGSessionOnConsoleKey, kCGSessionLoginDoneKey

from LaunchServices import LSFindApplicationForInfo, LSOpenCFURLRef
from LaunchServices import kLSUnknownCreator

from Foundation import NSConnection, NSURL

from subprocess import Popen, PIPE
import os, sys

_BUNDLE_ID = "com.googlecode.mactlmgr.tlu"
_CONN_NAME = "com.googlecode.mactlmgr.tlu.doconnection"

# dismiss alert after 12 hours of ignoring it (i.e., work computer running over the weekend)
_ALERT_TIMEOUT = 3600 * 12

# public attribute; can be checked from the shell with something like
# python -c 'import sys; sys.path.append("/Library/Application Support/TeX Live Utility"); import update_check as uc; sys.stdout.write("%s\n" % (uc.VERSION))'
VERSION = 0.1

def log_message(msg):
    sys.stderr.write("%s: %s\n" % (os.path.basename(sys.argv[0]), msg))

def check_for_updates():
    
    # if this hasn't been set, bail out, as this user likely won't care
    texbin_path = CFPreferencesCopyAppValue("TLMTexBinPathPreferenceKey", _BUNDLE_ID)
    if texbin_path == None and os.path.exists("/usr/texbin"):
        texbin_path = "/usr/texbin"
        
    if texbin_path == None:
        log_message("no tlmgr path set; TeX Live update check will not proceed")
        return 0
        
    cmd = [os.path.join(texbin_path, "tlmgr"), "update", "--list", "--machine-readable"]
    
    location = CFPreferencesCopyAppValue("TLMFullServerURLPreferenceKey", _BUNDLE_ID)
    if location:
        log_message("tlmgr will use %s" % (location))
        cmd += ("--location", location)
        
    tlmgr = Popen(cmd, stdout=PIPE, universal_newlines=True)
    (stdout, stderr) = tlmgr.communicate()
    
    output = "".join([c for c in stdout])
    is_list_line = False
    count = 0
    actual_location = None
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
            actual_location = line.strip().split()[-1]
    
    return count, actual_location

if __name__ == '__main__':
    
    # http://developer.apple.com/library/mac/#documentation/MacOSX/Conceptual/BPMultipleUsers/BPMultipleUsers.html
    sessionInfo = CGSessionCopyCurrentDictionary()
    if sessionInfo == None:
        log_message("unable to get session dictionary")
        exit(1)
        
    if sessionInfo[kCGSessionOnConsoleKey] is False:
        log_message("not running as console user; skipping update check")
        exit(1)
        
    if sessionInfo[kCGSessionLoginDoneKey] is False:
        log_message("login incomplete; skipping update check")
        exit(1)
            
    # check this first; no point in continuing if we can't show the alert
    # note: this doesn't help with Skim's full screen mode
    if CGDisplayIsCaptured(CGMainDisplayID()):
        log_message("main display not available for update alert")
        exit(0)
    
    update_count, actual_location = check_for_updates()
    if update_count == 0:
        exit(0)
     
    title = "TeX Live updates available"
    msg = "Updates for %d %s are available for TeX Live.  Would you like to update with TeX Live Utility now, or at a later time?" % (update_count, "packages" if update_count > 1 else "package")
    
    ret, tlu_fsref, tlu_url = LSFindApplicationForInfo(kLSUnknownCreator, _BUNDLE_ID, None, None, None)
            
    bundle = CFBundleCreate(None, tlu_url) if ret == 0 else None
    icon_url = CFBundleCopyResourceURL(bundle, "TeXDistTool", "icns", None) if bundle else None
    
    cancel, response = CFUserNotificationDisplayAlert(_ALERT_TIMEOUT, kCFUserNotificationNoteAlertLevel, icon_url, None, None, title, msg, "Later", "Update", None, None)    
    if kCFUserNotificationAlternateResponse == response:
        
        connection = NSConnection.connectionWithRegisteredName_host_(_CONN_NAME, None)
        if connection != None:
            log_message("TeX Live Utility is running; refreshing package list")
            tlu = connection.rootProxy()
            tlu.orderFront()
            update_url = NSURL.URLWithString_(actual_location) if actual_location else None
            tlu.displayUpdatesWithURL_(update_url)  
        elif tlu_url != None:
            log_message("launching TeX Live Utility")
            LSOpenCFURLRef(tlu_url, None)
    else:
        log_message("user postponed TeX Live updates")
        
            
     