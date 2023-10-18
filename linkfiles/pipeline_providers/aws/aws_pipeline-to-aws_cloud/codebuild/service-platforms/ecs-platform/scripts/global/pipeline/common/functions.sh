#!/bin/bash
LOCAL_FUNCTIONS="../../../local/pipeline/common/functions.sh"

if [ -f $LOCAL_FUNCTIONS ]; then
  # shellcheck source=/dev/null
  source "${LOCAL_FUNCTIONS}"
else
  exit 1
fi

function publish_ecr_image {
    start_docker
    install_asdf "${HOME}"
    set_vars_script_and_clone_service
    end_stage_if_properties_trigger "${GIT_REPO}" "${PROPERTIES_REPO_SUFFIX}"
    set_make_vars_and_artifact_token
    git_checkout "${MERGE_COMMIT_ID}" "${CODEBUILD_SRC_DIR}/${GIT_REPO}"
    cd_deploy_dir "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}"
    cp_docker_settings
    run_make_configure
    run_make_git_config
    run_make_platform
    run_make_docker_aws_ecr_login
    run_make_codebuild_ca_token
    run_mvn_clean_install
    push_docker_image "${MERGE_COMMIT_ID}"
}

function deploy_ecr_image {
    install_asdf "${HOME}"
    set_vars_script_and_clone_service
    export JOB_NAME="${GIT_USERNAME}"
    export JOB_EMAIL="${GIT_USERNAME}@${GIT_EMAIL_DOMAIN}"
    git_clone "magicdust" "${GIT_USERNAME}" "${GIT_TOKEN}" "${GIT_SERVER_URL#https://}" "DSO" "${CODEBUILD_SRC_DIR}/magicdust"
    python_setup "${CODEBUILD_SRC_DIR}/magicdust"
    cd_deploy_dir "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}"
    git_checkout "${BUILD_BRANCH}" "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}"
    run_make_git_config
    tool_versions_install "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}"
    set_netrc "${GIT_SERVER_URL}" "${GIT_USERNAME}" "${GIT_TOKEN}"
    run_make_codebuild_jinja
    cd_deploy_dir "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}/internals/platform/ecs/terragrunt/env/${TARGETENV}/"

    find . -mindepth 2 -maxdepth 2 -type d | sed 's|^\.||' | while IFS= read -r dir; do
        deploy_dir="${dir#/}"
        region_dir="${deploy_dir%%/*}"
        aws_profile=$(get_accounts_profile "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}/internals/platform/ecs/terragrunt/accounts.json" "${TARGETENV}")
        assume_iam_role "${ROLE_TO_ASSUME}" "${aws_profile}" "${region_dir}"
        create_properties_var_file "${CODEBUILD_SRC_DIR}" "${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}" "${TARGETENV}" "${IMAGE_TAG}" "${ECR_URI}" "${PROPERTIES_REPO_SUFFIX}" "${deploy_dir}"
        run_terragrunt_init
        run_terragrunt_apply_var_file
        print_running_td "${aws_profile}"
    done
}

function certify_image {
    set_vars_from_script "${CODEBUILD_SRC_DIR}/set_vars.sh"
    add_ecr_image_tag "${NEW_IMAGE_TAG}" "${MERGE_COMMIT_ID}" "${GIT_REPO}"
}

function set_make_vars_and_artifact_token {
    echo "Setting make vars"
    export JOB_NAME="${GIT_USERNAME}"
    export JOB_EMAIL="${GIT_USERNAME}@${GIT_EMAIL_DOMAIN}"
    CODEARTIFACT_AUTH_TOKEN=$(aws codeartifact get-authorization-token --domain "${CODEARTIFACT_DOMAIN}" --domain-owner "${CODEARTIFACT_OWNER}" --query authorizationToken --output text)
    export CODEARTIFACT_AUTH_TOKEN
}

# TODO:
function integration_test {
    echo "Integration test commands would go here"
}

function auto_qa {
    echo "Auto QA commands would go here"
}