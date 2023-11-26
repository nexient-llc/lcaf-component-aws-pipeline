#!/bin/bash

function run_make_tfmodule_lint {
    echo "Running make tfmodule/lint"
    make tfmodule/lint
}

function run_make_tfmodule_fmt {
    echo "Running make tfmodule/fmt"
    make tfmodule/fmt
}

function run_make_tfmodule_pre_deploy_test {
    echo "Running make tfmodule/test/regula"
    make tfmodule/pre_deploy_test
}

function run_launch_github_version_predict {
    echo "Running launch github version predict"
    launch github version predict
}

function run_launch_github_version_apply {
    echo "Running launch github version apply"
    launch github version apply
}