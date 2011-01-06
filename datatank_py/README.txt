INSTALL

Create a symlink to the datatank_py directory, somewhere along the Python user path.  
On Mac OS X, this will be ~/Library/Python/2.6/site-packages for Python 2.6.  This
allows you to use DTDataFile with 

from datatank_py.DTDataFile import DTDataFile

in a Python source file located anywhere.  For install locations on Linux, you might
try `python -c 'import site; print site.USER_SITE'`, but you're on your own.

Some of the test scripts assume that various symlinks exist in datatank_py/examples.
This is mainly so I can test on multiple systems without hardcoding absolute paths.

REQUIREMENTS

- Operating System -

    DTDataFile has been tested with Python 2.5 and 2.6 on Mac OS X 10.5 and 10.6, and
    Python 2.5 on Red Hat Enterprise Linux 5 (64 bit).  Some of the examples may
    require Python 2.6, or inclusion of 

    from __future__ import with_statement

    before any other import statements for Python 2.5.

- NumPy -

    NumPy is a requirement, and I have no interest in working with Numeric or Numarray.
    You can download NumPy at http://numpy.scipy.org/ or make do with Apple's lobotomized
    and ancient version as shipped with OS X.  If you do compile your own, I've found it
    necessary to get rid of the OS-installed version, particularly since SciPy won't
    compile with it installed.  To do this, I use the following Terminal commands:

    cd /System/Library/Frameworks/Python.framework/Versions/2.6/Extras/lib/python
    sudo tar -czf numpy.apple.tgz numpy
    rm -r numpy

    This leaves you a backup of the system-installed NumPy, in case you ever want it.
    If there's a better way to handle this, please tell me.

- GDAL -

    Some of the examples require GDAL with Python bindings.  I find this invaluable
    for getting geospatial data into DataTank, even though the SWIG bindings seem like
    writing C++ using Python syntax.

    http://www.gdal.org/

- PIL -

    Some of the examples require PIL, the Python Imaging Library.  If you don't have 
    PIL installed, you should.

    http://www.pythonware.com/products/pil/

DOCUMENTATION

DTDataFile is extensively documented in the source, so help(DTDataFile) in an
interpreter should get you started.  There are a bunch of private methods and
functions that won't show up in pydoc, but they are documented so I don't forget
what they're supposed to do.

BUGS

Please e-mail me at amaxwell AT mac DOT com if you find any bugs in the Python
code, or have ideas on improvements.  I don't want to add the kitchen sink in, but
rather give users the building blocks to abuse DataTank in their own way.

LICENSE

DTDataFile.py and associated scripts are released under the BSD license as follows:

This software is Copyright (c) 2010-2011
Adam Maxwell. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

- Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.

- Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the following disclaimer in
the documentation and/or other materials provided with the
distribution.

- Neither the name of Adam Maxwell nor the names of any
contributors may be used to endorse or promote products derived
from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


