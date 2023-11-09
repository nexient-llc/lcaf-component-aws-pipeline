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