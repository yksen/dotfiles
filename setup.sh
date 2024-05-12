#!/bin/bash

shopt -s globstar

while getopts ":r" option; do
    case $option in
        r)
        RUN=true;;
    esac
done

SOURCE_DIR="$(realpath .)"
TARGET_DIR="$HOME"

for file in $(find $SOURCE_DIR -type f -name "*" -not -name "README.md" -not -path "*/setup*" -not -path "*/.git/*" -not -path "*/powershell/*"); do
    if [[ -f "$file" ]]; then
        TARGET_PATH=$file
        SOURCE_PATH=$HOME/$(echo ${file/$SOURCE_DIR} | cut -d'/' -f3-)
        if [[ $RUN = true ]]; then
            mkdir -p $(dirname $SOURCE_PATH)
            ln -sf "$TARGET_PATH" "$SOURCE_PATH"
        else
            echo "ln -sf $TARGET_PATH $SOURCE_PATH";
        fi
    fi
done

if [[ -z ${RUN+x} ]]; then
    echo "This was a dry run, use with -r to execute"
fi
