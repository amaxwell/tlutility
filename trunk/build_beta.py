#!/usr/bin/python

"""
This script is part of TeX Live Utility.  Various paths are hardcoded near
the top, along with other paths that are dependent on those.

Running build_beta.py does the following:

1) bump the version in Info.plist by 0.1 if it is not a beta, and appends b1;
   otherwise, it increments bN to b(N+1)
2) does a clean/build, creating SYMROOT/Release/TeX Live Utility.app-DATE.tgz
3) uploads the .tgz file to the project page

The appcast is not modified, the description starts with BETA, and it will
not be featured when uploaded.
   
"""

#
# Created by Adam Maxwell on 12/28/08.
#
# This software is Copyright (c) 2008-2011
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

import os, sys
from subprocess import Popen, PIPE
from stat import ST_SIZE
import tarfile
from time import gmtime, strftime, localtime
import urllib
import plistlib
import tempfile
import googlecode_upload

from Foundation import NSUserDefaults

def GetSymRoot():
    xcprefs = NSUserDefaults.standardUserDefaults().persistentDomainForName_("com.apple.Xcode")
    return xcprefs["PBXApplicationwideBuildSettings"]["SYMROOT"].stringByStandardizingPath()

# determine the path based on the path of this program
SOURCE_DIR = os.path.dirname(os.path.abspath(sys.argv[0]))
assert len(SOURCE_DIR)
assert SOURCE_DIR.startswith("/")

# name of keychain item for svn/upload
UPLOAD_KEYCHAIN_ITEM = "<https://mactlmgr.googlecode.com:443> Google Code Subversion Repository"

# derived paths
BUILD_DIR = os.path.join(GetSymRoot(), "Release")
BUILT_APP = os.path.join(BUILD_DIR, "TeX Live Utility.app")
PLIST_PATH = os.path.join(SOURCE_DIR, "Info.plist")

def rewrite_version():
    
    infoPlist = plistlib.readPlist(PLIST_PATH)
    assert infoPlist is not None, "unable to read Info.plist"
    oldVersion = infoPlist["CFBundleVersion"]
    assert oldVersion is not None, "unable to read old version from Info.plist"
        
    if "b" in oldVersion:
        base, beta = oldVersion.split("b")
        newVersion = "%sb%d" % (base, int(beta) + 1)
    else:
        newVersion = "%.2f" % (float(oldVersion) + 0.01) + "b1"

    infoPlist["CFBundleVersion"] = newVersion
    infoPlist["CFBundleShortVersionString"] = newVersion
    plistlib.writePlist(infoPlist, PLIST_PATH)
    
    return newVersion

def clean_and_build():
    
    # clean and rebuild the Xcode project
    buildCmd = ["/usr/bin/xcodebuild", "-configuration", "Release", "-target", "TeX Live Utility", "clean", "build"]
    nullDevice = open("/dev/null", "r")
    x = Popen(buildCmd, cwd=SOURCE_DIR, stdout=nullDevice, stderr=nullDevice)
    rc = x.wait()
    assert rc == 0, "xcodebuild failed"
    nullDevice.close()

def create_tarball_of_application():
    
    # create a name for the tarball based on today's date
    tarballName = strftime("%Y%m%d", localtime())
    tarballName = os.path.join(BUILD_DIR, os.path.basename(BUILT_APP) + "-" + tarballName + ".tgz")

    # create a tarfile object
    tarball = tarfile.open(tarballName, "w:gz")
    tarball.add(BUILT_APP, os.path.basename(BUILT_APP))
    tarball.close()
    
    return tarballName

def user_and_pass_for_upload():
    
    pwtask = Popen(["/usr/bin/security", "find-generic-password", "-g", "-s", UPLOAD_KEYCHAIN_ITEM], stdout=PIPE, stderr=PIPE)
    [output, error] = pwtask.communicate()
    pwoutput = output + error
        
    username = None
    password = None
    for line in pwoutput.split("\n"):
        line = line.strip()
        acct_prefix = "\"acct\"<blob>="
        pw_prefix = "password: "
        if line.startswith(acct_prefix):
            assert username == None, "already found username"
            username = line[len(acct_prefix):].strip("\"")
        elif line.startswith(pw_prefix):
            assert password == None, "already found password"
            password = line[len(pw_prefix):].strip("\"")
    
    assert username and password, "unable to find username and password for %s" % (UPLOAD_KEYCHAIN_ITEM)
    return username, password
    
if __name__ == '__main__':

    newVersion = rewrite_version()
    clean_and_build()
    tarballPath = create_tarball_of_application()
    
    username, password = user_and_pass_for_upload()
    summary = "BETA: %s build (%s)" % (strftime("%Y%m%d", localtime()), newVersion)
    labels = ["Type-Archive", "OpSys-OSX"]
    print username, password, summary, labels
    #googlecode_upload.upload(tarballPath, "mactlmgr", username, password, summary, labels)

