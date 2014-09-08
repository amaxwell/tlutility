#!/bin/bash

# postflight script for the MacTeX installer

PKG_PATH=$1

# adjust /usr/local/bin permissions

# if [[ -d /usr/local ]]; then
# 	chmod a+rx /usr/local
# fi


# Adjust PATH and MANPATH

# Much of this code was copied from Gerben Wierda long ago.
# Later, Leopard provided more convenient ways to modify the
# PATH, and this is reflected below. The code has not been touched
# since Leopard.

# add path setup code to /etc/profile and /etc/csh.login
# and man setup code to /etc/manpath.config (for 10.3) or
# /usr/share/misc/man.conf (for 10.4 and higher)

manpath="/Library/TeX/Distributions/.DefaultTeX/Contents/Man"
binpath="/usr/texbin"

# if [[ `/usr/bin/uname -r | /usr/bin/cut -f 1 -d .` -lt 9 ]]; then
# 	"${PKG_PATH}"/Contents/Resources/setloginpath $binpath TeX
# 	"${PKG_PATH}"/Contents/Resources/setmanpath "MANPATH $manpath" TeX
# 	"${PKG_PATH}"/Contents/Resources/setmanpath  "MANPATH_MAP $binpath $manpath" TeXMap 
# fi

# in Leopard, add elements to path and manpath

if [[ ( `/usr/bin/uname -r | /usr/bin/cut -f 1 -d .` -gt 8 ) && (  -d /etc/paths.d ) ]]; then
 	cp -n -X ./TeXPath /etc/paths.d/TeX
 	chown root /etc/paths.d/TeX
 	chgrp wheel /etc/paths.d/TeX
	chmod 644 /etc/paths.d/TeX 
fi

if [[ ( `/usr/bin/uname -r | /usr/bin/cut -f 1 -d .` -gt 8 ) && (  -d /etc/manpaths.d ) ]]; then
 	cp -n -X ./TeXManPath /etc/manpaths.d/TeX
 	chown root /etc/manpaths.d/TeX
 	chgrp wheel /etc/manpaths.d/TeX
	chmod 644 /etc/manpaths.d/TeX
fi

# in Leopard, if /etc/profile or /etc/csh.login do NOT contain a call to path_helper, then use the old modifications
# don't do this in Snow Leopard

if [[ ( `/usr/bin/uname -r | /usr/bin/cut -f 1 -d .` -eq 9 ) ]]; then
if [[ ( -e /etc/profile ) && ( $( grep -c '^[^#]*eval `/usr/libexec/path_helper -s`' /etc/profile ) = 0 ) ]]; then
	./setloginpath $binpath TeX
fi
if [[ ( -e /etc/csh.login ) && ( $( grep -c '^[^#]*eval `/usr/libexec/path_helper -c`' /etc/csh.login ) = 0 ) ]]; then
	./setloginpath $binpath TeX
fi
fi



# Add /usr/local/texlive/texmf-local if completely absent

if [[ ! -d /usr/local/texlive/texmf-local ]]; then
	mkdir /usr/local/texlive/texmf-local
	mkdir /usr/local/texlive/texmf-local/bibtex
	mkdir -p /usr/local/texlive/texmf-local/bibtex/bib/local
	mkdir -p /usr/local/texlive/texmf-local/bibtex/bst/local
	mkdir -p /usr/local/texlive/texmf-local/dvips/local
	mkdir /usr/local/texlive/texmf-local/fonts
	mkdir -p /usr/local/texlive/texmf-local/fonts/source/local
	mkdir -p /usr/local/texlive/texmf-local/fonts/tfm/local
	mkdir -p /usr/local/texlive/texmf-local/fonts/type1/local
	mkdir -p /usr/local/texlive/texmf-local/fonts/vf/local
	mkdir -p /usr/local/texlive/texmf-local/metapost/local
	mkdir /usr/local/texlive/texmf-local/tex
	mkdir -p /usr/local/texlive/texmf-local/tex/latex/local
	mkdir -p /usr/local/texlive/texmf-local/tex/plain/local
	mkdir /usr/local/texlive/texmf-local/web2c
	chmod -R 755 /usr/local/texlive/texmf-local
fi




# Set the default paper size according to the user's preference.

# The install package is constructed in the US, and default paper size is "letter".  Note that
# resetting paper size also rebuilds formats.  So MacTeX will make formats for most users.
# The lucky few who avoid that step are running Intel machines and using letter paper; they use the
# prebuilt formats.


# PAPER=`sudo -u $USER defaults read com.apple.print.PrintingPrefs DefaultPaperID | perl -pe 's/^iso-//; s/^na-//'`

PAPER=$(sudo -u $USER /usr/bin/python -c 'from AppKit import NSPrintInfo; import sys; sys.stdout.write(NSPrintInfo.sharedPrintInfo().paperName().split("-")[-1])')


PROCESSOR=`/usr/bin/uname -p`

PATH=/usr/local/texlive/2014/bin/universal-darwin:$PATH; export PATH

echo "### setting default paper size $PAPER"

if [[ "$PAPER" == "a4" ]]; then 
	/usr/local/texlive/2014/bin/universal-darwin/tlmgr paper $PAPER
fi



# Formats were made on Intel; a few are different on PPC. Notice that powerpc users
# who have a4 paper have already rebuilt these formats, but the script author is lazy.

# if [[ "$PROCESSOR" == "powerpc" ]]; then
#  	/usr/local/texlive/2014/bin/universal-darwin/fmtutil-sys --byengine mpost
# fi

# if [[ "$PROCESSOR" == "powerpc" ]]; then
# 	/usr/local/texlive/2014/bin/universal-darwin/fmtutil-sys --byengine luatex
# fi



# Finally, construct the TeX Distribution data structure. Start with the key link

# First, set up /usr/texbin for the modern Pref Panel

if [[ ( !  -L /usr/texbin ) && ( -d /usr/texbin ) && ( -e /usr/texbin/tex ) ]]; then
	rm -R /usr/texbin
fi

if [[ -L /usr/texbin ]]; then
	 rm /usr/texbin
fi

# NEW STUFF


if [[ `/usr/bin/uname -r | /usr/bin/cut -f 1 -d .` -lt 13 ]]; then
	ln -fhs /Library/TeX/Distributions/.DefaultTeX/Contents/Programs/texbin /usr/texbin
else
	ln -fhs ../Library/TeX/Distributions/Programs/texbin /usr/texbin
fi

# Next install the Preference Pane, but only do that if there is no existing pane, or if
# the existing pane is older than the pane being installed.

if [[ `/usr/bin/uname -r | /usr/bin/cut -f 1 -d .` -lt 13 ]]; then
	rm -R /Library/PreferencePanes/TeXDistPrefPane2-Temp.prefPane
	if [[  -e /Library/PrerencePanes/TeXDistPrefPane.prefPane ]]; then
		rm -R /Library/PreferencePanes/TeXDistPrefPane.prefPane
	fi
	cp -pRP /Library/PreferencePanes/TeXDistPrefPane-Temp.prefPane /Library/PreferencePanes/TeXDistPrefPane.prefPane
	rm -R /Library/PreferencePanes/TeXDistPrefPane-Temp.prefPane
else
	rm -R /Library/PreferencePanes/TeXDistPrefPane-Temp.prefPane
	if [[ ! -e /Library/PreferencePanes/TeXDistPrefPane.prefPane ]]; then
		cp -pRP /Library/PreferencePanes/TeXDistPrefPane2-Temp.prefPane /Library/PreferencePanes/TeXDistPrefPane.prefPane
		rm -R /Library/PreferencePanes/TeXDistPrefPane2-Temp.prefPane
	else
		EXISTVERSION=`/Library/PreferencePanes/TeXDistPrefPane.prefPane/Contents/MacOS/GetSourceVersion`
		INSTALLVERSION=`/Library/PreferencePanes/TeXDistPrefPane2-Temp.prefPane/Contents/MacOS/GetSourceVersion`
		if [[ "$EXISTVERSION" -gt "$INSTALLVERSION" ]]; then
			rm -R  /Library/PreferencePanes/TeXDistPrefPane2-Temp.prefPane
		else
			rm -R  /Library/PreferencePanes/TeXDistPrefPane.prefPane
			cp -pRP /Library/PreferencePanes/TeXDistPrefPane2-Temp.prefPane /Library/PreferencePanes/TeXDistPrefPane.prefPane
			rm -R /Library/PreferencePanes/TeXDistPrefPane2-Temp.prefPane
		fi
	fi
fi

# END OF NEW STUFF

	

# create the texdist structure

if [[ ! -d /Library/TeX ]]; then
	mkdir /Library/TeX
fi

 if [[ ! -d /Library/TeX/.scripts ]]; then
 	mkdir /Library/TeX/.scripts
 	cp ./texdist /Library/TeX/.scripts/texdist
 	chmod 755 /Library/TeX/.scripts/texdist
 fi

if [[ -L /Library/TeX/Documentation ]]; then
	rm /Library/TeX/Documentation
fi

if [[ ! -e /Library/TeX/Documentation ]]; then
	ln -s Distributions/.DefaultTeX/Contents/Doc /Library/TeX/Documentation 
fi

if [[ -L /Library/TeX/Root ]]; then
	rm /Library/TeX/Root
fi

if [[ ! -e /Library/TeX/Root ]]; then
	ln -s Distributions/.DefaultTeX/Contents/Root /Library/TeX/Root
fi

if [[ -L /Library/TeX/Local ]]; then
	rm /Library/TeX/Local
fi

if [[ ! -e /Library/TeX/Local ]]; then
	ln -s Distributions/.DefaultTeX/Contents/TexmfLocal /Library/TeX/Local
fi

if [[ ! -d /Library/TeX/Distributions ]]; then
	mkdir /Library/TeX/Distributions
fi

# NEW STUFF

if [[ ! -d /Library/TeX/Distributions/Programs ]]; then
	mkdir /Library/TeX/Distributions/Programs
	ln -s ../.DefaultTeX/Contents/Programs/texbin /Library/TeX/Distributions/Programs/texbin
fi

# END OF NEW STUFF


if [[ ! -e /Library/TeX/Distributions/TeXDist-description.rtf ]]; then
	cp ./TeXDist-description.rtf /Library/TeX/Distributions/TeXDist-description.rtf
	chmod 644 /Library/TeX/Distributions/TeXDist-description.rtf
fi

 if [[  -L /usr/local/bin/texdist ]]; then
 	rm /usr/local/bin/texdist
 fi

 if [[ ! -d /usr/local/bin ]]; then
	mkdir /usr/local/bin
 fi

 if [[ ! -e /usr/local/bin/texdist ]]; then
 	ln -s /Library/TeX/.scripts/texdist /usr/local/bin/texdist
 fi

if [[ ! -d /Library/TeX/Distributions/.DefaultTeX ]]; then
	mkdir /Library/TeX/Distributions/.DefaultTeX
fi 


# /Library/TeX/Distributions/.DefaultTeX/Contents will become a link to the Contents
# folder of the active distribution. Make TeXLive-2014 that active distribution
# These are symbolic links, so the linked material will be created later on.

if [[  -L /Library/TeX/Distributions/.DefaultTeX/Contents ]]; then
	rm /Library/TeX/Distributions/.DefaultTeX/Contents
fi

if [[ !  -e /Library/TeX/Distributions/.DefaultTeX/Contents ]]; then
	ln -s  ../TeXLive-2014.texdist/Contents /Library/TeX/Distributions/.DefaultTeX/Contents
fi


# Now we come to the key data defining the various TeX distributions which can occur.
# It is legal to install this data even if the actual distribution isn't available, because the
# Preference Pane checks to make sure the links point somewhere before using them.

# MacTeX installs this data for itself, and for the TeX distributions in Fink and MacPorts.
# This last data is provided because Fink and MacPorts don't install the data and yet
# some users install those distributions.

# MacTeX-2014 only installs data for 2014, and not for other years. 

# The TeX Distribution data is much more elaborate than necessary because Jerome
# Laurens and Gerben Wierda thought of other uses of the data, which front ends haven't
# yet implemented.

# For mysterious reasons, each actual distribution occurs twice. Take for example TeXLive-2014.
# In /Library/TeX/Distributions, there is a folder named TeXLive-2014.texdist. But there is also
# a hidden folder of distributions, /Library/TeX/Distributions/.FactoryDefaults, and this folder
# contains a folder TeXLive-2014 as well. Notice that the first name has an extension and the
# second does not.

# The TeXLive-2014 folder in .FactoryDefaults contains a subfolder named Contents. The
# TeXLive-2014.texdist folder in Distributions contains an item named Contents, but this
# item is a symbolic link to the Contents folder in TeXLive-2014. Aside from this element,
# TeXLive-2014.texdist is empty. All of the interesting links are in
# .FactoryDefaults/TeXLive-2014/Contents

# This strange design was required so icons could be assigned to the various distributions,
# but that was never carried out. The extra complications now have no purpose, but they take
# almost no disk space and the only people noticing them are people reading these comments!

# All the items of interest are in /Library/TeX/Distributions/.FactoryDefaults/Contents
# Many of these items are there for future use and aren't currently used by software. The key
# subfolder of Contents for us is named Programs. It contains four links titled i386, ppc, powerpc,
# and x86_64. Each is a link to the actual binary directory of the distribution of indicated type.
# Some of these links might be missing for other distributions, but for TeXLive-2014, the
# links i386, ppc, and powerpc all point to universal-darwin, and x86_64 points to x86_64-darwin.
# Incidentally, ppc and powerpc will usually point to the same place; this link is duplicated for
# historical reasons.

# Programs also contains a symbolic link named texdist which points to one of the links
# just described. The Preference Pane may reset this link. For instance, the drop down panel
# allowing the user to choose 32 or 64 bit binaries resets the texdist link.

# There is one other key item. Although Leopard can run 64 bit programs, the TeX Live 64 bit
# programs are compiled on Snow Leopard and require that operating system. Jerome Laurens has
# provided a mechanism for handling that situation. On Mac OS X, the Contents directory can contain
# an Info.plist file. Jerome defined such a plist file which lives the minimal operating version which
# can run particular binaries. This would allow us in the future to compile the 64 bit binaries on Lion
# or another advanced system.

# We first create .FactoryDefaults where the interesting data lives. We usually write data there
# only if it doesn't already exist. But we will rewrite the data for our own distribution.

if [[ ! -d /Library/TeX/Distributions/.FactoryDefaults ]]; then
	mkdir /Library/TeX/Distributions/.FactoryDefaults
fi

if [[ -d /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014 ]]; then
	rm -R /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014
fi

# Next we create links to the main data in .Factory Defaults

if [[ ! -d /Library/TeX/Distributions/TeXLive-2014.texdist ]]; then
	mkdir -p /Library/TeX/Distributions/TeXLive-2014.texdist
	ln -s ../.FactoryDefaults/TeXLive-2014/Contents /Library/TeX/Distributions/TeXLive-2014.texdist/Contents
fi

if [[ ! -d /Library/TeX/Distributions/MacPorts-teTeX.texdist ]]; then
	mkdir -p /Library/TeX/Distributions/MacPorts-teTeX.texdist
	ln -s ../.FactoryDefaults/MacPorts-teTeX/Contents /Library/TeX/Distributions/MacPorts-teTeX.texdist/Contents
fi

if [[ ! -d /Library/TeX/Distributions/MacPorts-TeXLive.texdist ]]; then
	mkdir -p /Library/TeX/Distributions/MacPorts-TeXLive.texdist
	ln -s ../.FactoryDefaults/MacPorts-TeXLive/Contents /Library/TeX/Distributions/MacPorts-TeXLive.texdist/Contents
fi

if [[ ! -d /Library/TeX/Distributions/Fink-teTeX.texdist ]]; then
	mkdir -p /Library/TeX/Distributions/Fink-teTeX.texdist
	ln -s ../.FactoryDefaults/Fink-teTeX/Contents /Library/TeX/Distributions/Fink-teTeX.texdist/Contents
fi


# At last! Here's the data!

if [[ ! -d /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014 ]]; then
	mkdir -p  /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/AllTexmf
	mkdir -p /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Doc
	mkdir -p /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Programs
	mkdir -p /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Resources
	mkdir -p /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Resources/English.lproj
	cp ./TeXDistVersion  /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/TeXDistVersion
	chmod 644 /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/TeXDistVersion
	cp ./Description.rtf  /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Resources/English.lproj/Description.rtf
	chmod 644  /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Resources/English.lproj/Description.rtf
	ln -s ../../../../../../usr/local/texlive/2014/texmf-dist/doc/info /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Info
	ln -s ../../../../../../usr/local/texlive/2014/texmf-dist/doc/man /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Man
	ln -s ../../../../../../usr/local/texlive/2014 /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Root
	ln -s ../../../../../../usr/local/texlive/texmf-local /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/TexmfLocal
	ln -s ../../../../../../usr/local/texlive/2014/texmf-var /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/TexmfSysVar
	ln -s ../../../../../../../usr/local/texlive/2014/bin/universal-darwin /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Programs/i386
	ln -s ../../../../../../../usr/local/texlive/2014/bin/universal-darwin /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Programs/powerpc
	ln -s ../../../../../../../usr/local/texlive/2014/bin/universal-darwin /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Programs/ppc
	ln -s ../../../../../../../usr/local/texlive/2014/bin/x86_64-darwin /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Programs/x86_64
	ln -s ../../../../../../../usr/local/texlive/2014/texmf-dist/doc /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Doc/texmf-dist-doc
	ln -s ../../../../../../../usr/local/texlive/2014/texmf-dist/doc /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Doc/texmf-doc
	ln -s ../../../../../../../usr/local/texlive/2014/texmf-dist/doc /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Doc/texmf-doc-doc
	ln -s ../../../../../../../usr/local/texlive/2014/texmf-dist/doc /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Doc/texmf-var-doc
	ln -s ../../../../../../../usr/local/texlive/2014/texmf-dist /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/AllTexmf/texmf
	ln -s ../../../../../../../usr/local/texlive/2014/texmf-dist /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/AllTexmf/texmf-dist
	ln -s ../../../../../../../usr/local/texlive/2014/texmf-dist/doc /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/AllTexmf/texmf-doc
	ln -s ../../../../../../../usr/local/texlive/2014/texmf-var /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/AllTexmf/texmf-var
	ln -s ../../../../../../../usr/local/texlive/texmf-local /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/AllTexmf/texmf-local
	if [[ "$PROCESSOR" == "powerpc" ]]; then
		echo "### setting program link powerpc"
		ln -s powerpc  /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Programs/texbin
	fi
	if [[ "$PROCESSOR" == "i386" ]]; then
		echo "### setting program link i386"
		ln -s i386  /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Programs/texbin
	fi
	cp ./PrefPane/Info.plist /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Info.plist
	chmod 644 /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Info.plist
fi

if [[ ! -d /Library/TeX/Distributions/.FactoryDefaults/MacPorts-teTeX ]]; then
	mkdir -p  /Library/TeX/Distributions/.FactoryDefaults/MacPorts-teTeX/Contents/AllTexmf
	mkdir -p /Library/TeX/Distributions/.FactoryDefaults/MacPorts-teTeX/Contents/Doc
	mkdir -p /Library/TeX/Distributions/.FactoryDefaults/MacPorts-teTeX/Contents/Programs
	cp ./TeXDistVersion  /Library/TeX/Distributions/.FactoryDefaults/MacPorts-teTeX/Contents/TeXDistVersion
	chmod 644  /Library/TeX/Distributions/.FactoryDefaults/MacPorts-teTeX/Contents/TeXDistVersion
	ln -s ../../../../../../opt/local/share/info /Library/TeX/Distributions/.FactoryDefaults/MacPorts-teTeX/Contents/Info
	ln -s ../../../../../../opt/local/share/man /Library/TeX/Distributions/.FactoryDefaults/MacPorts-teTeX/Contents/Man
	ln -s ../../../../../../opt/local/share /Library/TeX/Distributions/.FactoryDefaults/MacPorts-teTeX/Contents/Root
	ln -s ../../../../../../opt/local/share/texmf-local /Library/TeX/Distributions/.FactoryDefaults/MacPorts-teTeX/Contents/TexmfLocal
	ln -s ../../../../../../opt/local/share/texmf-local /Library/TeX/Distributions/.FactoryDefaults/MacPorts-teTeX/Contents/TexmfSysVar
	ln -s ../../../../../../../opt/local/bin /Library/TeX/Distributions/.FactoryDefaults/MacPorts-teTeX/Contents/Programs/i386
	ln -s ../../../../../../../opt/local/bin /Library/TeX/Distributions/.FactoryDefaults/MacPorts-teTeX/Contents/Programs/powerpc
	ln -s ../../../../../../../opt/local/bin /Library/TeX/Distributions/.FactoryDefaults/MacPorts-teTeX/Contents/Programs/ppc
	ln -s ../../../../../../../opt/local/share/texmf/doc /Library/TeX/Distributions/.FactoryDefaults/MacPorts-teTeX/Contents/Doc/texmf-doc
	ln -s ../../../../../../../opt/local/share/texmf-dist/doc /Library/TeX/Distributions/.FactoryDefaults/MacPorts-teTeX/Contents/Doc/texmf-dist-doc
	ln -s ../../../../../../../opt/local/share/texmf /Library/TeX/Distributions/.FactoryDefaults/MacPorts-teTeX/Contents/AllTexmf/texmf
	ln -s ../../../../../../../opt/local/share/texmf-dist /Library/TeX/Distributions/.FactoryDefaults/MacPorts-teTeX/Contents/AllTexmf/texmf.dist
	ln -s ../../../../../../../opt/local/share/texmf-local /Library/TeX/Distributions/.FactoryDefaults/MacPorts-teTeX/Contents/AllTexmf/texmf.local
	ln -s ../../../../../../../opt/local/share/texmf-var /Library/TeX/Distributions/.FactoryDefaults/MacPorts-teTeX/Contents/AllTexmf/texmf.var
	if [[ "$PROCESSOR" == "powerpc" ]]; then
		ln -s powerpc  /Library/TeX/Distributions/.FactoryDefaults/MacPorts-teTeX/Contents/Programs/texbin
	fi
	if [[ "$PROCESSOR" == "i386" ]]; then
		ln -s i386  /Library/TeX/Distributions/.FactoryDefaults/MacPorts-teTeX/Contents/Programs/texbin
	fi
fi

if [[ ! -d /Library/TeX/Distributions/.FactoryDefaults/MacPorts-TeXLive ]]; then
	mkdir -p  /Library/TeX/Distributions/.FactoryDefaults/MacPorts-TeXLive/Contents/AllTexmf
	mkdir -p /Library/TeX/Distributions/.FactoryDefaults/MacPorts-TeXLive/Contents/Doc
	mkdir -p /Library/TeX/Distributions/.FactoryDefaults/MacPorts-TeXLive/Contents/Programs
	cp ./TeXDistVersion  /Library/TeX/Distributions/.FactoryDefaults/MacPorts-TeXLive/Contents/TeXDistVersion
	chmod 644  /Library/TeX/Distributions/.FactoryDefaults/MacPorts-TeXLive/Contents/TeXDistVersion
	ln -s ../../../../../../opt/local/share/info /Library/TeX/Distributions/.FactoryDefaults/MacPorts-TeXLive/Contents/Info
	ln -s ../../../../../../opt/local/share/man /Library/TeX/Distributions/.FactoryDefaults/MacPorts-TeXLive/Contents/Man
	ln -s ../../../../../../opt/local/share /Library/TeX/Distributions/.FactoryDefaults/MacPorts-TeXLive/Contents/Root
	ln -s ../../../../../../opt/local/share/texmf-local /Library/TeX/Distributions/.FactoryDefaults/MacPorts-TeXLive/Contents/TexmfLocal
	ln -s ../../../../../../opt/local/var/db/texmf /Library/TeX/Distributions/.FactoryDefaults/MacPorts-TeXLive/Contents/TexmfSysVar
	ln -s ../../../../../../../opt/local/libexec/texlive/texbin /Library/TeX/Distributions/.FactoryDefaults/MacPorts-TeXLive/Contents/Programs/i386
	ln -s ../../../../../../../opt/local/libexec/texlive/texbin /Library/TeX/Distributions/.FactoryDefaults/MacPorts-TeXLive/Contents/Programs/powerpc
	ln -s ../../../../../../../opt/local/libexec/texlive/texbin /Library/TeX/Distributions/.FactoryDefaults/MacPorts-TeXLive/Contents/Programs/ppc
	ln -s ../../../../../../../opt/local/share/texmf-texlive/doc /Library/TeX/Distributions/.FactoryDefaults/MacPorts-TeXLive/Contents/Doc/texmf-doc
	ln -s ../../../../../../../opt/local/share/texmf-texlive-dist/doc /Library/TeX/Distributions/.FactoryDefaults/MacPorts-TeXLive/Contents/Doc/texmf-dist-doc
	ln -s ../../../../../../../opt/local/share/texmf /Library/TeX/Distributions/.FactoryDefaults/MacPorts-TeXLive/Contents/AllTexmf/texmf
	ln -s ../../../../../../../opt/local/share/texmf-texlive /Library/TeX/Distributions/.FactoryDefaults/MacPorts-TeXLive/Contents/AllTexmf/texmf-texlive
	ln -s ../../../../../../../opt/local/share/texmf-texlive-dist /Library/TeX/Distributions/.FactoryDefaults/MacPorts-TeXLive/Contents/AllTexmf/texmf-texlive-dist
	ln -s ../../../../../../../opt/local/share/texmf-local /Library/TeX/Distributions/.FactoryDefaults/MacPorts-TeXLive/Contents/AllTexmf/texmf-local
	ln -s ../../../../../../../opt/local/var/db//texmf /Library/TeX/Distributions/.FactoryDefaults/MacPorts-TeXLive/Contents/AllTexmf/texmf-var
	ln -s ../../../../../../../opt/local/etc/texmf /Library/TeX/Distributions/.FactoryDefaults/MacPorts-TeXLive/Contents/AllTexmf/texmf-etc
	if [[ "$PROCESSOR" == "powerpc" ]]; then
		ln -s powerpc  /Library/TeX/Distributions/.FactoryDefaults/MacPorts-TeXLive/Contents/Programs/texbin
	fi
	if [[ "$PROCESSOR" == "i386" ]]; then
		ln -s i386  /Library/TeX/Distributions/.FactoryDefaults/MacPorts-TeXLive/Contents/Programs/texbin
	fi
fi


 if [[ ! -d /Library/TeX/Distributions/.FactoryDefaults/Fink-teTeX ]]; then
	mkdir -p  /Library/TeX/Distributions/.FactoryDefaults/Fink-teTeX/Contents/AllTexmf
	mkdir -p /Library/TeX/Distributions/.FactoryDefaults/Fink-teTeX/Contents/Doc
	mkdir -p /Library/TeX/Distributions/.FactoryDefaults/Fink-teTeX/Contents/Programs
	cp ./TeXDistVersion  /Library/TeX/Distributions/.FactoryDefaults/Fink-teTeX/Contents/TeXDistVersion
	chmod 644  /Library/TeX/Distributions/.FactoryDefaults/Fink-teTeX/Contents/TeXDistVersion
	ln -s ../../../../../../sw/share/info /Library/TeX/Distributions/.FactoryDefaults/Fink-teTeX/Contents/Info
	ln -s ../../../../../../sw/share/man /Library/TeX/Distributions/.FactoryDefaults/Fink-teTeX/Contents/Man
	ln -s ../../../../../../sw/share /Library/TeX/Distributions/.FactoryDefaults/Fink-teTeX/Contents/Root
	ln -s ../../../../../../sw/share/texmf-local /Library/TeX/Distributions/.FactoryDefaults/Fink-teTeX/Contents/TexmfLocal
	ln -s ../../../../../../sw/share/texmf-local /Library/TeX/Distributions/.FactoryDefaults/Fink-teTeX/Contents/TexmfSysVar
	ln -s ../../../../../../../sw/bin /Library/TeX/Distributions/.FactoryDefaults/Fink-teTeX/Contents/Programs/i386
	ln -s ../../../../../../../sw/bin /Library/TeX/Distributions/.FactoryDefaults/Fink-teTeX/Contents/Programs/powerpc
	ln -s ../../../../../../../sw/bin /Library/TeX/Distributions/.FactoryDefaults/Fink-teTeX/Contents/Programs/ppc
	ln -s ../../../../../../../sw/share/texmf/doc /Library/TeX/Distributions/.FactoryDefaults/Fink-teTeX/Contents/Doc/texmf-doc
	ln -s ../../../../../../../sw/share/texmf-dist/doc /Library/TeX/Distributions/.FactoryDefaults/Fink-teTeX/Contents/Doc/texmf-dist-doc
	ln -s ../../../../../../../sw/share/texmf /Library/TeX/Distributions/.FactoryDefaults/Fink-teTeX/Contents/AllTexmf/texmf
	ln -s ../../../../../../../sw/share/texmf-dist /Library/TeX/Distributions/.FactoryDefaults/Fink-teTeX/Contents/AllTexmf/texmf-dist
	ln -s ../../../../../../../sw/share/texmf-local /Library/TeX/Distributions/.FactoryDefaults/Fink-teTeX/Contents/AllTexmf/texmf-local
	if [[ "$PROCESSOR" == "powerpc" ]]; then
		ln -s powerpc  /Library/TeX/Distributions/.FactoryDefaults/Fink-teTeX/Contents/Programs/texbin
	fi
	if [[ "$PROCESSOR" == "i386" ]]; then
		ln -s i386  /Library/TeX/Distributions/.FactoryDefaults/Fink-teTeX/Contents/Programs/texbin
	fi
 fi


# activate 64 bit data structure if machine is 64 bit capable and operating system is at least Snow Leopard

# Snow Leopard test
if [[ `/usr/bin/uname -r | /usr/bin/cut -f 1 -d .` -lt 10 ]]; then
 	exit 0 
fi

# 64 bit test
if [[ `/usr/sbin/sysctl hw.cpu64bit_capable | /usr/bin/cut -b 22` -lt 1 ]]; then
	exit 0
fi

# Activate 64 bits

rm  /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Programs/texbin
ln -s x86_64  /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Programs/texbin

exit 0

