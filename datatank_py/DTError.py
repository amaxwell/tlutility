#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

__all__ = ["DTErrorMessage", "DTSaveError"]

import sys
import os

_errors = []

def DTErrorMessage(fcn, msg):
    """Accumulate a message and echo to standard error.
    
    Arguments:
    fcn -- typically a function or module name
    msg -- an error or warning message
    
    Returns:
    Nothing
    
    Typically you call this each time an error or warning
    should be presented, then call DTSaveError before exiting.
    
    """
    
    if fcn == None:
        fcn = os.path.basename(sys.argv[0])
    
    err_msg = "%s: %s" % (fcn, msg)
    _errors.append(err_msg)
    sys.stderr.write(err_msg + "\n")

def DTSaveError(datafile, name="ExecutionErrors"):
    """Save accumulated messages to a file.
    
    Arguments:
    datafile -- an open DTDataFile instance
    name -- defaults to "ExecutionErrors" for DataTank
    
    Returns:
    Nothing
    
    This will be displayed in DataTank's Messages panel.
    
    """
    
    if len(_errors):
        datafile.write_anonymous(_errors, name)
