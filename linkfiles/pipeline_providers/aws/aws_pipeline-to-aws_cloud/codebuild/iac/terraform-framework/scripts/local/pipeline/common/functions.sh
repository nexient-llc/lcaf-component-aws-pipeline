#!/bin/bash

function run_make_tfmodule_lint {
    echo "Running make tfmodule/lint"
    make tfmodule/lint
}

function run_make_tfmodule_fmt {
    echo "Running make tfmodule/fmt"
    make tfmodule/fmt
}

function run_make_check {
    echo "Running make check"
    make check
}

function run_launch_github_version_predict {
    local from_branch=$1

    echo "Running launch github version predict"
    launch github version predict --source-branch "${FROM_BRANCH}"
}

function run_launch_github_version_apply {
    local from_branch=$1

    echo "Running launch github version apply"
    launch github version apply --source-branch "${FROM_BRANCH}" --pipeline
}