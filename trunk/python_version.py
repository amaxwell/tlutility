#!/usr/bin/env python

import sys
sys.stdout.write("Using Python interpreter at '%s'\n" % (sys.executable))
sys.stdout.write("Python version: %s" % (sys.version))
major, minor = sys.version_info[0:2]
if major > 2:
    sys.stderr.write("\n*** WARNING *** Python scripts used by TeX Live Utility may not be compatible with Python %s.%s" % (major, minor))
