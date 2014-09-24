#!/usr/bin/env python

import sys, os
sys.stdout.write("%s\n" % (sys.executable))
sys.stdout.write("%s\n" % (sys.version))
sys.stdout.write("%s\n" % " ".join(str(x) for x in sys.version_info))
if os.path.islink(sys.executable):
    sys.stderr.write("\n*** WARNING *** '%s' is a symlink to '%s'. Replacing the system python is not supported" % (sys.executable, os.path.realpath(sys.executable)))
major, minor = sys.version_info[0:2]
if major > 2:
    sys.stderr.write("\n*** WARNING *** Python scripts used by TeX Live Utility may not be compatible with Python %s.%s" % (major, minor))
