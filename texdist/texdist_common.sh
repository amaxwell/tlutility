#!/bin/bash

# create the texdist structure

YEAR=$1

if [[ "$YEAR" = "" ]]; then
    echo "failed to pass year argument" >&2
    exit 1
fi

# Finally, construct the TeX Distribution data structure. Start with the key link

# First, set up /usr/texbin for the modern Pref Panel

if [[ ( !  -L /usr/texbin ) && ( -d /usr/texbin ) && ( -e /usr/texbin/tex ) ]]; then
	rm -R /usr/texbin
fi

if [[ -L /usr/texbin ]]; then
	 rm /usr/texbin
fi

if [[ `/usr/bin/uname -r | /usr/bin/cut -f 1 -d .` -lt 13 ]]; then
	ln -fhs /Library/TeX/Distributions/.DefaultTeX/Contents/Programs/texbin /usr/texbin
else
	ln -fhs ../Library/TeX/Distributions/Programs/texbin /usr/texbin
fi

# Set up /Library/TeX

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

if [[ ! -d /Library/TeX/Distributions/Programs ]]; then
	mkdir /Library/TeX/Distributions/Programs
	ln -s ../.DefaultTeX/Contents/Programs/texbin /Library/TeX/Distributions/Programs/texbin
fi

if [[ ! -e /Library/TeX/Distributions/TeXDist-description.rtf ]]; then
	cp ./TeXDist-description.rtf /Library/TeX/Distributions/TeXDist-description.rtf
	chmod 644 /Library/TeX/Distributions/TeXDist-description.rtf
fi

# postinstall does some stuff with /usr/local/bin/texdist here that
# I've omitted

if [[ ! -d /Library/TeX/Distributions/.DefaultTeX ]]; then
    mkdir /Library/TeX/Distributions/.DefaultTeX
fi 

# /Library/TeX/Distributions/.DefaultTeX/Contents will become a link to the Contents
# folder of the active distribution. Make TeXLive-$YEAR that active distribution
# These are symbolic links, so the linked material will be created later on.

if [[  -L /Library/TeX/Distributions/.DefaultTeX/Contents ]]; then
	rm /Library/TeX/Distributions/.DefaultTeX/Contents
fi

if [[ !  -e /Library/TeX/Distributions/.DefaultTeX/Contents ]]; then
	ln -s  ../TeXLive-$YEAR.texdist/Contents /Library/TeX/Distributions/.DefaultTeX/Contents
fi

# We first create .FactoryDefaults where the interesting data lives. We usually write data there
# only if it doesn't already exist. But we will rewrite the data for our own distribution.

if [[ ! -d /Library/TeX/Distributions/.FactoryDefaults ]]; then
	mkdir /Library/TeX/Distributions/.FactoryDefaults
fi

if [[ -d /Library/TeX/Distributions/.FactoryDefaults/TeXLive-$YEAR ]]; then
	rm -R /Library/TeX/Distributions/.FactoryDefaults/TeXLive-$YEAR
fi

# Next we create links to the main data in .Factory Defaults

if [[ ! -d /Library/TeX/Distributions/TeXLive-$YEAR.texdist ]]; then
	mkdir -p /Library/TeX/Distributions/TeXLive-$YEAR.texdist
	ln -s ../.FactoryDefaults/TeXLive-$YEAR/Contents /Library/TeX/Distributions/TeXLive-$YEAR.texdist/Contents
fi
