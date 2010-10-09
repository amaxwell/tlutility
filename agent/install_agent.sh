#!/bin/sh

# always install here, since it's useful for any user
BIN_DIR="/Library/Application Support/TeX Live Utility"

# will install to one of these, depending on the -a flag
USER_PLIST_DIR=""
LOCAL_PLIST_DIR="/Library/LaunchAgents"

# default to local install
PLIST_DIR="$LOCAL_PLIST_DIR"

BIN_PATH="$BIN_DIR/update_check.py"

# passed in as arguments; should be absolute paths inside the app bundle
SRC_BIN_PATH=""
SRC_PLIST_PATH=""
DO_UNINSTALL=0

OWNER_ID="0"

SCRIPT_NAME=$(basename "$0")

#
# Three ways to set a time in the plist:
#
# /usr/libexec/PlistBuddy -c "Set :StartCalendarInterval:Hour 9 real" com.googlecode.mactlmgr.update_check.plist
#
# python -c 'from Foundation import NSDictionary; d=NSDictionary.dictionaryWithContentsOfFile_("com.googlecode.mactlmgr.update_check.plist"); d["StartCalendarInterval"]["Hour"]=9;d.writeToFile_atomically_("com.googlecode.mactlmgr.update_check.plist",True)'
#
# python -c 'from plistlib import readPlist, writePlist; plname="com.googlecode.mactlmgr.update_check.plist"; pl=readPlist(plname); pl["StartCalendarInterval"]["Hour"]=9;writePlist(pl, plname)'
#

usage()
{
    echo 'usage: install_agent -b binary_src_path -p plist_src_path [-h home_dir -o uid] [-u]' >&2
}

#
# -b: absolute path to update_check.py in the application bundle
# -p: absolute path to the launchd plist in the application bundle
# -u: uninstall launchd plist and update_check.py
# 
while getopts ":uh:b:p:o:" opt; do
    case $opt in
        b   )   SRC_BIN_PATH="$OPTARG" ;;
        p   )   SRC_PLIST_PATH="$OPTARG" ;;
        u   )   DO_UNINSTALL=1 ;;
        h   )   USER_PLIST_DIR="$OPTARG/$LOCAL_PLIST_DIR" ;;
        o   )   OWNER_ID="$OPTARG" ;;
        \?  )   usage
                exit 1 ;;
                
    esac
done
shift $(($OPTIND - 1))

function log_message
{
    echo "$SCRIPT_NAME: $1" >&2
}

if [ "$USER_PLIST_DIR" != "" ]; then
    PLIST_DIR="$USER_PLIST_DIR"
    if [ "$DO_UNINSTALL" = 0 ] && [ "$OWNER_ID" = "0" ]; then
        log_message "Owner ID not set, which is unsafe."
        exit 1
    fi
fi

do_uninstall_and_exit()
{
    exit_status=0
    
    # try to unload the launchd plist if it exists; this fails if it's not loaded
    # no action is taken if none of the files exist, and this is not an error
    
    plist_dirs=("$USER_PLIST_DIR" "$LOCAL_PLIST_DIR")
    for plist_dir in "${plist_dirs[@]}"; do

        plist_path="$plist_dir/com.googlecode.mactlmgr.update_check.plist"

        if [ -f "$plist_path" ]; then
            
            # Unload with launchctl, which doesn't like running as root to unload a non-root plist.
            # Since this tries to unload any plist that exists, use stat to figure
            # out the owner and ignore OWNER_ID since it will be wrong.
            
            owner_uid=$(/usr/bin/stat -f "%Uu" $plist_path)
            /usr/bin/sudo "-u#$owner_uid" /bin/launchctl unload -w "$plist_path"
            if [ $? != 0 ]; then
                log_message "unable to unload $plist_path"
                exit_status=10
            fi
            
            # remove the launchd plist only if it could be unloaded
            if [ $exit_status = 0 ]; then
                /bin/rm -f "$plist_path"
                if [ $? != 0 ]; then
                    log_message "unable to remove $plist_path"
                    exit_status=11
                else
                    log_message "removed $plist_path"
                fi
            fi
            
        else
            log_message "$plist_path not installed"
        fi

    done
    
    # remove the Python script
    if [ -f "$BIN_PATH" ]; then
        /bin/rm -f "$BIN_PATH"
        if [ $? != 0 ]; then
            log_message "unable to remove $BIN_PATH"
            exit_status=12
        else
            log_message "removed $BIN_PATH"
        fi
    else
        log_message "$BIN_PATH not installed"
    fi
    
    exit $exit_status
}

do_install_and_exit()
{
    # arguments are mandatory
    if [ "$SRC_BIN_PATH" = "" ] || [ "$SRC_PLIST_PATH" = "" ]; then
        usage
        exit 1
    fi

    #
    # fail immediately if either source path does not exist
    #
    
    if [ ! -f "$SRC_BIN_PATH" ]; then
        echo "$SRC_BIN_PATH does not exist"
        exit 2
    fi

    if [ ! -f "$SRC_PLIST_PATH" ]; then
        echo "$SRC_PLIST_PATH does not exist"
        exit 3
    fi

    # probably have to create /Library/Application Support/TeX Live Utility
    if [ ! -d "$BIN_DIR" ]; then
        /bin/mkdir -p "$BIN_DIR"
        if [ $? != 0 ]; then
            log_message "unable to create $BIN_DIR"
            exit 4
        fi
    fi

    # the OS should have created this already
    if [ ! -d "$PLIST_DIR" ]; then
        # don't create this as root in a user's directory
        /usr/bin/sudo "-u#$OWNER_ID" /bin/mkdir -p "$PLIST_DIR"
        if [ $? != 0 ]; then
            log_message "unable to create $PLIST_DIR as UID $OWNER_ID"
            exit 5
        else
            log_message "created $PLIST_DIR as UID $OWNER_ID"
        fi
    fi

    #
    # only copy if all else succeeded
    #

    /bin/cp "$SRC_BIN_PATH" "$BIN_DIR"
    if [ $? != 0 ]; then
        log_message "unable to copy $SRC_BIN_PATH to $BIN_DIR"
        exit 6
    fi

    /bin/cp "$SRC_PLIST_PATH" "$PLIST_DIR"
    if [ $? != 0 ]; then
        log_message "unable to copy $SRC_PLIST_PATH to $PLIST_DIR"
        exit 7
    fi
    
    plist_path="$PLIST_DIR/com.googlecode.mactlmgr.update_check.plist"
            
    # set the plist owner    
    log_message "changing ownership of $plist_path to $OWNER_ID"
    /usr/sbin/chown -v $OWNER_ID "$plist_path"
    if [ $? != 0 ]; then
        exit 8
    fi
    
    /usr/bin/sudo "-u#$OWNER_ID" /bin/launchctl unload -w "$plist_path" 2>/dev/null
    /usr/bin/sudo "-u#$OWNER_ID" /bin/launchctl load -w "$plist_path"
    if [ $? != 0 ]; then
        log_message "unable to load $plist_path"
        exit 9
    fi
    
    exit 0
}

if [ "$DO_UNINSTALL" -ne 0 ]; then
    do_uninstall_and_exit
else
    do_install_and_exit
fi
