#!/bin/bash
LOCAL_FUNCTIONS="../../../local/pipeline/common/functions.sh"

if [ -f $LOCAL_FUNCTIONS ]; then
  # shellcheck source=/dev/null
  source "${LOCAL_FUNCTIONS}"
else
  exit 1
fi

function conftest_terraform_module {
    echo "Conftest has not been implemented"
}

function lint_terraform_module {
    install_asdf "${HOME}"
    set_vars_script_and_clone_module
    export JOB_NAME="${GIT_USERNAME}"
    export JOB_EMAIL="${GIT_USERNAME}@${GIT_EMAIL_DOMAIN}"
    git_checkout "${MERGE_COMMIT_ID}" "${CODEBUILD_SRC_DIR}/${GIT_REPO}"
    tool_versions_install "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}"
    cd "${CODEBUILD_SRC_DIR}/${GIT_REPO}" || exit 1
    git_checkout "CodeBuild_${FROM_BRANCH}" "${CODEBUILD_SRC_DIR}/${GIT_REPO}" "-b"
    set_netrc "${GIT_SERVER_URL}" "${GIT_USERNAME}" "${GIT_TOKEN}"
    run_make_configure
    run_make_git_config
    run_make_tfmodule_fmt
    run_make_tfmodule_lint
    if ! git_status_porcelain_changes; then
        exit 0
    fi
    git_commit "${CODEBUILD_SRC_DIR}/${GIT_REPO}"
    git_checkout "${FROM_BRANCH}" "${CODEBUILD_SRC_DIR}/${GIT_REPO}" "-b"
    git_merge "CodeBuild_${FROM_BRANCH}" "${CODEBUILD_SRC_DIR}/${GIT_REPO}"
    git_push "${CODEBUILD_SRC_DIR}/${GIT_REPO}" "${FROM_BRANCH}"
    exit 1
}

function make_check_module {
    install_asdf "${HOME}"
    set_vars_script_and_clone_module
    export JOB_NAME="${GIT_USERNAME}"
    export JOB_EMAIL="${GIT_USERNAME}@${GIT_EMAIL_DOMAIN}"
    git_checkout "${MERGE_COMMIT_ID}" "${CODEBUILD_SRC_DIR}/${GIT_REPO}"
    tool_versions_install "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}"
    cd "${CODEBUILD_SRC_DIR}/${GIT_REPO}" || exit 1
    assume_iam_role "${ROLE_TO_ASSUME}" "make_check_module" "${AWS_REGION}"
    export AWS_PROFILE="make_check_module"
    set_netrc "${GIT_SERVER_URL}" "${GIT_USERNAME}" "${GIT_TOKEN}"
    run_make_configure
    run_make_git_config
    run_make_check
}

function set_vars_script_and_clone_module {
    set_vars_from_script "${CODEBUILD_SRC_DIR}/set_vars.sh"  "${BUILD_BRANCH}"
    git_clone "${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}" "${GIT_USERNAME}" "${GIT_TOKEN}" "${GIT_SERVER_URL#https://}" "${GIT_PROJECT}" "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}" "${SVC_BRANCH}" && SERVICE_COMMIT=$(git -C "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}" rev-parse HEAD)
    export SERVICE_COMMIT
    echo "${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"} HEAD commit: ${SERVICE_COMMIT}"
}
