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
from Foundation import NSString
import sys

def _strings_dictionary_at_path(path):
    content, encoding, error = NSString.stringWithContentsOfFile_usedEncoding_error_(path, None, None)
    return content.propertyListFromStringsFileFormat()

def _check_strings_at_path(path, english_strings):
    sys.stdout.write("checking %s\n" % (path))
    strings = _strings_dictionary_at_path(path)
    for key in english_strings:
        if key not in strings:
            sys.stderr.write(("%s: missing %s\n" % (path, key)))

if __name__ == '__main__':
    
    english_strings_path = "English.lproj/Localizable.strings"
    paths_to_check = glob("*.lproj/Localizable.strings")
    assert english_strings_path in paths_to_check, "english strings file not found at %s" % (english_strings)
    paths_to_check.remove(english_strings_path)
        
    english_strings = _strings_dictionary_at_path(english_strings_path)
    
    for path in paths_to_check:
        _check_strings_at_path(path, english_strings)
