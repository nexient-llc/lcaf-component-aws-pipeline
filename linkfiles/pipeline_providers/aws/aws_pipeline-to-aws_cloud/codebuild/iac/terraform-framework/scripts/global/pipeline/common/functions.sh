#!/bin/bash
LOCAL_FUNCTIONS="../../../local/pipeline/common/functions.sh"

if [ -f $LOCAL_FUNCTIONS ]; then
  # shellcheck source=/dev/null
  source "${LOCAL_FUNCTIONS}"
else
  exit 1
fi

function lint_terraform_module {
    install_asdf "${HOME}"
    set_vars_from_script "${CODEBUILD_SRC_DIR}/set_vars.sh"  "${BUILD_BRANCH}"
    set_global_vars
    git_clone_service
    set_commit_vars
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

function make_check {
    install_asdf "${HOME}"
    set_vars_from_script "${CODEBUILD_SRC_DIR}/set_vars.sh"  "${BUILD_BRANCH}"
    set_global_vars
    git_config "${GIT_USERNAME}@${GIT_EMAIL_DOMAIN}" "${GIT_USERNAME}"
    git_clone_service
    set_commit_vars
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

function launch_predict_semver {
    install_asdf "${HOME}"
    set_vars_script_and_clone_service
    git_checkout "${MERGE_COMMIT_ID}" "${CODEBUILD_SRC_DIR}/${GIT_REPO}"
    tool_versions_install "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}"
    set_netrc "${GIT_SERVER_URL}" "${GIT_USERNAME}" "${GIT_TOKEN}"
    run_make_configure
    if ! run_launch_github_version_predict "${FROM_BRANCH}"; then
        echo "[ERROR] predict repo version failed on branch: ${FROM_BRANCH}"
        exit 1
    fi
}

function launch_apply_semver {
    local branch="${BUILD_BRANCH:-main}"

    install_asdf "${HOME}"
    set_vars_script_and_clone_service
    git_checkout "${MERGE_COMMIT_ID}" "${CODEBUILD_SRC_DIR}/${GIT_REPO}"
    tool_versions_install "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}"
    set_netrc "${GIT_SERVER_URL}" "${GIT_USERNAME}" "${GIT_TOKEN}"
    run_make_configure
    if git merge-base --is-ancestor "${MERGE_COMMIT_ID}" "origin/${branch}"; then
        run_launch_github_version_apply "${FROM_BRANCH}"
    else 
        echo "[ERROR] ${MERGE_COMMIT_ID} is not ancestor of ${branch}"
        exit 1
    fi
}
