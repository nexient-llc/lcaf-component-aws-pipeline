#!/bin/bash

function run_make_codebuild_jinja {
    echo "Running make codebuild-jinja"
    asdf reshim
    make codebuild-jinja
}

function run_make_platform {
    echo "Running make platform/devenv/configure-docker-buildx"
    make platform/devenv/configure-docker-buildx
}

function run_make_docker_aws_ecr_login {
    echo "Running make docker/aws_ecr_login"
    make docker/aws_ecr_login
}

function start_docker {
    echo "Starting docker"
    dockerd &
}

function push_docker_image {
    echo "Pushing image to ECR"
    export CONTAINER_IMAGE_VERSION="$1" && make docker/push
}

function python_setup {
    local dir=$1

    cd "$dir" || exit 1
    pip3 install .
}

function run_mvn_clean_install {
    echo "Running mvn clean install -DskipTests"
    mvn clean install -DskipTests
}

function create_properties_var_file {
    local base_path=$1
    local repository=$2
    local target_env=$3
    local image_tag=$4
    local container_uri=$5
    local properties=$6
    local dir=$7

    cd "$dir" ||  exit 1
    cp -rf $base_path/${repository}${properties}/$target_env/terragrunt/* ./
    echo "app_image_tag=\"$container_uri/$repository:$image_tag\"
        force_new_deployment=\"true\"
        app_environment = {
        timestamp=$(date +%s)
        $(cat $base_path/$repository/configuration/application-envvars.env)
        $(cat $base_path/$repository/configuration/wildfly-envvars.env)
        }
        app_secrets = {
        $(cat $base_path/$repository/configuration/application-envsecrets-arns.env)
        $(cat $base_path/$repository/configuration/wildfly-envsecrets-arns.env)
        }" > env_vars.tfvars
}

function run_terragrunt_apply_var_file {
    echo "Running terragrunt apply"
    terragrunt apply -var-file ./env_vars.tfvars -auto-approve
}

function print_running_td {
    local profile=$1

    echo 'Printing current ECS running task definition'
    CLUSTER_ARN=$(python3 -c "import yaml;print(yaml.safe_load(open('inputs.yaml'))['ecs_cluster_arn'])")
    CLUSTER_SERVICES=$(aws ecs list-services --cluster "$CLUSTER_ARN" --output text --query 'serviceArns[]' --profile "$profile")
    for SERVICE_ARN in $CLUSTER_SERVICES
        do
            echo "Task definition for :$SERVICE_ARN"
            aws ecs describe-task-definition --task-definition $(aws ecs describe-services --cluster "$CLUSTER_ARN" --services "$SERVICE_ARN" --query "services[0].taskDefinition" --output text --profile "$profile") --profile "$1"
    done
}

function add_ecr_image_tag {
    local image_tag=$1
    local commit_id=$2
    local repository=$3

    echo "Tagging ECR image with new tag:$image_tag-$commit_id"
    manifest=$(aws ecr batch-get-image --repository-name "$3" --image-ids imageTag=$commit_id --output json | jq --raw-output --join-output '.images[0].imageManifest')
    aws ecr put-image --repository-name "$repository" --image-tag "$image_tag-$commit_id" --image-manifest "$manifest"
    aws ecr describe-images --repository-name "$repository"
}

function cp_docker_settings {
    # https://docs.aws.amazon.com/codebuild/latest/userguide/troubleshooting.html#troubleshooting-maven-repos
    cp ./settings.xml-DOCKERBUILD /root/.m2/settings.xml
}
