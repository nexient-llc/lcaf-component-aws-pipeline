#!/bin/bash

function run_conftest_docker {
    echo "Configuring..."
    run_make_configure
    echo "Running conftest."
    conftest test --all-namespaces Dockerfile* --policy components/container/policy
}

function build_container_ecr {
    run_make_configure
    make platform/devenv/configure-docker-buildx
    make docker/aws_ecr_login
    IMAGE_TAG="$1"
    echo "Container will be built with IMAGE_TAG=$IMAGE_TAG"
    export CONTAINER_IMAGE_VERSION="${IMAGE_TAG}" && make docker/push
}

function start_docker {
    echo "Starting docker"
    dockerd &
}
