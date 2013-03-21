#! /usr/bash

function git_clone {
    [[ "$OFFLINE" = "True" ]] && return

    GIT_REMOTE=$1
    GIT_DEST=$2
    GIT_REF=$3

    if [[ ! -d $GIT_DEST ]]; then
        git clone $GIT_REMOTE $GIT_DEST
    fi
        cd $GIT_DEST
        git fetch $GIT_REMOTE $GIT_REF && git checkout FETCH_HEAD

    if echo $GIT_REF | egrep -q "^refs"; then
        # If our branch name is a gerrit style refs/changes/...
        if [[ ! -d $GIT_DEST ]]; then
            [[ "$ERROR_ON_CLONE" = "True" ]] && exit 1
            git clone $GIT_REMOTE $GIT_DEST
        fi
        cd $GIT_DEST
        git fetch $GIT_REMOTE $GIT_REF && git checkout FETCH_HEAD
    else
        # do a full clone only if the directory doesn't exist
        if [[ ! -d $GIT_DEST ]]; then
            [[ "$ERROR_ON_CLONE" = "True" ]] && exit 1
            git clone $GIT_REMOTE $GIT_DEST
            cd $GIT_DEST
            # This checkout syntax works for both branches and tags
            git checkout $GIT_REF
        elif [[ "$RECLONE" == "yes" ]]; then
            # if it does exist then simulate what clone does if asked to RECLONE
            cd $GIT_DEST
            # set the url to pull from and fetch
            git remote set-url origin $GIT_REMOTE
            git fetch origin
            # remove the existing ignored files (like pyc) as they cause breakage
            # (due to the py files having older timestamps than our pyc, so python
            # thinks the pyc files are correct using them)
            find $GIT_DEST -name '*.pyc' -delete

            # handle GIT_REF accordingly to type (tag, branch)
            if [[ -n "`git show-ref refs/tags/$GIT_REF`" ]]; then
                git_update_tag $GIT_REF
            elif [[ -n "`git show-ref refs/heads/$GIT_REF`" ]]; then
                git_update_branch $GIT_REF
            elif [[ -n "`git show-ref refs/remotes/origin/$GIT_REF`" ]]; then
                git_update_remote_branch $GIT_REF
            else
                echo $GIT_REF is neither branch nor tag
                exit 1
            fi

        fi
    fi
}

