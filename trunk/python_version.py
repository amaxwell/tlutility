#!/usr/bin/env python

import sys, os
sys.stdout.write("Using Python interpreter at '%s'\n" % (sys.executable))
sys.stdout.write("Python version: %s\n" % (sys.version))
if os.path.islink(sys.executable):
    sys.stderr.write("\n*** WARNING *** '%s' is a symlink to '%s'. Replacing the system python is not supported" % (sys.executable, os.path.realpath(sys.executable)))
major, minor = sys.version_info[0:2]
if major > 2:
    sys.stderr.write("\n*** WARNING *** Python scripts used by TeX Live Utility may not be compatible with Python %s.%s" % (major, minor))
