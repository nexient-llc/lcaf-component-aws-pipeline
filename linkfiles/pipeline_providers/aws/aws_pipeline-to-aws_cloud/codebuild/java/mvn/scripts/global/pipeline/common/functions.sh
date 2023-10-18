#!/bin/bash
LOCAL_FUNCTIONS="../../../local/pipeline/common/functions.sh"

if [ -f $LOCAL_FUNCTIONS ]; then
  # shellcheck source=/dev/null
  source "${LOCAL_FUNCTIONS}"
else
  exit 1
fi

function maven_build {
    install_asdf "${HOME}"
    set_vars_script_and_clone_service
    set_make_vars_and_artifact_token
    end_stage_if_properties_trigger "${GIT_REPO}" "${PROPERTIES_REPO_SUFFIX}"
    git_checkout "${MERGE_COMMIT_ID}" "${CODEBUILD_SRC_DIR}/${GIT_REPO}"
    cd_deploy_dir "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}"
    cp_docker_settings
    run_make_configure
    run_mvn_clean_install
}

function maven_test {
    install_asdf "${HOME}"
    set_vars_script_and_clone_service
    set_make_vars_and_artifact_token
    end_stage_if_properties_trigger "${GIT_REPO}" "${PROPERTIES_REPO_SUFFIX}"
    git_checkout "${MERGE_COMMIT_ID}" "${CODEBUILD_SRC_DIR}/${GIT_REPO}"
    cd_deploy_dir "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}"
    cp_docker_settings
    run_make_configure
    run_make_git_config
    run_make_codebuild_ca_token
    run_mvn_test
}

function set_make_vars_and_artifact_token {
    echo "Setting make vars"
    export JOB_NAME="${GIT_USERNAME}"
    export JOB_EMAIL="${GIT_USERNAME}@example.com"
    CODEARTIFACT_AUTH_TOKEN=$(aws codeartifact get-authorization-token --domain "${CODEARTIFACT_DOMAIN}" --domain-owner "${CODEARTIFACT_OWNER}" --query authorizationToken --output text)
    export CODEARTIFACT_AUTH_TOKEN
}