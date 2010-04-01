#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

from math import floor
import os

class DTProgress(object):
    """Drive progress indicator for DataTank.
    
    Call update_percentage periodically to get correct progress bar
    timing during a long-running external program.  The implementation
    creates a file called DTProgress in the current working directory.
    
    http://www.visualdatatools.com/phpBB2/viewtopic.php?t=158
    
    """
            
    def __init__(self):
        super(DTProgress, self).__init__()
        self._current_length = 0
        # save this in case a client changes CWD
        self._path = os.path.join(os.getcwdu(), "DTProgress")
        
    def update_percentage(self, percent):
        """Updates the progress indicator if needed.
        
        Only updates the progress file on integral percentage points, so
        can be called as frequently as needed.
        
        """
        
        new_length = int(floor(percent * 100 + 0.5))
        if self._current_length < new_length:
                        
            # The only difference from DTSource is that we open and close the
            # file here instead of keeping it open, so we can ensure that it's
            # cleaned up properly.
            mode = "w" if self._current_length == 0 else "a"
            with open(self._path, mode) as pfile:
                # write a single character to the file for each percentage point
                while self._current_length < new_length:
                    pfile.write("x")
                    self._current_length += 1
        
                assert self._current_length == new_length
                pfile.flush()

if __name__ == '__main__':
    
    progress = DTProgress()
    for idx in xrange(300):
        progress.update_percentage(idx / 300.)
    
    assert os.path.getsize("DTProgress") == 100
