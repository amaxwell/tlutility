#!/bin/sh

#  texdist_change_default.sh
#  TeX Live Utility
#
#  Created by Adam R. Maxwell on 04/30/15.
#

#    From Dick Koch on 17 Mar 2015:
#    One final thing. When actually selecting a distribution, it should only be
#    necessary to define one symbolic link. Such a link is shown below
#    when TeXLive-2013 is chosen.
#
#    /Library/Distributions/.DefaultTeX/Contents —> ../TeXLive-2013.texdist/Contents
#
#
#    Let me talk about the contents of ../TeXLive-2013.texdist/Contents/Programs.
#    This location contains five symbolic links:
#
#    i386
#    powerpc
#    ppc
#    x86_64
#    texbin
#
#    The first four point to paths to the corresponding binaries for that distribution.
#    The final texbin is a link to one of the first four, choosing the actual distribution.
#
#    I’d advise ignoring this, because the texbin link was set up at install time
#    to point to an appropriate binary. But you can dip into this if you want the
#    user to reselect the binaries (mainly to select x86 over universal-darwin).
#    However, it is an added complication, and for what?

DEFAULT_TEX_DIR="/Library/TeX/Distributions/.DefaultTeX"

# may be e.g. TeXLive-2014.texdist or TeXLive-2014-Basic.texdist
TEXDIST_NAME=`basename "$1"`

if [[ "$TEXDIST_NAME" = "" ]]; then
    echo "failed to pass texdist name" >&2
    exit 2
fi

cd "$DEFAULT_TEX_DIR"

if ! [[ $? = 0 ]]; then
    echo "failed to change directory" >&2
    exit 3
fi

REL_PATH=../$TEXDIST_NAME/Contents

if ! [[ -d "$REL_PATH" ]]; then
    echo "$DEFAULT_TEX_DIR/$REL_PATH does not exist" >&2
    exit 4
fi

rm -f Contents
ln -s "$REL_PATH" Contents

if ! [[ $? = 0 ]]; then
    echo "failed to change symlink $DEFAULT_TEX_DIR/Contents --> $REL_PATH" >&2
    exit 5
fi

exit 0
