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
    cd "$1" || exit 1
    pip3 install .
}

function run_mvn_clean_install {
    echo "Running mvn clean install -DskipTests"
    mvn clean install -DskipTests
}

function create_properties_var_file {
    cd "$7" ||  exit 1
    cp -rf $1/${2}${6}/$3/terragrunt/* ./
    echo "app_image_tag=\"$5/$2:$4\"
        force_new_deployment=\"true\"
        app_environment = {
        timestamp=$(date +%s)
        $(cat $1/$2/configuration/application-envvars.env)
        $(cat $1/$2/configuration/wildfly-envvars.env)
        }
        app_secrets = {
        $(cat $1/$2/configuration/application-envsecrets-arns.env)
        $(cat $1/$2/configuration/wildfly-envsecrets-arns.env)
        }" > env_vars.tfvars
}

function run_terragrunt_apply_var_file {
    echo "Running terragrunt apply"
    terragrunt apply -var-file ./env_vars.tfvars -auto-approve
}

function print_running_td {
    echo 'Printing current ECS running task definition'
    CLUSTER_ARN=$(python3 -c "import yaml;print(yaml.safe_load(open('inputs.yaml'))['ecs_cluster_arn'])")
    CLUSTER_SERVICES=$(aws ecs list-services --cluster "$CLUSTER_ARN" --output text --query 'serviceArns[]' --profile "$1")
    for SERVICE_ARN in $CLUSTER_SERVICES
        do
            echo "Task definition for :$SERVICE_ARN"
            aws ecs describe-task-definition --task-definition $(aws ecs describe-services --cluster "$CLUSTER_ARN" --services "$SERVICE_ARN" --query "services[0].taskDefinition" --output text --profile "$1") --profile "$1"
    done
}

function add_ecr_image_tag {
    echo "Tagging ECR image with new tag:$1-$2"
    MANIFEST=$(aws ecr batch-get-image --repository-name "$3" --image-ids imageTag=$2 --output json | jq --raw-output --join-output '.images[0].imageManifest')
    aws ecr put-image --repository-name "$3" --image-tag "$1-$2" --image-manifest "$MANIFEST"
    aws ecr describe-images --repository-name "$3"
}

function tag_service_platform_service {
    echo "Adding tags to shared service."
    yq e ".tags.application_name = \"$1\"" inputs.yaml -i
    yq e ".tags.application_version = \"$2\"" inputs.yaml -i
    yq e ".tags.exclusive_service_name = \"$3\"" inputs.yaml -i
    yq e ".tags.exclusive_service_version = \"$4\"" inputs.yaml -i
    yq e ".tags.envoy_name = \"$5\"" inputs.yaml -i
    yq e ".tags.envoy_version = \"$6\"" inputs.yaml -i
    yq e ".tags.otel_collector_name = \"$7\"" inputs.yaml -i
    yq e ".tags.otel_collector_version = \"$8\"" inputs.yaml -i
    yq e ".tags.properties_version = \"$9\"" inputs.yaml -i
}

function cp_docker_settings {
    # https://docs.aws.amazon.com/codebuild/latest/userguide/troubleshooting.html#troubleshooting-maven-repos
    cp ./settings.xml-DOCKERBUILD /root/.m2/settings.xml
}
