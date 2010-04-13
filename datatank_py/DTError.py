#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

import sys

_errors = []

def DTErrorMessage(fcn, msg):
    err_msg = "%s: %s" % (fcn, msg)
    _errors.append(err_msg)
    sys.stderr.write(err_msg + "\n")

def DTSaveError(datafile, name):
    if len(_errors):
        datafile[name] = _errors
