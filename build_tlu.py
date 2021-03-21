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
# 2) step 1 created SYMROOT/Release/TeX Live Utility.app-DATE.tar.tz
# 3) upload the .tar.gz file to the project page
# 4) svn commit sources and tag as necessary, recalling that the appcast is
#    live as soon as it is checked in
#

#
# Created by Adam Maxwell on 12/28/08.
#
# This software is Copyright (c) 2008-2016
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

import os, sys, io
from subprocess import Popen, PIPE
from stat import ST_SIZE
import tarfile
from time import gmtime, strftime, localtime, sleep
import plistlib
import tempfile
from getpass import getuser

import requests
from requests.auth import HTTPBasicAuth
import json
from uritemplate import expand as uri_expand 

from Foundation import NSXMLDocument, NSUserDefaults, NSURL, NSXMLNodePrettyPrint, NSXMLNodePreserveCDATA

# determine the path based on the path of this program
SOURCE_DIR = os.path.dirname(os.path.abspath(sys.argv[0]))
assert len(SOURCE_DIR)
assert SOURCE_DIR.startswith("/")

# name of secure note in Keychain
KEY_NAME = "TeX Live Utility Sparkle Key"

# name of keychain item for svn/upload
UPLOAD_KEYCHAIN_ITEM = "github.com"

# create a private temporary directory
SYMROOT = os.path.join("/tmp", "TLU-%s" % (getuser()))
try:
    # should already exist after the first run
    os.mkdir(SYMROOT)
except Exception as e:
    assert os.path.isdir(SYMROOT), "%s does not exist" % (SYMROOT)

# derived paths
BUILD_DIR = os.path.join(SYMROOT, "Release")
APPCAST_PATH = os.path.join(SOURCE_DIR, "appcast", "tlu_appcast.xml")
BUILT_APP = os.path.join(BUILD_DIR, "TeX Live Utility.app")
PLIST_PATH = os.path.join(SOURCE_DIR, "Info.plist")

def rewrite_version(newVersion):

    oldVersion = None

    # change CFBundleVersion and rewrite the Info.plist
    infoPlist = plistlib.readPlist(PLIST_PATH)
    assert infoPlist is not None, "unable to read Info.plist"
    oldVersion = infoPlist["CFBundleVersion"]
    assert oldVersion is not None, "unable to read old version from Info.plist"
    infoPlist["CFBundleVersion"] = newVersion
    infoPlist["CFBundleShortVersionString"] = newVersion
    minimumSystemVersion = infoPlist["LSMinimumSystemVersion"]
    plistlib.writePlist(infoPlist, PLIST_PATH)

    # sanity check to avoid screwing up the appcast
    assert oldVersion != newVersion, "CFBundleVersion is already at " + newVersion
    
    return oldVersion, minimumSystemVersion

def clean_and_build():
    
    # clean and rebuild the Xcode project
    buildCmd = ["/usr/bin/xcodebuild", "clean", "-scheme", "TeX Live Utility (Release)", "SYMROOT=" + SYMROOT]
    nullDevice = open("/dev/null", "w")
    x = Popen(buildCmd, cwd=SOURCE_DIR)
    rc = x.wait()
    print("xcodebuild clean exited with status %s" % (rc))

    buildCmd = ["/usr/bin/xcodebuild", "-scheme", "TeX Live Utility (Release)", "SYMROOT=" + SYMROOT, "buildsetting=", "CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO"]
    nullDevice = open("/dev/null", "w")
    x = Popen(buildCmd, cwd=SOURCE_DIR)#, stdout=nullDevice, stderr=nullDevice)
    rc = x.wait()
    assert rc == 0, "xcodebuild failed"
    nullDevice.close()

def codesign():
    
    sign_cmd = [os.path.join(SOURCE_DIR, "codesign-all.sh"), BUILT_APP]
    x = Popen(sign_cmd, cwd=SOURCE_DIR)
    rc = x.wait()
    print("codesign-all.sh exited with status %s" % (rc))
    assert rc == 0, "code signing failed"
    
def notarize_dmg_or_zip(dmg_path):
    """dmg_path: zip file or dmg file"""
    
    notarize_cmd = ["xcrun", "altool", "--notarize-app", "--primary-bundle-id", "com.mac.amaxwell.tlu", "--username", "amaxwell@mac.com", "--password",  "@keychain:AC_PASSWORD", "--output-format", "xml", "--file", dmg_path]
    notarize_task = Popen(notarize_cmd, cwd=SOURCE_DIR, stdout=PIPE, stderr=PIPE)
    [output, error] = notarize_task.communicate()
    rc = notarize_task.returncode
    print("altool --notarize-app exited with status %s" % (rc))
    assert rc == 0, "notarization failed"
    
    output_stream = io.BytesIO(output)
    output_pl = plistlib.readPlist(output_stream)
    output_stream.close()
    sys.stderr.write("%s\n" % (output))
    assert "notarization-upload" in output_pl, "missing notarization-upload key in reply %s" % (output)
    
    request_uuid = output_pl["notarization-upload"]["RequestUUID"]
    
    while True:
    
        sleep(20)
        
        # xcrun altool --notarization-info 401e7e6d-7bce-4e0a-87bd-bcb17b40bf97 --username amaxwell@mac.com --password @keychain:AC_PASSWORD
        
        notarize_cmd = ["xcrun", "altool", "--notarization-info", request_uuid, "--username", "amaxwell@mac.com", "--password",  "@keychain:AC_PASSWORD", "--output-format", "xml"]
        notarize_task = Popen(notarize_cmd, cwd=SOURCE_DIR, stdout=PIPE, stderr=PIPE)
        [output, error] = notarize_task.communicate()
        rc = notarize_task.returncode
        assert rc == 0, "status request failed"
        
        output_stream = io.BytesIO(output)
        output_pl = plistlib.readPlist(output_stream)
        assert "notarization-info" in output_pl, "missing notarization-upload key in reply %s" % (output)
        status = output_pl["notarization-info"]["Status"]
            
        if status == "invalid":
            # open the URL
            log_url = output_pl["notarization-info"]["LogFileURL"]
            Popen(["/usr/bin/open", "-a", "Safari", log_url])
            break
        elif status == "in progress":
            sys.stderr.write("notarization status not available yet for %s\n" % (request_uuid))
            continue
        else:
            # staple?
            sys.stderr.write("notarization succeeded\n")
            sys.stdout.write("%s\n" % (output))
                        
            log_url = output_pl["notarization-info"]["LogFileURL"]
            Popen(["/usr/bin/open", "-a", "Safari", log_url])
            
            break

def create_tarball_of_application(newVersionNumber):
    
    # Create a name for the tarball based on version number
    tarballName = os.path.join(BUILD_DIR, os.path.basename(BUILT_APP) + "-" + newVersionNumber + ".tar.gz")

    # create a tarfile object
    tarball = tarfile.open(tarballName, "w:gz")
    tarball.add(BUILT_APP, os.path.basename(BUILT_APP))
    tarball.close()
    
    return tarballName

def create_dmg_of_application(new_version_number):
    
    # Create a name for the tarball based on version number, instead
    # of date, since I sometimes want to upload multiple betas per day.
    final_dmg_name = os.path.join(BUILD_DIR, os.path.basename(BUILT_APP) + "-" + new_version_number + ".dmg")
    
    temp_dmg_path = "/tmp/TeX Live Utility.dmg"
    if os.path.exists(temp_dmg_path):
        os.unlink(temp_dmg_path)

    nullDevice = open("/dev/null", "w")
    cmd = ["/usr/bin/hdiutil", "create", "-fs", "HFS+", "-srcfolder", BUILT_APP, temp_dmg_path]
    x = Popen(cmd, stdout=nullDevice, stderr=nullDevice)
    rc = x.wait()
    assert rc == 0, "hdiutil create failed"

    cmd = ["/usr/bin/hdiutil", "convert", temp_dmg_path, "-format", "UDZO", "-imagekey", "zlib-level=9", "-o", final_dmg_name]
    x = Popen(cmd, stdout=nullDevice, stderr=nullDevice)
    rc = x.wait()
    assert rc == 0, "hdiutil convert failed"

    nullDevice.close()
    os.unlink(temp_dmg_path)
    
    return final_dmg_name    

def create_zip_of_application(new_version_number):
    
    # Create a name for the tarball based on version number, instead
    # of date, since I sometimes want to upload multiple betas per day.
    final_zip_name = os.path.join(BUILD_DIR, os.path.basename(BUILT_APP) + "-" + new_version_number + ".zip")
    
    nullDevice = open("/dev/null", "w")
    cmd = ["/usr/bin/ditto", "-c", "-k", "--keepParent", BUILT_APP, final_zip_name]
    x = Popen(cmd)
    rc = x.wait()
    assert rc == 0, "zip creation failed"
    
    return final_zip_name 

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
    
def signature_and_size(tarballName):
    
    # write to a temporary file that's readably only by owner; minor security issue here since
    # we have to use a named temp file, but it's better than storing unencrypted key
    keyFile = tempfile.NamedTemporaryFile()
    keyFile.write(keyFromSecureNote())
    keyFile.flush()

    # now run the signature for Sparkle...
    sha_task = Popen(["/usr/bin/openssl", "dgst", "-sha1", "-binary"], stdin=open(tarballName, "rb"), stdout=PIPE)
    dss_task = Popen(["/usr/bin/openssl", "dgst", "-dss1", "-sign", keyFile.name], stdin=sha_task.stdout, stdout=PIPE)
    b64_task = Popen(["/usr/bin/openssl", "enc", "-base64"], stdin=dss_task.stdout, stdout=PIPE)

    # now compute the variables we need for writing the new appcast
    appcastSignature = b64_task.communicate()[0].strip()
    fileSize = str(os.stat(tarballName)[ST_SIZE])
    
    return appcastSignature, fileSize
    
def update_appcast(oldVersion, newVersion, appcastSignature, tarballName, fileSize, minimumSystemVersion, download_url):
    
    appcastDate = strftime("%a, %d %b %Y %H:%M:%S +0000", gmtime())

    # creating this from a string is easier than manipulating NSXMLNodes...
    newItemString = """<?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"  xmlns:dc="http://purl.org/dc/elements/1.1/">
       <channel>
       <item>
            <title>Version """ + newVersion + """</title>
            <description>
            <![CDATA[
    	    <h3>Changes Since """ + str(oldVersion) + """</h3>
    	        <li></li>
    	        <li></li>
            ]]>
            </description>
            <pubDate>""" + appcastDate + """</pubDate>
            <sparkle:minimumSystemVersion>""" + minimumSystemVersion + """</sparkle:minimumSystemVersion>
            <enclosure url=\"""" + download_url + """\" sparkle:version=\"""" + newVersion + """\" length=\"""" + fileSize + """\" type="application/octet-stream" sparkle:dsaSignature=\"""" + appcastSignature + """\" />
        </item>
        </channel>
    </rss>"""

    # read from the source directory
    appcastURL = NSURL.fileURLWithPath_(APPCAST_PATH)

    # xml doc from the current appcast
    (oldDoc, error) = NSXMLDocument.alloc().initWithContentsOfURL_options_error_(appcastURL, NSXMLNodePreserveCDATA, None)
    assert oldDoc is not None, error

    # xml doc from the new appcast string
    (newDoc, error) = NSXMLDocument.alloc().initWithXMLString_options_error_(newItemString, NSXMLNodePreserveCDATA, None)
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

def user_and_pass_for_upload():
    
    pwtask = Popen(["/usr/bin/security", "find-internet-password", "-g", "-s", UPLOAD_KEYCHAIN_ITEM, "-t", "dflt"], stdout=PIPE, stderr=PIPE)
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
    
    pull_task = Popen(["/usr/bin/git", "pull"], cwd=SOURCE_DIR)
    rc = pull_task.wait()
    assert rc == 0, "update failed"
    
    sites_task = Popen(["/usr/bin/python", "read_ctan_sites.py"], cwd=SOURCE_DIR)
    rc = sites_task.wait()
    assert rc == 0, "parsing CTAN sites failed"
    commit_task = Popen(["/usr/bin/git", "commit", "CTAN.sites.plist", "-m", "update CTAN sites list"], cwd=SOURCE_DIR)
    commit_task.wait()
    
    # single arg is required (the new version)
    assert len(sys.argv) > 1, "missing new version argument"
    new_version = sys.argv[-1]
    print "will use version %s" % (new_version)
    
    old_version = "1.17"
    minimum_system_version = "10.6.8"

    old_version, minimum_system_version = rewrite_version(new_version)

    commit_task = Popen(["/usr/bin/git", "commit", "-a", "-m", "bump version to %s" % (new_version)], cwd=SOURCE_DIR)
    commit_task.wait()

    push_task = Popen(["/usr/bin/git", "push"], cwd=SOURCE_DIR)
    push_task.wait()

    # git tag -a 1.18b5 -m "release 1.18"
    tag_task = Popen(["/usr/bin/git", "tag", "-a", new_version, "-m", "release " + new_version])
    tag_task.wait()

    # git push origin --tags
    push_task = Popen(["/usr/bin/git", "push", "origin", "--tags"], cwd=SOURCE_DIR)
    push_task.wait()
    
    clean_and_build()
    codesign()
    dmg_or_zip_path = create_zip_of_application(new_version)
    
    # will bail if any part fails
    notarize_dmg_or_zip(dmg_or_zip_path)
    
    if dmg_or_zip_path.endswith("dmg"):
        # xcrun stapler staple TeX\ Live\ Utility.app-1.42b17.dmg 
        x = Popen(["xcrun", "stapler", "staple", dmg_or_zip_path])
        rc = x.wait()
        assert rc == 0, "stapler failed"
    else:
        # staple the application, then delete the zip we notarized
        # and make a new zip of the stapled application, because stapler
        # won't staple a damn zip file https://developer.apple.com/forums/thread/115670
        x = Popen(["xcrun", "stapler", "staple", BUILT_APP])
        rc = x.wait()
        assert rc == 0, "stapler failed"
        os.unlink(dmg_or_zip_path)
        dmg_or_zip_path = create_zip_of_application(new_version)
    
    username, password = user_and_pass_for_upload()
    auth = HTTPBasicAuth(username, password)
    r = requests.get("https://api.github.com/user", auth=auth)
    assert r.ok, "failed authentication"
    
    payload = {}
    payload["tag_name"] = new_version
    payload["target_commitish"] = "master"
    payload["name"] = new_version
    payload["body"] = "RELEASE: %s build (%s)" % (strftime("%Y%m%d", localtime()), new_version)
    payload["draft"] = False
    payload["prerelease"] = False
    
    r = requests.post("https://api.github.com/repos/amaxwell/tlutility/releases", data=json.dumps(payload), auth=auth)
    post_response = json.loads(r.text or r.content)
    upload_url = uri_expand(post_response["upload_url"], {"name" : os.path.basename(dmg_or_zip_path)})
    
    file_data = open(dmg_or_zip_path, "rb").read()
    mime_type = "application/x-apple-diskimage" if dmg_or_zip_path.endswith("dmg") else "application/zip"
    asset_response = json.loads(r.text or r.content)
    
    # should be part of appcast
    download_url = asset_response["browser_download_url"]
    print "download_url:", download_url
    
    appcast_signature, file_size = signature_and_size(dmg_or_zip_path)    
    update_appcast(old_version, new_version, appcast_signature, dmg_or_zip_path, file_size, minimum_system_version, download_url)

