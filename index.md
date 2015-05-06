---
title: Getting Started
layout: default
---

## TeX Live Utility

TeX Live Utility is a Mac OS X graphical interface for [TeX Live Manager](http://www.tug.org/texlive/tlmgr.html).  It aims to provide a native Mac OS X interface for the most commonly used functions of the TeX Live Manager command-line tool.

[TeX Live](http://www.tug.org/texlive/) 2008 and later come with the [TeX Live Manager](http://www.tug.org/texlive/tlmgr.html) for updating, installing, and otherwise managing a TeX installation.  It includes a cross-platform [Perl/Tk](http://search.cpan.org/~srezic/Tk/) graphical interface, and a command-line interface (tlmgr).  The cross-platform Perl/Tk interface is less Mac-like, but provides access to more features.

## Functionality

The present subset of commands is as follows:

  * Set paper size for all TeX programs
  * Update packages (all or subset)
  * Install and remove packages (all or subset)
  * Show details for individual packages (including texdoc results)
  * Set a mirror URL for command-line tlmgr usage
  * List and restore backups

See (GettingStarted.html) for screenshots and more specific details.

## Why Use This?
Why use this program when you can use the command line tlmgr or the Perl/Tk GUI?  TeX Live Utility performs TeX Live infrastructure updates using the [Disaster Recovery script](http://www.tug.org/texlive/tlmgr.html), which avoids problems with tlmgr removing itself while updating.  TeX Live Utility also provides a native OS X user interface.  Beyond that, there's no compelling reason to switch from the command line or X11 GUI if you're comfortable with them.

## Requirements

  * Mac OS X Snow Leopard 10.6.8 or greater
  * [TeX Live](http://www.tug.org/texlive/) installed via [MacTeX](http://www.tug.org/mactex) or the standard Unix install


## Versioning Notes
TeX Live Utility 0.74 and earlier will work with TeX Live 2008 and 2009.  Current versions of TeX Live Utility require TeX Live 2009 or later.  Note that TeX Live 2008 and 2009 content has been removed from CTAN servers, so functionality with those releases will be limited.

If you are stuck using Mac OS X Leopard 10.5.7 (e.g, you are using a PowerPC system), you can use TeX Live Utility 1.03 or earlier.  Unfortunately, Apple made it too hard to keep supporting 10.5.

## Support
If you have a bug report or feature suggestion, please use the issue tracker (Issues tab on this page). There is also a [Mailing List](http://tug.org/mailman/listinfo/tlu) dedicated to discussion of TeX Live Utility where you can post questions, comments, or discuss ideas for development. Subscription isn't required if you just have a question; you can [email](mailto:tlu@tug.org) us directly.

## License
TeX Live Utility is free software, and released under the [BSD License](License.html)
