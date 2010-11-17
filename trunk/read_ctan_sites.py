#!/usr/bin/env python

#
# This software is Copyright (c) 2010
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

from plistlib import writePlist
from urllib import urlretrieve
from calendar import timegm
from datetime import datetime

SITES_URL = "http://www.tex.ac.uk/tex-archive/CTAN.sites"

JUNK    = 0 << 1
COUNTRY = 1 << 2
MIRROR  = 1 << 3
URL     = 1 << 4

class Mirror(object):
    """docstring for Mirror"""
    def __init__(self, name):
        super(Mirror, self).__init__()
        self.name = name
        self.urls = []
        
    def add_url(self, url):
        self.urls.append(url)
        
    def country(self):
        junk, country = self.name.split("(")
        country, junk = country.split(")")
        return country
        
    def mirror_name(self):
        return self.name.split("(")[0].strip()
        
    def __iter__(self):
        return self.urls.__iter__()
        
    def __str__(self):
        s = "Mirror {\n"
        s += "  name = %s\n" % (self.mirror_name())
        s += "  country = %s\n" % (self.country())
        for idx, url in enumerate(self.urls):
            s += "  URL %d: %s\n" % (idx + 1, url)
        s += "}\n"
        return s
        
class Continent(object):
    """docstring for Continent"""
    def __init__(self, name):
        super(Continent, self).__init__()
        self.name = name
        self.mirrors = []
        
    def add_mirror(self, mirror):
        self.mirrors.append(mirror)

    def __iter__(self):
        return self.mirrors.__iter__()
        

if __name__ == '__main__':
    
    (sites_path, headers) = urlretrieve(SITES_URL)
    
    with open(sites_path, "rb") as sites_file:
        
        state = 0
        state |= JUNK
        saved_line = None
        
        continents = []
        current_mirror = None
        
        for line in sites_file:
            
            line = line.strip()
            
            # skip empty lines
            if len(line) == 0:
                continue
                
            if line.startswith("=="):
                continents.append(Continent(saved_line))
                state = COUNTRY
            elif line.startswith("URL:"):
                
                if state == COUNTRY:
                    assert state & MIRROR == 0, "corrupt state"
                    assert state & URL == 0, "corrupt state"
                    current_mirror = Mirror(saved_line)
                    state |= MIRROR
                    continents[-1].add_mirror(current_mirror)

                assert state & MIRROR != 0, "corrupt state"
                current_mirror.add_url(line[4:])
                state |= URL
                    
            elif state & URL:
                # no longer reading URL lines, so unset that bit
                state &= ~URL
                # transition from URL to ~URL signals transition between mirrors
                state &= ~MIRROR
            
            saved_line = line
        
        plist = { "sites" : {}, "timestamp" : timegm(datetime.utcnow().timetuple()) }
        sites_dict = plist["sites"]
        for continent in continents:
            
            # keep a list of all mirrors for a given continent
            sites_dict[continent.name] = []
            
            for mirror in continent:
                clist = sites_dict[continent.name]
                mdict = {}
                mdict["name"] = mirror.mirror_name()
                mdict["country"] = mirror.country()
                mdict["urls"] = mirror.urls
                clist.append(mdict)

        writePlist(plist, "CTAN.sites.plist")
