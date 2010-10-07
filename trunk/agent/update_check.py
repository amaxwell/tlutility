#!/usr/bin/python
# -*- coding: utf-8 -*-

from CoreFoundation import CFUserNotificationDisplayNotice, CFUserNotificationDisplayAlert, CFBundleCreate, CFBundleCopyResourceURL, CFPreferencesCopyAppValue
from CoreFoundation import kCFUserNotificationNoteAlertLevel, kCFUserNotificationAlternateResponse

from LaunchServices import LSFindApplicationForInfo, LSOpenCFURLRef
from LaunchServices import kLSUnknownCreator

from Foundation import NSConnection

from subprocess import Popen, PIPE
import os, sys

BUNDLE_ID = "com.googlecode.mactlmgr.tlu"
CONN_NAME = "com.googlecode.mactlmgr.tlu.doconnection"

def log_message(msg):
    sys.stderr.write("%s: %s\n" % (os.path.basename(sys.argv[0]), msg))

def check_for_updates():
    
    location = CFPreferencesCopyAppValue("TLMFullServerURLPreferenceKey", BUNDLE_ID)
    log_message("tlmgr will use %s" % (location))
    
    tlmgr = Popen(("/usr/texbin/tlmgr", "update", "--list", "--machine-readable", "--location", location), stdout=PIPE, universal_newlines=True)
    (stdout, stderr) = tlmgr.communicate()
    
    output = "".join([c for c in stdout])
    should_count = 0
    count = 0
    for line in output.split("\n"):
        
        if line == "end-of-header":
            should_count = True
        elif line == "end-of-updates":
            should_count = False
        elif should_count:
            count += 1
    
    return count

if __name__ == '__main__':
    
    update_count = check_for_updates()
    if update_count == 0:
        log_message("no updates available at this time")
        exit(0)
    
    title = "TeX Live updates available"
    msg = "Updates for %d %s are available for TeX Live.  Would you like to update with TeX Live Utility now, or at a later time?" % (update_count, "packages" if update_count > 1 else "package")
    
    ret, tlu_fsref, tlu_url = LSFindApplicationForInfo(kLSUnknownCreator, BUNDLE_ID, None, None, None)
            
    bundle = CFBundleCreate(None, tlu_url) if ret == 0 else None
    icon_url = CFBundleCopyResourceURL(bundle, "TeXDistTool", "icns", None) if bundle else None
    
    cancel, response = CFUserNotificationDisplayAlert(0, kCFUserNotificationNoteAlertLevel, icon_url, None, None, title, msg, "Later", "Update", None, None)    
    if kCFUserNotificationAlternateResponse == response:
        
        connection = NSConnection.connectionWithRegisteredName_host_(CONN_NAME, None)
        if connection != None:
            log_message("TeX Live Utility is running; refreshing package list")
            tlu = connection.rootProxy()
            tlu.orderFront()
            tlu.displayUpdates()  
        elif tlu_url != None:
            log_message("launching TeX Live Utility")
            LSOpenCFURLRef(tlu_url, None)
    else:
        log_message("user postponed TeX Live updates")
        
            
     