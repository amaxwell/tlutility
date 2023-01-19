#!/usr/bin/env python

"""
This script is part of TeX Live Utility.  Various paths are hardcoded near
the top, along with other paths that are dependent on those.

Running build_beta.py does the following:

1) bump the version in Info.plist by 0.1 if it is not a beta, and appends b1;
   otherwise, it increments bN to b(N+1)
2) does a clean/build, creating SYMROOT/Release/TeX Live Utility.app-DATE.tar.gz
3) uploads the .tar.gz file to the project page

The appcast is not modified, the description starts with BETA, and it will
not be featured when uploaded.
   
"""

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
import tarfile
from time import strftime, localtime, sleep
import plistlib
from getpass import getuser

import requests
from requests.auth import HTTPBasicAuth
import json
from uritemplate import expand as uri_expand 

# determine the path based on the path of this program
SOURCE_DIR = os.path.dirname(os.path.abspath(sys.argv[0]))
assert len(SOURCE_DIR)
assert SOURCE_DIR.startswith("/")

# name of keychain item for svn/upload
UPLOAD_KEYCHAIN_ITEM = "github.com"

# create a private temporary directory
SYMROOT = os.path.join("/tmp", "TLU-%s" % (getuser()))
try:
    # should already exist after the first run
    os.mkdir(SYMROOT)
except Exception as e:
    assert os.path.isdir(SYMROOT), "%s does not exist" % (SYMROOT)

BUILD_DIR = os.path.join(SYMROOT, "Release")
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
        newVersion = "%.2f" % (float(".".join(oldVersion.split(".")[0:2])) + 0.01) + "b1"

    infoPlist["CFBundleVersion"] = newVersion
    infoPlist["CFBundleShortVersionString"] = newVersion
    plistlib.writePlist(infoPlist, PLIST_PATH)
    
    return newVersion

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
    print("altool --notarize-app exited with status %s: %s" % (rc, error))
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
    
    # Create a name for the tarball based on version number, instead
    # of date, since I sometimes want to upload multiple betas per day.
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


def user_and_pass_for_upload():
    
    # look for dflt account type, rather than the web form
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

    new_version = rewrite_version()
    commit_task = Popen(["/usr/bin/git", "commit", "-a", "-m", "bump beta version"], cwd=SOURCE_DIR)
    commit_task.wait()
    
    push_task = Popen(["/usr/bin/git", "push"], cwd=SOURCE_DIR)
    push_task.wait()
    
    # git tag -a 1.18b5 -m "beta 1.18b5"
    tag_task = Popen(["/usr/bin/git", "tag", "-a", new_version, "-m", "beta " + new_version])
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
    payload["body"] = "BETA: %s build (%s)" % (strftime("%Y%m%d", localtime()), new_version)
    payload["draft"] = False
    payload["prerelease"] = True
    
    r = requests.post("https://api.github.com/repos/amaxwell/tlutility/releases", data=json.dumps(payload), auth=auth)
    post_response = json.loads(r.text or r.content)
    upload_url = uri_expand(post_response["upload_url"], {"name" : os.path.basename(dmg_or_zip_path)})
    
    file_data = open(dmg_or_zip_path, "rb").read()
    mime_type = "application/x-apple-diskimage" if dmg_or_zip_path.endswith("dmg") else "application/zip"
    r = requests.post(upload_url, data=file_data, headers={"Content-Type" : mime_type}, auth=auth)
    asset_response = json.loads(r.text or r.content)
    
    # should be part of appcast
    download_url = asset_response["browser_download_url"]
    print("download_url: " + download_url)

