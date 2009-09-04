#!/usr/bin/env python
# -*- coding: utf-8 -*-

from Foundation import *

profile = open("/usr/local/texlive/2009/tlpkg/texlive.profile")

options = []
variables = []
docs = []
lang = []
collections = []
other = []

for line in profile:
    
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
    
plist, error = NSPropertyListSerialization.dataFromPropertyList_format_errorDescription_(profileValues, NSPropertyListXMLFormat_v1_0, None)

plist.writeToFile_atomically_("texlive.profile.plist", False)

#print plist
#plist = NSDictionary.dictionaryWithDictionary_(pd)
#print plist
