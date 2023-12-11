#!/bin/bash

function run_conftest_docker {
    echo "Configuring..."
    run_make_configure
    echo "Running conftest."
    conftest test --all-namespaces Dockerfile* --policy components/container/policy
}

function make_docker_build {
    local image_tag=$1
    local arch_type=$2

    run_make_configure
    make platform/devenv/configure-docker-buildx
    echo "Container will be built with IMAGE_TAG=$image_tag"
    export CONTAINER_IMAGE_VERSION="${image_tag}"
    export DOCKER_BUILD_ARCH="${arch_type}"
    make docker/build
}

function make_docker_push {
    local image_tag=$1
    local arch_type=$2

    run_make_configure
    make platform/devenv/configure-docker-buildx
    make docker/aws_ecr_login
    echo "Container will be built with IMAGE_TAG=$image_tag"
    export CONTAINER_IMAGE_VERSION="${image_tag}"
    export DOCKER_BUILD_ARCH="${arch_type}"
    make docker/push
}

function start_docker {
    echo "Starting docker"
    dockerd &
}

function add_ecr_image_tag {
    local image_tag=$1
    local commit_id=$2
    local repository=$3

    echo "Tagging ECR image with new tag:$image_tag"
    manifest=$(aws ecr batch-get-image --repository-name "$repository" --image-ids imageTag=$commit_id --output json | jq --raw-output --join-output '.images[0].imageManifest')
    aws ecr put-image --repository-name "$repository" --image-tag "$image_tag" --image-manifest "$manifest"
}