#!/usr/bin/env python

class Package(object):
    """TeX Live Package"""
    def __init__(self):
        super(Package, self).__init__()
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
        
    def insert_in_packages(self, conn):
        c = conn.cursor()
        c.execute("""INSERT into packages values (?,?,?,?,?,?)""", (self.name, self.category, self.revision, self.shortdesc, self.longdesc, self.runfiles))
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
                package = Package()
        
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
    
def convert_to_sqlite(packages):
    
    import sqlite3

    DB_PATH = "/tmp/texlive.sqlite3"

    def adapt_list(lst):
        return "\0".join(lst) if lst else None

    def convert_list(s):
        return s.split("\0") if s else None

    sqlite3.register_adapter(list, adapt_list)
    sqlite3.register_converter("list", convert_list)

    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
        
    conn = sqlite3.connect(DB_PATH, detect_types=sqlite3.PARSE_DECLTYPES)
    c = conn.cursor()
    c.execute("""CREATE table packages (name text, category text, revision real, shortdesc text, longdesc text, runfiles list)""")
    
    for pkg in packages:
        pkg.insert_in_packages(conn)
    
    conn.close()    

if __name__ == '__main__':
    
    import os
    
    with open("/usr/local/texlive/2011/tlpkg/texlive.tlpdb") as flat_tlpdb:
        all_packages, index_map = packages_from_tlpdb(flat_tlpdb)
        
        pkg = all_packages[index_map["00texlive.installation"]]
        for dep in pkg.depends:
            if dep.startswith("opt_"):
                key, ignored, value = dep[4:].partition(":")
                print "%s = %s" % (key, value)
        
    #exit(0)

    # for idx, pkg in enumerate(all_packages):
    #     
    #     if pkg.name == "achemso":
    #         break
    #     
    #     if idx % 4 == 0 or pkg.name == "a2ping":
    #         print pkg
    #         print ""