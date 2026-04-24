#!/usr/bin/env zsh

setup_library() {
    local LIB_NAME=$1
    local SOURCE_FILE=Sources/"$LIB_NAME/$LIB_NAME.swift"

    mkdir -p Sources/"$LIB_NAME"
    if [ ! -e "$SOURCE_FILE" ]; then
        echo "// $LIB_NAME" > $SOURCE_FILE
    fi
}

setup_library BlueskyKit
setup_library BlueskyCore
setup_library BlueskyAuth
setup_library BlueskyDataStore
setup_library BlueskyUI
