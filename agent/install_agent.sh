#!/bin/sh

BIN_DIR='/Library/Application Support/TeX Live Utility'
AGENT_DIR='/Library/LaunchAgents'
AGENT_PATH="$AGENT_DIR/com.googlecode.mactlmgr.update_check.plist"

SRC_BIN_PATH=""
SRC_PLIST_PATH=""

while getopts ":b:p:" opt; do
    case $opt in
        b   )   SRC_BIN_PATH="$OPTARG" ;;
        p   )   SRC_PLIST_PATH="$OPTARG" ;;
        \?  )   echo 'usage: install_agent -b binary_src_path -p plist_src_path'
                exit 1 ;;
                
    esac
done
shift $(($OPTIND - 1))

if [ "$SRC_BIN_PATH" = "" ] || [ "$SRC_PLIST_PATH" = "" ]; then
    echo 'usage: install_agent -b binary_src_path -p plist_src_path'
    exit 1
fi

if [ ! -f "$SRC_BIN_PATH" ]; then
    echo "$SRC_BIN_PATH does not exist"
    exit 3
fi

if [ ! -f "$SRC_PLIST_PATH" ]; then
    echo "$SRC_PLIST_PATH does not exist"
    exit 3
fi

if [ ! -d "$BIN_DIR" ]; then
    /bin/mkdir -p "$BIN_DIR"
    if [ $? != 0 ]; then
        echo "$0: unable to create $BIN_DIR"
        exit 1
    fi
fi

if [ ! -d "$AGENT_DIR" ]; then
    /bin/mkdir -p "$AGENT_DIR"
    if [ $? != 0 ]; then
        echo "$0: unable to create $AGENT_DIR"
        exit 1
    fi
fi

/bin/cp "$SRC_BIN_PATH" "$BIN_DIR"
if [ $? != 0 ]; then
    echo "$0: unable to create $SRC_BIN_PATH to $BIN_DIR"
    exit 1
fi

/bin/cp "$SRC_PLIST_PATH" "$AGENT_DIR"
if [ $? != 0 ]; then
    echo "$0: unable to copy $SRC_PLIST_PATH to $AGENT_DIR"
    exit 1
fi

/bin/launchctl load -w "$AGENT_PATH"
if [ $? != 0 ]; then
    echo "$0: unable to load $AGENT_PATH"
    exit 1
fi

