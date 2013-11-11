#!/usr/bin/env python
# -*- coding: utf-8 -*-

#
# This software is Copyright (c) 2009-2013
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

from Foundation import *

options = []
variables = []
docs = []
lang = []
collections = []
other = []

TEXLIVE_YEAR = 2012

for line in open("/usr/local/texlive/%d/tlpkg/texlive.profile" % (TEXLIVE_YEAR), "r"):
    
    if line.startswith("#"):
        continue
        
    keyValues = line.strip().split(" ")
    
    key = keyValues[0]
    value = " ".join(keyValues[1:])
        
    profileDictionary = {}

    profileDictionary["key"] = key
    
    if len(value) == 1 and value.isdigit():
        profileDictionary["value"] = (value and True or False)
    else:
        profileDictionary["value"] = value
    
    # default human-readable string
    profileDictionary["name"] = key
    
    if key.startswith("TEX"):
        profileDictionary["name"] = key
        profileDictionary["type"] = "variable"
        variables.append(profileDictionary)
    # do longest match first on keys with a common prefix
    elif key.startswith("collection-documentation-"):
        profileDictionary["name"] = key[len("collection-documentation-"):].capitalize()
        profileDictionary["type"] = "documentation"
        docs.append(profileDictionary)
    elif key.startswith("collection-lang"):
        profileDictionary["name"] = key[len("collection-lang"):].capitalize()
        profileDictionary["type"] = "language"
        lang.append(profileDictionary)
    elif key.startswith("collection-"):
        profileDictionary["name"] = key[len("collection-"):]
        profileDictionary["type"] = "collection"
        collections.append(profileDictionary)
    elif key.startswith("option"):
        profileDictionary["type"] = "option"
        options.append(profileDictionary)
    else:
        profileDictionary["type"] = "unknown"
        other.append(profileDictionary)
                
profileValues = { "options" : options, "variables" : variables, "documentation" : docs, "languages" : lang, "collections" : collections, "other" : other }

# add another dictionary for my metadata
profileValues["com.googlecode.mactlmgr"] = { "texliveyear" : TEXLIVE_YEAR }
    
plist, error = NSPropertyListSerialization.dataFromPropertyList_format_errorDescription_(profileValues, NSPropertyListXMLFormat_v1_0, None)

plist.writeToFile_atomically_("texlive.profile.plist", False)

#print plist
#plist = NSDictionary.dictionaryWithDictionary_(pd)
#print plist
