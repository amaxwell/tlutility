#!/usr/bin/env python

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


from glob import glob
from Foundation import NSString, NSUTF8StringEncoding
from CoreFoundation import CFStringConvertNSStringEncodingToEncoding, CFStringConvertEncodingToIANACharSetName
import os, sys
import codecs

class StringsEntry(object):
    """docstring for StringsEntry"""
    def __init__(self):
        super(StringsEntry, self).__init__()
        self.key = None
        self.value = None
        self.comment = ""
        self.order = None
        self.line_number = 0
        
    def string_value(self):
        return (u"%s\"%s\" = \"%s\";\n" % (self.comment, self.key, self.value))
        
    def __repr__(self):
        return self.string_value()

IN_COMMENT          = 0
IN_VALUE            = 1
SINGLE_LINE_COMMENT = 2

def _normalize_key(key):
    key = key.encode("raw_unicode_escape").encode("utf-8").decode("string_escape")
    if "\\u" in key:
        key = key.replace("\\u", "\\U")
    return key

def _strings_entries_at_path(path):
    
    content, nsencoding, error = NSString.stringWithContentsOfFile_usedEncoding_error_(path, None, None)
    if nsencoding == 0:
        sys.stderr.write("%s:0:0: error: could not determine file's encoding\n" % (path))
        exit(1)
        
    cfencoding = CFStringConvertNSStringEncodingToEncoding(nsencoding)
    iana_encoding = CFStringConvertEncodingToIANACharSetName(cfencoding)
    
    # Apple docs still say to use UTF-16, and that's what genstrings et al output
    if nsencoding != NSUTF8StringEncoding:
        sys.stderr.write("%s:0:0: warning: file is using %s encoding instead of utf-8\n" % (path, iana_encoding))
    
    entries = {}
    current_entry = None
    state = IN_COMMENT
    
    for line_number, line in enumerate(content.split("\n")):
        line = line.strip("\n")
        
        # make this 1-based everywhere
        line_number = line_number + 1
        
        if line.startswith("/*"):
            state = IN_COMMENT
        elif line.startswith("//"):
            state = SINGLE_LINE_COMMENT

        if state in (IN_COMMENT, SINGLE_LINE_COMMENT):
            
            if current_entry is None:
                current_entry = StringsEntry()
                current_entry.line_number = line_number
                
            current_entry.comment += line + "\n"
            current_entry.order = len(entries)
            
            # reset state for SINGLE_LINE_COMMENT also; next pass through the loop
            # can set it back, in case we have consecutive comments
            if line.endswith("*/") or state == SINGLE_LINE_COMMENT:
                state = IN_VALUE
                continue
            
        if state == IN_VALUE and len(line):
            key, ignored, value = line.partition("\" = \"")
            if key is None or len(key) == 0:
                sys.stderr.write("%s:%d:0: error: missing key in strings file\n" % (path, line_number))
                exit(1)
            if value is None or len(value) == 0:
                sys.stderr.write("%s:%d:0: error: missing value for key in strings file\n" % (path, line_number))
                exit(1)
            if current_entry is None:
                sys.stderr.write("%s:%d:0: error: missing comment in strings file\n" % (path, line_number))
                exit(1)
            assert current_entry.comment, "empty comment found"
            # strip leading quote
            key = _normalize_key(key[1:])
            current_entry.key = key
            # strip trailing semicolon and quote
            current_entry.value = value[:-2]
            entries[key] = current_entry
            current_entry = None            
            
    return iana_encoding, entries
            

def _strings_dictionary_at_path(path):
    content, encoding, error = NSString.stringWithContentsOfFile_usedEncoding_error_(path, None, None)
    assert encoding == NSUTF8StringEncoding, "%s is not UTF-8 encoded" % (path)
    return content.propertyListFromStringsFileFormat()
    

def _check_strings_at_path(path, english_strings):
    sys.stderr.write("checking %s\n" % (path))
    destination_encoding, non_english_entries = _strings_entries_at_path(path)

    missing = []
    for key in english_strings:
        if key not in non_english_entries:
            missing.append(key)
    
    def _sort_by_order(a, b):
        return cmp(a.order, b.order)
    
    to_add = [english_strings[key] for key in missing]
    to_add = sorted(to_add, _sort_by_order)
    
    # now add to the strings file
    if len(to_add):
        sys.stderr.write("%s:0:0: warning: added %d missing strings\n" % (path, len(to_add)))
    
        # This really sucks; NSString returns NSUTF16StringEncoding regardless of the
        # endianness, and python's codec will insert a BOM before appending, using utf-16
        # without explicit endianness. For utf-16, then, we sniff the encoding BOM and
        # fully specify the utf-16 encoding, so python doesn't stuff BOM in the middle of
        # our files.
        if destination_encoding == "utf-16":
            assert os.path.getsize(path) >= 2, "file is too short for utf-16 data"
            with open(path, "rb") as output_file:
                raw = output_file.read(2)
                if raw.startswith(codecs.BOM_UTF16_LE):
                    destination_encoding = "utf-16LE"
                elif raw.startswith(codecs.BOM_UTF16_BE):
                    destination_encoding = "utf-16BE"
                else:
                    sys.stderr.write("%s:0:0: error: failed to determine endianness of strings file\n" % (path))
                    exit(1)
            
        with codecs.open(path, "ab", destination_encoding) as output_file:
            for x in to_add:
                output_file.write(u"\n" + x.string_value())

    # This is a later addition, once I realized that intermediate versions
    # of alert messages were being appended to the file. If manual intervention
    # gets annoying, we can edit the table manually, but it would have to be
    # re-parsed in order to account for anything we just added in the previous
    # step. Line numbers should still be current here, as anything we've added
    # comes later.
    to_remove = []
    for key in non_english_entries:
        if key not in english_strings:
            to_remove.append(key)
            bad_entry = non_english_entries[key]
            sys.stderr.write("%s:%d:0: warning: remove %s\n" % (path, bad_entry.line_number, key))

if __name__ == '__main__':
    
    english_lproj = "English.lproj" if os.path.exists("English.lproj") else "en.lproj"
    english_strings_path = os.path.join(english_lproj, "Localizable.strings")
    paths_to_check = glob("*.lproj/Localizable.strings")
    assert english_strings_path in paths_to_check, "english strings file not found at %s" % (english_strings)
    paths_to_check.remove(english_strings_path)
    
    iana_encoding, english_strings = _strings_entries_at_path(english_strings_path)

    for path in paths_to_check:
        _check_strings_at_path(path, english_strings)
