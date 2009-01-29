#!/usr/bin/python

#
# This script is part of TeX Live Utility.  Various paths are hardcoded near
# the top, along with other paths that are dependent on those.  The script
# takes a single argument, which is the new version.  It alters the Info.plist
# CFBundleVersion, rebuilds the Xcode project, wraps it in a gzipped tarball,
# and then modifies the appcast file with the requisite information from the
# new tarball.  
# 
# 1) python build_tlu.py 0.3
# 2) step 1 created SYMROOT/Release/TeX Live Utility.app-DATE.tgz
# 3) upload the .tgz file to the project page
# 4) svn commit sources and tag as necessary, recalling that the appcast is
#    live as soon as it is checked in
#

#
# Created by Adam Maxwell on 12/28/08.
#
# This software is Copyright (c) 2008
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

# for NSXMLDocument
from Foundation import *

def GetSymRoot():
    xcprefs = NSUserDefaults.standardUserDefaults().persistentDomainForName_("com.apple.Xcode")
    return xcprefs["PBXApplicationwideBuildSettings"]["SYMROOT"].stringByStandardizingPath()

# fixed paths
SOURCE_DIR = os.path.expanduser("~/build/mactlmgr")

# name of secure note in Keychain
KEY_NAME = "TeX Live Utility Sparkle Key"

# derived paths
BUILD_DIR = os.path.join(GetSymRoot(), "Release")
APPCAST_PATH = os.path.join(SOURCE_DIR, "appcast", "tlu_appcast.xml")
BUILT_APP = os.path.join(BUILD_DIR, "TeX Live Utility.app")
PLIST_PATH = os.path.join(SOURCE_DIR, "Info.plist")

# single arg is required (the new version)
assert len(sys.argv) > 1, "missing new version argument"
oldVersion = None
newVersion = sys.argv[-1]

# change CFBundleVersion and rewrite the Info.plist
infoPlist = plistlib.readPlist(PLIST_PATH)
assert infoPlist is not None, "unable to read Info.plist"
oldVersion = infoPlist["CFBundleVersion"]
assert oldVersion is not None, "unable to read old version from Info.plist"
infoPlist["CFBundleVersion"] = newVersion
infoPlist["CFBundleShortVersionString"] = newVersion
plistlib.writePlist(infoPlist, PLIST_PATH)

# sanity check to avoid screwing up the appcast
assert oldVersion != newVersion, "CFBundleVersion is already at " + newVersion

# clean and rebuild the Xcode project
buildCmd = ["/usr/bin/xcodebuild", "-configuration", "Release", "-target", "TeX Live Utility", "clean", "build"]
nullDevice = open("/dev/null", "r")
x = Popen(buildCmd, cwd=SOURCE_DIR, stdout=nullDevice, stderr=nullDevice)
rc = x.wait()
if rc != 0:
    print "xcodebuild failed"
    exit(rc)
nullDevice.close()

# create a name for the tarball based on today's date
tarballName = datetime.today().strftime("%Y%m%d")
tarballName = os.path.join(BUILD_DIR, os.path.basename(BUILT_APP) + "-" + tarballName + ".tgz")

# create a tarfile object
tarball = tarfile.open(tarballName, "w:gz")
tarball.add(BUILT_APP, os.path.basename(BUILT_APP))
tarball.close()

def keyFromSecureNote():
    
    # see http://www.entropy.ch/blog/Developer/2008/09/22/Sparkle-Appcast-Automation-in-Xcode.html
    pwtask = Popen(["/usr/bin/security", "find-generic-password", "-g", "-s", KEY_NAME], stdout=PIPE, stderr=PIPE)
    [output, error] = pwtask.communicate()
    pwoutput = output + error

    # notes are evidently stored as archived RTF data, so find start/end markers
    start = pwoutput.find("-----BEGIN DSA PRIVATE KEY-----")
    stopString = "-----END DSA PRIVATE KEY-----"
    stop = pwoutput.find(stopString)

    assert start is not -1 and stop is not -1, "failed to find DSA key in secure note"

    key = pwoutput[start:stop] + stopString
    
    # replace RTF end-of-lines
    key = key.replace("\\134\\012", "\n")
    
    return key

# write to a temporary file that's readably only by owner; minor security issue here since
# we have to use a named temp file, but it's better than storing unencrypted key
keyFile = tempfile.NamedTemporaryFile()
keyFile.write(keyFromSecureNote())
keyFile.flush()

# now run the signature for Sparkle...
sha_task = Popen(["/usr/bin/openssl", "dgst", "-sha1", "-binary"], stdin = open(tarballName, "rb"), stdout = PIPE)
dss_task = Popen(["/usr/bin/openssl", "dgst", "-dss1", "-sign", keyFile.name], stdin = sha_task.stdout, stdout = PIPE)
b64_task = Popen(["/usr/bin/openssl", "enc", "-base64"], stdin = dss_task.stdout, stdout = PIPE)

# now compute the variables we need for writing the new appcast
appcastSignature = b64_task.communicate()[0].strip()
appcastDate = Popen(["/bin/date", "+%a, %d %b %Y %T %z"], stdout = PIPE).communicate()[0].strip()
theURL = "http://mactlmgr.googlecode.com/files/" + urllib.pathname2url(os.path.basename(tarballName))
fileSize = str(os.stat(tarballName)[ST_SIZE])

# creating this from a string is easier than manipulating NSXMLNodes...
newItemString = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"  xmlns:dc="http://purl.org/dc/elements/1.1/">
   <channel>
   <item>
        <title>Version """ + newVersion + """</title>
        <description>
	    <h3>Changes Since """ + str(oldVersion) + """</h3>
	        <li></li>
	        <li></li>
        </description>
        <pubDate>""" + appcastDate + """</pubDate>
        <enclosure url=\"""" + theURL + """\" sparkle:version=\"""" + newVersion + """\" length=\"""" + fileSize + """\" type="application/octet-stream" sparkle:dsaSignature=\"""" + appcastSignature + """\" />
    </item>
    </channel>
</rss>"""

# read from the source directory
appcastURL = NSURL.fileURLWithPath_(APPCAST_PATH)

# xml doc from the current appcast
(oldDoc, error) = NSXMLDocument.alloc().initWithContentsOfURL_options_error_(appcastURL, 0, None)
assert oldDoc is not None, error

# xml doc from the new appcast string
(newDoc, error) = NSXMLDocument.alloc().initWithXMLString_options_error_(newItemString, 0, None)
assert newDoc is not None, error

# get an arry of the current item titles
(oldTitles, error) = oldDoc.nodesForXPath_error_("//item/title", None)
assert oldTitles.count > 0, "oldTitles had no elements"

# now get the title we just created
(newTitles, error) = newDoc.nodesForXPath_error_("//item/title", None)
assert newTitles.count() is 1, "newTitles must have a single element"

# easy test to avoid duplicating items
if oldTitles.containsObject_(newTitles.lastObject()) is False:

    # get the parent node we'll be inserting to
    (parentChannel, error) = oldDoc.nodesForXPath_error_("//channel", None)
    assert parentChannel.count() is 1, "channel count must be one"
    parentChannel = parentChannel.lastObject()

    # now get the new node
    (newNodes, error) = newDoc.nodesForXPath_error_("//item", None)
    assert newNodes is not None, error

    # insert a copy of the new node
    parentChannel.addChild_(newNodes.lastObject().copy())
    
    # write to NSData, since pretty printing didn't work with NSXMLDocument writing
    oldDoc.XMLDataWithOptions_(NSXMLNodePrettyPrint).writeToURL_atomically_(appcastURL, True)
