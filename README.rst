=============
WHAT IS THIS?
=============

TeX Live Utility is a Mac OS X graphical interface for TeX Live Manager. 
It aims to provide a native Mac OS X interface for the most commonly 
used functions of the TeX Live Manager command-line tool.

TeX Live 2008 and later come with the TeX Live Manager for updating, 
installing, and otherwise managing a TeX installation. It includes a 
cross-platform Perl/Tk graphical interface, and a command-line 
interface (tlmgr). The cross-platform Perl/Tk interface is less 
Mac-like, but provides access to more features.

Development is moving to GitHub, but the old
`Project page <https://code.google.com/p/mactlmgr/>`_ is still active.

===========
COMPILATION
===========

To check out:

* In Terminal: ``git clone https://github.com/amaxwell/tlutility``
* in the source directory, run::
      
    git submodule init   
    git submodule update

  to pull the necessary submodules.
* open ``TeX Live Utility.xcodeproj`` and set the scheme to
  ``TeX Live Utility (Debug)`` or release, and build it
* it should build in Xcode on 10.8 and later

=======
LICENSE
=======

TeX Live Utility and associated scripts are released under the BSD license as follows:

This software is Copyright (c) 2010-2014
Adam Maxwell. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

- Redistributions of source code must retain the above 
  copyright notice, this list of conditions and the following disclaimer.

- Redistributions in binary form must reproduce the above copyright 
  notice, this list of conditions and the following disclaimer in 
  the documentation and/or other materials provided with the distribution.

- Neither the name of Adam Maxwell nor the names of any contributors 
  may be used to endorse or promote products derived from this 
  software without specific prior written permission.

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


