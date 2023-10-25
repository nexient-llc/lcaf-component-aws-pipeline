#!/bin/bash

function run_make_tfmodule_lint {
    echo "Running make tfmodule/lint"
    make tfmodule/lint
}

function run_make_tfmodule_fmt {
    echo "Running make tfmodule/fmt"
    make tfmodule/fmt
}

function run_make_tfmodule_test_conftest {
    echo "Running make tfmodule/test/conftest"
    make tfmodule/test/conftest
}

function run_make_tfmodule_test_regula {
    echo "Running make tfmodule/test/regula"
    make tfmodule/test/regula
}