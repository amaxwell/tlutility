#!/usr/bin/env python

#
# This software is Copyright (c) 2010-2012
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
    
class TLPackage(object):
    """TeX Live Package
    
    Conceptually this is nothing more than a dictionary.  It's able to
    convert itself to an sqlite3 row and a dictionary value.
    
    """
    mirror = None
    
    def __init__(self):
        super(TLPackage, self).__init__()
        self.name = None
        self.category = None
        self.shortdesc = None
        self.longdesc = None
        self.catalogue = None
        self.relocated = 0
        
        self.runfiles = []
        self.runsize = None
        
        self.srcfiles = []
        self.srcsize = None
        
        self.docfiles = []
        self.docsize = None
        
        # maps keys (doc filenames) to maps of attributes (details, language)
        self.docfiledata = {}
        
        self.executes = []
        self.postactions = []
        
        # maps keys (arch name) to lists of files
        self.binfiles = {}
        # maps keys (arch name) to integer size
        self.binsize = {}
        
        self.depends = []
        self.revision = None
        
        self.cataloguedata = {}
        
        self.extradata = {}
        
    def add_pair(self, key, value):
        """For data that I don't care about at the moment"""
        self.extradata[key] = value
        
    def __str__(self):
        return repr(self)
        
    def __repr__(self):
        s = "%s: %s\n  srcsize=%s\n  srcfiles=%s" % (self.name, self.shortdesc, self.srcsize, self.srcfiles)
        s += "\n  binsize = %s\n  binfiles = %s" % (self.binsize, self.binfiles)
        s += "\n  docsize = %s\n  docfiles = %s\n  docfiledata = %s" % (self.docsize, self.docfiles, self.docfiledata)
        s += "\n  runsize = %s\n  runfiles = %s" % (self.runsize, self.runfiles)
        s += "\n  depends = %s" % (self.depends)
        s += "\n  longdesc = %s" % (self.longdesc)
        s += "\n  cataloguedata = %s" % (self.cataloguedata)
        for k in self.extradata:
            s += "\n  %s = %s" % (k, self.extradata[k])
        return s
        
    def dictionary_value(self):
        """Returns a dictionary with name as key and attributes as key-value pairs.
        
        NOTE: not all attributes are saved, because I don't need all of them.  So if
        you don't see one in the plist, it may just need to be added as a line here.
        
        """
        kv = {}
        kv["name"] = self.name
        if self.category: kv["category"] = self.category
        if self.revision: kv["revision"] = self.revision
        if self.shortdesc: kv["shortDescription"] = self.shortdesc
        if self.longdesc: kv["longDescription"] = self.longdesc
        if self.catalogue: kv["catalogue"] = self.catalogue
        if self.runfiles: kv["runFiles"] = self.runfiles
        if self.srcfiles: kv["sourceFiles"] = self.srcfiles
        if self.binfiles: kv["binFiles"] = self.binfiles
        if self.cataloguedata: kv["catalogueData"] = self.cataloguedata
        if self.depends: kv["depends"] = self.depends
        if self.docfiles: kv["docFiles"] = self.docfiles
        if self.extradata: kv["extradata"] = self.extradata
        if self.docfiledata: kv["docFileData"] = self.docfiledata
        return kv
        
    def insert_in_packages(self, conn):
        """Inserts in an open SQLite3 database.  Limited support."""
        # c.execute("""CREATE table packages (name text, category text, revision real, shortdesc text, longdesc text, srcfiles blob, binfiles blob, docfiles blob)""")
        c = conn.cursor()
        c.execute("""INSERT into packages values (?,?,?,?,?,?,?,?)""", (self.name, self.category, self.revision, self.shortdesc, self.longdesc, self.runfiles, self.srcfiles, self.docfiles))
        conn.commit()

def _attributes_from_line(line):
    """Parse an attribute line.
    
    Arguments:
    line -- a single line from the tlpdb
    
    Returns:
    A dictionary of attributes
    
    Example input lines:
    
        arch=x86_64-darwin size=1
        details="Package introduction" language="de"
    
    """
    
    key = None
    value = None
    chars = []
    quote_count = 0
    attrs = {}
    for c in line:

        if c == "=":
            
            if key == None:
                assert quote_count == 0, "possibly quoted key in line %s" % (line)
                key = "".join(chars)
                chars = []
            else:
                chars.append(c)
        
        elif c == "\"":
            
            quote_count += 1
            
        elif c == " ":
            
            # if quotes are matched, we've reached the end of a key-value pair
            if quote_count % 2 == 0:
                assert key != None, "no key found for %s" % (line)
                assert key not in attrs, "key already assigned for line %s" % (line)
                attrs[key] = "".join(chars)
                
                # reset parser state
                chars = []
                key = None
                quote_count = 0
            else:
                chars.append(c)
                
        else:
            chars.append(c)
    
    assert key != None, "no key found for %s" % (line)
    assert len(chars), "no values found for line %s" % (line)
    attrs[key] = "".join(chars)
    return attrs

def packages_from_tlpdb(flat_tlpdb):
    """Creates a list of TLPackage objects from the given file-like object.
    
    Arguments:
    flat_tlpdb -- A file or file-like object, open for reading
    
    Returns:
    A list of TLPackage objects
    
    """            
    
    package = None
    package_index = 0
    all_packages = []
    index_map = {}
    last_key = None
    last_arch = None

    for line_idx, line in enumerate(flat_tlpdb):
    
        if line_idx == 0 and line.startswith("location-url\t"):
            TLPackage.mirror = line[len("location-url\t"):].strip()
            continue
            
        # comment lines; supported, but not currently used
        if line.startswith("#"):
            continue
                
        line = line.strip("\r\n")
    
        if len(line) == 0:
            all_packages.append(package)
            index_map[package.name] = package_index
            
            package_index += 1
            package = None
            last_key = None
            last_arch = None
        else:
            
            # the first space token is a delimiter
            key, ignored, value = line.partition(" ")
                            
            if package == None:
                assert key == "name", "first line must be a name"
                package = TLPackage()
        
            line_has_key = True
            if len(key) == 0:
                key = last_key
                line_has_key = False
                        
            if key == "name":
                package.name = value
            elif key == "category":
                package.category = value
            elif key == "revision":
                package.revision = int(value)
            elif key == "relocated":
                package.relocated = int(value)
            elif key == "shortdesc":
                package.shortdesc = value.decode("utf-8")
            elif key == "longdesc":
                oldvalue = "" if package.longdesc == None else package.longdesc
                package.longdesc = oldvalue + " " + value.decode("utf-8")
            elif key == "depend":
                package.depends.append(value)
            elif key == "catalogue":
                package.catalogue = value
            elif key.startswith("catalogue-"):
                catkey = key[len("catalogue-"):]
                package.cataloguedata[catkey] = value
            elif key == "srcfiles":
                if line_has_key:
                    attrs = _attributes_from_line(value)
                    assert "size" in attrs, "missing size for %s : %s" % (package.name, key)
                    package.srcsize = int(attrs["size"])
                else:
                    package.srcfiles.append(value)
            elif key == "binfiles":
                if line_has_key:
                    attrs = _attributes_from_line(value)
                    assert "arch" in attrs, "missing arch for %s : %s" % (package.name, key)
                    last_arch = attrs["arch"]
                    assert "size" in attrs, "missing size for %s : %s" % (package.name, key)
                    package.binsize[last_arch] = int(attrs["size"])
                else:
                    oldvalue = package.binfiles[last_arch] if last_arch in package.binfiles else []
                    oldvalue.append(value)
                    package.binfiles[last_arch] = oldvalue
            elif key == "docfiles":
                if line_has_key:
                    attrs = _attributes_from_line(value)
                    assert "size" in attrs, "missing size for %s : %s" % (package.name, key)
                    package.docsize = int(attrs["size"])
                else:
                    values = value.split(" ")
                    if len(values) > 1:
                        package.docfiledata[values[0]] = _attributes_from_line(" ".join(values[1:]))
                    package.docfiles.append(values[0])
            elif key == "runfiles":
                if line_has_key:
                    attrs = _attributes_from_line(value)
                    assert "size" in attrs, "missing size for %s : %s" % (package.name, key)
                    package.runsize = int(attrs["size"])
                else:
                    package.runfiles.append(value)
            elif key == "postaction":
                package.postactions.append(value)
            elif key == "execute":
                package.executes.append(value)
            else:
                package.add_pair(key, value)
                #assert False, "unhandled line %s" % (line)
                
            last_key = key

    return all_packages, index_map
    
def _save_as_sqlite(packages, absolute_path):
    """Save a list of packages as an SQLite3 binary file.
    
    Arguments:
    packages -- a list of TLPackage objects
    absolute_path -- output path for the database
    
    An existing file at this path will be removed before writing, to ensure that
    you end up with a consistent database.  This is mainly for symmetry with the
    plist writing method.
    
    Not all values are saved to sqlite.  Notably runfiles and other dictionary
    types are not written at present, since they should probably be in a separate
    table.
    
    """
    import sqlite3
    import os
    import errno
    
    def _adapt_list(lst):
        if lst is None or len(lst) == 0:
            return None
        return buffer("\0".join(lst).encode("utf-8"))

    sqlite3.register_adapter(list, _adapt_list)
    sqlite3.register_adapter(tuple, _adapt_list)
    
    # plistlib will overwrite the previous file, so do the same with sqlite
    # instead of adding rows
    try:
        os.remove(absolute_path)
    except OSError, e:
        if e.errno != errno.ENOENT:
            raise e
            
    assert os.path.exists(absolute_path) == False, "File exists: %s" % (absolute_path)
    conn = sqlite3.connect(absolute_path, detect_types=sqlite3.PARSE_DECLTYPES)
    c = conn.cursor()
    c.execute("""CREATE table packages (name text, category text, revision real, shortdesc text, longdesc text, runfiles blob, srcfiles blob, docfiles blob)""")
    for pkg in all_packages:
        pkg.insert_in_packages(conn)
    
    conn.close()
    
def _save_as_plist(packages, path_or_file):
    """Save a list of packages as a Mac OS X property list.
    
    Arguments:
    packages -- a list of TLPackage objects
    path_or_file -- output file (path or a file-like object) for the database
    
    The root object of the output property list is a dictionary.  Keys at
    present are "mirror" (may not exist) and "packages", which is a list
    of TLPackage dictionary values.
    
    """
    
    import plistlib
    plist = {}
    # only for remote tlpdb
    if TLPackage.mirror:
        plist["mirror"] = TLPackage.mirror
    plist["packages"] = []
    for pkg in all_packages:
        plist["packages"].append(pkg.dictionary_value())
    
    plistlib.writePlist(plist, path_or_file)
    
if __name__ == '__main__':
    
    from optparse import OptionParser
    import sys
        
    usage = "usage: %prog [options] [tlpdb_path or stdin]"
    parser = OptionParser()
    parser.set_usage(usage)
    parser.add_option("-o", "--output", dest="output_path", help="write tlpdb to FILE", metavar="FILE", action="store", type="string")
    parser.add_option("-f", "--format", dest="output_format", help="[sqlite3 | plist] (default is to guess from output file extension)", metavar="FORMAT", action="store", type="string")
    
    (options, args) = parser.parse_args(sys.argv[1:])    
    
    # can't write sqlite3 to stdout (at least, not easily)
    if not options.output_path:
        if options.output_format == "sqlite3":
            sys.stderr.write("Must supply an output path for SQLite3\n")
            parser.print_help(file=sys.stderr)
            exit(1) 
        else:
            # either no format given or no output path given; in either case, this requires a plist format
            options.output_format = "plist"
            options.output_path = sys.stdout

    if not options.output_format:
        dot_idx = options.output_path.rfind(".") + 1
        if dot_idx != -1:
            options.output_format = options.output_path[dot_idx:]
            if options.output_format not in ("sqlite3", "plist"):
                sys.stderr.write("Unable to guess output format from extension .%s\n" % (options.output_format))
                parser.print_help(file=sys.stderr)
                exit(1)
        else:
            sys.stderr.write("Must supply an output format or known output path extension\n")
            parser.print_help(file=sys.stderr)
            exit(1)

    # "/usr/local/texlive/2011/tlpkg/texlive.tlpdb"
    flat_tlpdb = open(args[0], "r") if len(args) else sys.stdin
    all_packages, index_map = packages_from_tlpdb(flat_tlpdb)
        
    if options.output_format == "sqlite3":
        _save_as_sqlite(all_packages, options.output_path)
    elif options.output_format == "plist":
        _save_as_plist(all_packages, options.output_path)
        
    # pkg = all_packages[index_map["00texlive.installation"]]
    # for dep in pkg.depends:
    #     if dep.startswith("opt_"):
    #         key, ignored, value = dep[4:].partition(":")
    #         print "%s = %s" % (key, value)
    # 

    
