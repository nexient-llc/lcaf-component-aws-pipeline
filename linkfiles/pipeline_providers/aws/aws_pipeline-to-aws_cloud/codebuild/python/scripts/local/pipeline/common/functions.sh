#!/bin/bash

function run_python_unit_tests {
    echo "Preparing to run Unit Tests."
    make configure
    make python/venv
    source .venv/bin/activate
    echo "Running Unit Tests."
    make python/tests/unit
    deactivate
}

function run_python_integration_tests {
    echo "Preparing to run Integration Tests."
    make configure
    make python/venv
    source .venv/bin/activate
    echo "Starting dockerd."
    dockerd &
    echo "Running Integration Tests."
    make python/tests/integration
    deactivate
}
