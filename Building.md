---
title: Building
layout: default
---

## Check out

In Terminal:

    git clone https://github.com/amaxwell/tlutility
    cd tlutility
    git submodule init
    git submodule update
 
to pull the necessary submodules.

## Compile

Open TeX Live Utility.xcodeproj and set the scheme to TeX Live Utility (Debug) or Release. It
should build on Mac OS X 10.8 and later.

You will have to create a code signing certificate named
"TeX Live Utility Signing Certificate." This is easily done using Keychain Access, or you
can hack the build process to use your own certificate. Note that signing is done in a shell
script build phase, since Xcode's signing was broken when I started developing the program.