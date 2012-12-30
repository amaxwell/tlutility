#!/usr/bin/env python

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


from glob import glob
from Foundation import NSString, NSUTF8StringEncoding
import os, sys

class StringsEntry(object):
    """docstring for StringsEntry"""
    def __init__(self):
        super(StringsEntry, self).__init__()
        self.key = None
        self.value = None
        self.comment = ""
        self.order = None
        
    def string_value(self):
        return ("%s\"%s\" = \"%s\";\n" % (self.comment, self.key, self.value)).encode("utf-8")
        
    def __repr__(self):
        return self.string_value()

IN_COMMENT = 0
IN_VALUE   = 1

def _normalize_key(key):
    key = key.encode("raw_unicode_escape").encode("utf-8").decode("string_escape")
    if "\\u" in key:
        key = key.replace("\\u", "\\U")
    return key

def _strings_entries_at_path(path):
    
    content, encoding, error = NSString.stringWithContentsOfFile_usedEncoding_error_(path, None, None)
    entries = {}
    current_entry = None
    state = IN_COMMENT
    
    for line in content.split("\n"):
        line = line.strip("\n")
        
        if line.startswith("/*"):
            state = IN_COMMENT

        if state == IN_COMMENT:
            
            current_entry = StringsEntry() if current_entry is None else current_entry
            current_entry.comment += line + "\n"
            current_entry.order = len(entries)
            
            if line.endswith("*/"):
                state = IN_VALUE
                continue
            
        if state == IN_VALUE and len(line):
            key, ignored, value = line.partition("\" = \"")
            assert key, "invalid key"
            assert value, "invalid value"
            assert current_entry.comment, "no comment found"
            assert current_entry, "no current entry"
            # strip leading quote
            key = _normalize_key(key[1:])
            current_entry.key = key
            # strip trailing semicolon and quote
            current_entry.value = value[:-2]
            entries[key] = current_entry
            current_entry = None            
            
    return entries
            

def _strings_dictionary_at_path(path):
    content, encoding, error = NSString.stringWithContentsOfFile_usedEncoding_error_(path, None, None)
    assert encoding == NSUTF8StringEncoding, "%s is not UTF-8 encoded" % (path)
    return content.propertyListFromStringsFileFormat()
    

def _check_strings_at_path(path, english_strings):
    sys.stderr.write("checking %s\n" % (path))
    strings = _strings_dictionary_at_path(path)
    pystrings = {}
    for nskey in strings:
        pystrings[_normalize_key(nskey)] = strings[nskey]
    strings = pystrings

    missing = []
    #print strings.keys()
    for key in english_strings:
        if key not in strings:
            missing.append(key)
    
    def _sort_by_order(a, b):
        return cmp(a.order, b.order)
    
    to_add = [english_strings[key] for key in missing]
    to_add = sorted(to_add, _sort_by_order)
    
    sys.stderr.write("found %d missing strings\n" % (len(to_add)))
    
    with open(path, "ab") as output_file:
        for x in to_add:
            output_file.write(x.string_value())


if __name__ == '__main__':
    
    english_lproj = "English.lproj" if os.path.exists("English.lproj") else "en.lproj"
    english_strings_path = os.path.join(english_lproj, "Localizable.strings")
    paths_to_check = glob("*.lproj/Localizable.strings")
    assert english_strings_path in paths_to_check, "english strings file not found at %s" % (english_strings)
    paths_to_check.remove(english_strings_path)
    
    english_strings = _strings_entries_at_path(english_strings_path)

    for path in paths_to_check:
        _check_strings_at_path(path, english_strings)