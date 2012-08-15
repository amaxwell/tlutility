#!/bin/sh

#
# Uninstall the launchd agent from the local domain (/Library).
# Requires authorization to run, so rights must be acquired
# before calling the script.
#

PLIST_PATH="/Library/LaunchAgents/com.googlecode.mactlmgr.update_check.plist"
SCRIPT_PATH="/Library/Application Support/TeX Live Utility/update_check.py"

if [ -f "$PLIST_PATH" ]; then
    if /bin/launchctl unload -w -S Aqua "$PLIST_PATH" ; then
        echo "unloaded $PLIST_PATH" >&2
    else
        echo "failed to unload $PLIST_PATH" >&2
    fi
    
    if rm "$PLIST_PATH" ; then
        echo "removed $PLIST_PATH" >&2
    else
        echo "failed to remove $PLIST_PATH" >&2
    fi
else
    echo "no file at $PLIST_PATH" >&2
fi

if [ -f "$SCRIPT_PATH" ]; then
    if rm "$SCRIPT_PATH" ; then
        echo "removed $SCRIPT_PATH" >&2
    else
        echo "failed to remove $SCRIPT_PATH" >&2
    fi
else
    echo "no file at $SCRIPT_PATH" >&2
fi

