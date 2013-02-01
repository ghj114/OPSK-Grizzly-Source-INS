#!/usr/bin/env bash

set -ex

function git_clone {
    [[ "$OFFLINE" = "True" ]] && return

    GIT_REMOTE=$1
    GIT_DEST=$2
    GIT_REF=$3

    BASE_SOURCE="source/${GIT_DEST##/*/}"
    #echo $BASE_SOURCE

    if [[ ! -d $BASE_SOURCE ]]; then
        git clone $GIT_REMOTE $GIT_DEST
        cp -r $GIT_DEST $BASE_SOURCE
    else
        cp -r $BASE_SOURCE $GIT_DEST
    fi
    cd $GIT_DEST
    git fetch $GIT_REMOTE $GIT_REF && git checkout FETCH_HEAD
}

git_clone $1 $2 $3

