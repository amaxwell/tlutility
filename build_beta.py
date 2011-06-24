#!/usr/bin/python

#
# This script is part of TeX Live Utility.  Various paths are hardcoded near
# the top, along with other paths that are dependent on those.  The script
# takes a single argument, which is the new version.  It alters the Info.plist
# CFBundleVersion, rebuilds the Xcode project, wraps it in a gzipped tarball,
# and then modifies the appcast file with the requisite information from the
# new tarball.  
# 
# 1) python build_tlu.py
# 2) step 1 created /tmp/TeX Live Utility.app.zip
# 3) upload the .zip file to the website
# 4) svn commit sources and tag as necessary
#

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
from stat import *
import tarfile
from datetime import tzinfo, timedelta, datetime
import urllib
import plistlib
import tempfile

from Foundation import NSUserDefaults

def GetSymRoot():
    xcprefs = NSUserDefaults.standardUserDefaults().persistentDomainForName_("com.apple.Xcode")
    return xcprefs["PBXApplicationwideBuildSettings"]["SYMROOT"].stringByStandardizingPath()

# determine the path based on the path of this program
SOURCE_DIR = os.path.dirname(os.path.abspath(sys.argv[0]))
assert len(SOURCE_DIR)
assert SOURCE_DIR.startswith("/")

# derived paths
BUILD_DIR = os.path.join(GetSymRoot(), "Release")
BUILT_APP = os.path.join(BUILD_DIR, "TeX Live Utility.app")
PLIST_PATH = os.path.join(SOURCE_DIR, "Info.plist")

# change CFBundleVersion and rewrite the Info.plist
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

# clean and rebuild the Xcode project
buildCmd = ["/usr/bin/xcodebuild", "-configuration", "Release", "-target", "TeX Live Utility", "clean", "build"]
nullDevice = open("/dev/null", "r")
x = Popen(buildCmd, cwd=SOURCE_DIR, stdout=nullDevice, stderr=nullDevice)
rc = x.wait()
if rc != 0:
    print "xcodebuild failed"
    exit(rc)
nullDevice.close()

# create a name for the tarball
tarballName = os.path.join("/tmp", os.path.basename(BUILT_APP) + ".tgz")

# create a tarfile object
tarball = tarfile.open(tarballName, "w:gz")
tarball.add(BUILT_APP, os.path.basename(BUILT_APP))
tarball.close()
