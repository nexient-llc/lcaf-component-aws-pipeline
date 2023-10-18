#!/bin/bash

function run_make_tfmodule_lint {
    echo "Running make tfmodule/lint"
    make tfmodule/lint
}

function run_make_tfmodule_fmt {
    echo "Running make tfmodule/fmt"
    make tfmodule/fmt
}
