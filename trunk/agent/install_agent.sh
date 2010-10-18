#!/bin/sh

# always install here, since it's useful for any user
BIN_DIR="/Library/Application Support/TeX Live Utility"

# will install to one of these, depending on the -h flag
USER_PLIST_DIR=""
LOCAL_PLIST_DIR="/Library/LaunchAgents"

# default to local install
PLIST_DIR="$LOCAL_PLIST_DIR"

BIN_PATH="$BIN_DIR/update_check.py"

# passed in as arguments; should be absolute paths inside the app bundle
SRC_BIN_PATH=""
SRC_PLIST_PATH=""

OWNER_ID="0"
USER_ID=""

SCRIPT_NAME=$(basename "$0")

usage()
{
    echo 'usage: install_agent -b binary_src_path -p plist_src_path [-h home_dir -o uid] -u uid' >&2
}

#
# -b: absolute path to update_check.py in the application bundle
# -p: absolute path to the launchd plist in the application bundle
# 
while getopts ":h:b:p:o:u:" opt; do
    case $opt in
        b   )   SRC_BIN_PATH="$OPTARG" ;;
        p   )   SRC_PLIST_PATH="$OPTARG" ;;
        h   )   USER_PLIST_DIR="$OPTARG$LOCAL_PLIST_DIR" ;;
        o   )   OWNER_ID="$OPTARG" ;;
        u   )   USER_ID="$OPTARG" ;;
        \?  )   usage
                exit 1 ;;
                
    esac
done
shift $(($OPTIND - 1))

function log_message
{
    echo "$SCRIPT_NAME: $1" >&2
}

# need to run launchctl as currently logged-in user
if [ "$USER_ID" == "" ]; then
    log_message "User id to load agent is not set."
    exit 1
fi

# if installing as a user, we have to make sure the owner is set also
if [ "$USER_PLIST_DIR" != "" ]; then
    PLIST_DIR="$USER_PLIST_DIR"
    if [ "$OWNER_ID" = "0" ]; then
        log_message "Owner ID not set, which is unsafe."
        exit 1
    fi
fi

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
    log_message "unable to change ownership"
    exit 8
fi

# execute as user, not necessarily as owner in case of /Library/LaunchAgents
/usr/bin/sudo "-u#$USER_ID" /bin/launchctl unload -w "$plist_path" 2>/dev/null
/usr/bin/sudo "-u#$USER_ID" /bin/launchctl load -S Aqua -w "$plist_path"
if [ $? != 0 ]; then
    log_message "unable to load $plist_path"
    exit 9
fi
