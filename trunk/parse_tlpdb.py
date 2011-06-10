#!/usr/bin/env python

import sys, os
import objc
from Foundation import NSBundle, NSURL

if __name__ == '__main__':

    bundle_path = sys.argv[1]

    bundle = NSBundle.bundleWithPath_(bundle_path)
    if not bundle:
        sys.stderr.write("Failed to load bundle %s\n" % (bundle_path))
        exit(1)

    TLMDatabasePackage = objc.lookUpClass("TLMDatabasePackage")
    if not TLMDatabasePackage:
        sys.stderr.write("Failed to find class TLMDatabasePackage\n")
        exit(1)

    TLMDatabase = objc.lookUpClass("TLMDatabase")
    if not TLMDatabase:
        sys.stderr.write("Failed to find class TLMDatabase\n")
        exit(1)

class TLMPyDatabasePackage(TLMDatabasePackage):
    """TeX Live Package"""
    
    @classmethod
    def packagesFromDatabaseAtPath_(self, dbpath):
        all_packages = None
        with open(dbpath, "r") as flat_tlpdb:
            all_packages, index_map = packages_from_tlpdb(flat_tlpdb)

        return all_packages
        
    def packagesFromDatabaseWithPipe_(self, nspipe):
        all_packages = None
        
        with os.fdopen(nspipe.fileHandleForReading().fileDescriptor(), "r") as flat_tlpdb:
            all_packages, index_map = packages_from_tlpdb(flat_tlpdb)

        return all_packages
        
    def description(self):
        return str(self)
        
    def dealloc(self):
        sys.stderr.write("dealloc %s\n" % (self._name))
        
    # subclass of NSObject, so override -[NSObject init]
    def init(self):
        self = super(TLMPyDatabasePackage, self).init()
        if self is None: return None
        
        self._name = None
        self._category = None
        self._shortdesc = None
        self._longdesc = None
        self._catalogue = None
        self._relocated = 0
    
        self._runfiles = []
        self._runsize = None
    
        self._srcfiles = []
        self._srcsize = None
    
        self._docfiles = []
        self._docsize = None
    
        # maps keys (doc filenames) to maps of attributes (details, language)
        self._docfiledata = {}
    
        self._executes = []
        self._postactions = []
    
        # maps keys (arch name) to lists of files
        self._binfiles = {}
        # maps keys (arch name) to integer size
        self._binsize = {}
    
        self._depends = []
        self._revision = None
    
        self._cataloguedata = {}
    
        self._extradata = {}
        
        return self
        
    def name(self):
        return self._name

    def category(self):
        return self._category

    def shortDescription(self):
        return self._shortdesc

    def longDescription(self):
        return self._longdesc

    def catalogue(self):
        return self._catalogue

    def relocated(self):
        return self._relocated

    def runFiles(self):
        return self._runfiles

    def sourceFiles(self):
        return self._srcfiles

    def docFiles(self):
        return self._docfiles

    def revision(self):
        return self._revision

    def add_pair(self, key, value):
        self._extradata[key] = value
        
    def __str__(self):
        return repr(self)
        
    def __repr__(self):
        s = "%s: %s\n  srcsize=%s\n  srcfiles=%s" % (self._name, self._shortdesc, self._srcsize, self._srcfiles)
        s += "\n  binsize = %s\n  binfiles = %s" % (self._binsize, self._binfiles)
        s += "\n  docsize = %s\n  docfiles = %s\n  docfiledata = %s" % (self._docsize, self._docfiles, self._docfiledata)
        s += "\n  runsize = %s\n  runfiles = %s" % (self._runsize, self._runfiles)
        s += "\n  depends = %s" % (self._depends)
        s += "\n  longdesc = %s" % (self._longdesc)
        s += "\n  cataloguedata = %s" % (self._cataloguedata)
        for k in self._extradata:
            s += "\n  %s = %s" % (k, self._extradata[k])
        return s
        
    def insert_in_packages(self, conn):
        c = conn.cursor()
        c.execute("""INSERT into packages values (?,?,?,?,?,?)""", (self._name, self._category, self._revision, self._shortdesc, self._longdesc, self._runfiles))
        conn.commit()

def _attributes_from_line(line):
    # arch=x86_64-darwin size=1
    # details="Package introduction" language="de"
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
                
    package = None
    package_index = 0
    all_packages = []
    index_map = {}
    last_key = None
    last_arch = None

    for line in flat_tlpdb:
                
        line = line.strip("\r\n")
    
        if len(line) == 0:
            all_packages.append(package)
            index_map[package._name] = package_index
            
            package_index += 1
            package = None
            last_key = None
            last_arch = None
        else:
            
            # the first space token is a delimiter
            key, ignored, value = line.partition(" ")
                            
            if package == None:
                assert key == "name", "first line must be a name: %s" % (line)
                package = TLMPyDatabasePackage.new()
        
            line_has_key = True
            if len(key) == 0:
                key = last_key
                line_has_key = False
                        
            if key == "name":
                package._name = value
            elif key == "category":
                package._category = value
            elif key == "revision":
                package._revision = int(value)
            elif key == "relocated":
                package._relocated = int(value)
            elif key == "shortdesc":
                package._shortdesc = value.decode("utf-8")
            elif key == "longdesc":
                oldvalue = "" if package._longdesc == None else package._longdesc
                package._longdesc = oldvalue + " " + value.decode("utf-8")
            elif key == "depend":
                package._depends.append(value)
            elif key == "catalogue":
                package._catalogue = value
            elif key.startswith("catalogue-"):
                catkey = key[len("catalogue-"):]
                package._cataloguedata[catkey] = value
            elif key == "srcfiles":
                if line_has_key:
                    attrs = _attributes_from_line(value)
                    assert "size" in attrs, "missing size for %s : %s" % (package._name, key)
                    package._srcsize = int(attrs["size"])
                else:
                    package._srcfiles.append(value)
            elif key == "binfiles":
                if line_has_key:
                    attrs = _attributes_from_line(value)
                    assert "arch" in attrs, "missing arch for %s : %s" % (package._name, key)
                    last_arch = attrs["arch"]
                    assert "size" in attrs, "missing size for %s : %s" % (package._name, key)
                    package._binsize[last_arch] = int(attrs["size"])
                else:
                    oldvalue = package._binfiles[last_arch] if last_arch in package._binfiles else []
                    oldvalue.append(value)
                    package._binfiles[last_arch] = oldvalue
            elif key == "docfiles":
                if line_has_key:
                    attrs = _attributes_from_line(value)
                    assert "size" in attrs, "missing size for %s : %s" % (package._name, key)
                    package._docsize = int(attrs["size"])
                else:
                    values = value.split(" ")
                    if len(values) > 1:
                        package._docfiledata[values[0]] = _attributes_from_line(" ".join(values[1:]))
                    package._docfiles.append(values[0])
            elif key == "runfiles":
                if line_has_key:
                    attrs = _attributes_from_line(value)
                    assert "size" in attrs, "missing size for %s : %s" % (package._name, key)
                    package._runsize = int(attrs["size"])
                else:
                    package._runfiles.append(value)
            elif key == "postaction":
                package._postactions.append(value)
            elif key == "execute":
                package._executes.append(value)
            else:
                package.add_pair(key, value)
                #assert False, "unhandled line %s" % (line)
                
            last_key = key

    return all_packages, index_map
