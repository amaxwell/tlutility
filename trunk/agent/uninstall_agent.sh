#!/bin/sh

# always install here, since it's useful for any user
BIN_DIR="/Library/Application Support/TeX Live Utility"

# will install to one of these, depending on the -a flag
USER_PLIST_DIR=""
LOCAL_PLIST_DIR="/Library/LaunchAgents"

# default to local install
PLIST_DIR="$LOCAL_PLIST_DIR"

BIN_PATH="$BIN_DIR/update_check.py"
USER_ID=""

SCRIPT_NAME=$(basename "$0")

usage()
{
    echo 'usage: uninstall_agent -h home_dir -u uid' >&2
}

while getopts ":h:u:" opt; do
    case $opt in
        h   )   USER_PLIST_DIR="$OPTARG/$LOCAL_PLIST_DIR" ;;
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

if [ "$USER_PLIST_DIR" = "" ]; then
    log_message "Home directory not passed in"
    usage
    exit 1
fi

# need to run launchctl as currently logged-in user
if [ "$USER_ID" == "" ]; then
    log_message "User id to unload agent is not set."
    exit 1
fi

exit_status=0

# try to unload the launchd plist if it exists; this fails if it's not loaded
# no action is taken if none of the files exist, and this is not an error

plist_dirs=("$USER_PLIST_DIR" "$LOCAL_PLIST_DIR")
for plist_dir in "${plist_dirs[@]}"; do

    plist_path="$plist_dir/com.googlecode.mactlmgr.update_check.plist"

    if [ -f "$plist_path" ]; then
        
        # Unload with launchctl, which doesn't like running as root to unload a non-root plist.        
        /usr/bin/sudo "-u#$USER_ID" /bin/launchctl unload -w -S Aqua "$plist_path"
        if [ $? != 0 ]; then
            log_message "unable to unload $plist_path"
            log_message "changes may not be effective until next login"
            exit_status=10
        fi
        
        # Note: user can still unload jobs by label, even if the plist is now gone
        /bin/rm -f "$plist_path"
        if [ $? != 0 ]; then
            log_message "unable to remove $plist_path"
            exit_status=11
        else
            log_message "removed $plist_path"
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
