#!/bin/bash
DIR=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")
LOCAL_FUNCTIONS="${DIR}/../../../local/pipeline/common/functions.sh"

if [ -f $LOCAL_FUNCTIONS ]; then
  # shellcheck source=/dev/null
  source "${LOCAL_FUNCTIONS}"
else
  exit 1
fi

function simulated_merge {
    set_vars_script_and_clone_service
    git_checkout "origin/${TO_BRANCH}" "${CODEBUILD_SRC_DIR}/${GIT_REPO}"
    sim_merge "origin/${FROM_BRANCH}" "${CODEBUILD_SRC_DIR}/${GIT_REPO}"
    if [ "${IGNORE_INTERNALS}" != "true" ]; then
        check_git_changes_for_internals "${MERGE_COMMIT_ID}" "${BUILD_BRANCH}" || echo "git change result: $?"
    fi
}

function terragrunt_plan {
    install_asdf "${HOME}"
    set_vars_script_and_clone_service
    git_checkout "${MERGE_COMMIT_ID}" "${CODEBUILD_SRC_DIR}/${GIT_REPO}"
    tool_versions_install "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}"
    set_netrc "${GIT_SERVER_URL}" "${GIT_USERNAME}" "${GIT_TOKEN}"
    cd_deploy_dir "${CODEBUILD_SRC_DIR}/${GIT_REPO}"

    if check_git_changes_for_internals "${MERGE_COMMIT_ID}" "${BUILD_BRANCH}" && [ "${INTERNALS_PIPELINE}" == "true" ]; then
        cd_deploy_dir "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}/internals/${INTERNALS_SERVICE}/provider/aws/terragrunt/env/${TARGETENV}/"
        aws_profile=$(get_accounts_profile "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}/internals/${INTERNALS_SERVICE}/provider/aws/terragrunt/accounts.json" "${TARGETENV}")
        find . -mindepth 2 -maxdepth 2 -type d | sed 's|^\.||' | while IFS= read -r dir; do
            deploy_dir="${dir#/}"
            region_dir="${deploy_dir%%/*}"
            assume_iam_role "${ROLE_TO_ASSUME}" "${aws_profile}" "${region_dir}"
            copy_dependency_to_internals "${INTERNALS_SERVICE}" "${TOOLS_DIR}" "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}/internals/${INTERNALS_SERVICE}/provider/aws/terragrunt/env/${TARGETENV}/${deploy_dir}"
            cd_deploy_dir "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}/internals/${INTERNALS_SERVICE}/provider/aws/terragrunt/env/${TARGETENV}/${deploy_dir}/"
            run_terragrunt_init
            run_terragrunt_plan
        done
    elif ! check_git_changes_for_internals "${MERGE_COMMIT_ID}" "${BUILD_BRANCH}" && [ "${INTERNALS_PIPELINE}" == "true" ]; then
        echo "Exiting terragrunt plan as git changes found outside internals with this stage INTERNALS_PIPELINE == true"
        exit 0;
    elif check_git_changes_for_internals "${MERGE_COMMIT_ID}" "${BUILD_BRANCH}" && [ "${INTERNALS_PIPELINE}" != "true" ]; then
        echo "Exiting terragrunt plan as git changes found inside internals with this stage INTERNALS_PIPELINE != true"
        exit 0;
    else
        cd_deploy_dir "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}/env/${TARGETENV}/"
        find . -mindepth 2 -maxdepth 2 -type d | sed 's|^\.||' | while IFS= read -r dir; do
            deploy_dir="${dir#/}"
            region_dir="${deploy_dir%%/*}"
            aws_profile=$(get_accounts_profile "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}/accounts.json" "${TARGETENV}")
            assume_iam_role "${ROLE_TO_ASSUME}" "${aws_profile}" "${region_dir}"
            cd_deploy_dir "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}/env/${TARGETENV}/${deploy_dir}/"
            find ${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}${PROPERTIES_REPO_SUFFIX}/env/${TARGETENV}/${deploy_dir}/ -type f -exec cp -- {} ${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}/env/${TARGETENV}/${deploy_dir}/ \;
            run_terragrunt_init
            run_terragrunt_plan
        done
    fi
}

function terragrunt_deploy {
    install_asdf "${HOME}"
    set_vars_script_and_clone_service
    git_checkout "${MERGE_COMMIT_ID}" "${CODEBUILD_SRC_DIR}/${GIT_REPO}"
    tool_versions_install "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}"
    set_netrc "${GIT_SERVER_URL}" "${GIT_USERNAME}" "${GIT_TOKEN}" 
    cd_deploy_dir "${CODEBUILD_SRC_DIR}/${GIT_REPO}"

    if [ "${INTERNALS_PIPELINE}" == "true" ]; then
        cd_deploy_dir "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}/internals/${INTERNALS_SERVICE}/provider/aws/terragrunt/env/${TARGETENV}/"
        aws_profile=$(get_accounts_profile "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}/internals/${INTERNALS_SERVICE}/provider/aws/terragrunt/accounts.json" "${TARGETENV}")
        find . -mindepth 2 -maxdepth 2 -type d | sed 's|^\.||' | while IFS= read -r dir; do
            deploy_dir="${dir#/}"
            region_dir="${deploy_dir%%/*}"
            assume_iam_role "${ROLE_TO_ASSUME}" "${aws_profile}" "${region_dir}"
            copy_dependency_to_internals "${INTERNALS_SERVICE}" "${TOOLS_DIR}" "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}/internals/${INTERNALS_SERVICE}/provider/aws/terragrunt/env/${TARGETENV}/${deploy_dir}"
            cd_deploy_dir "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}/internals/${INTERNALS_SERVICE}/provider/aws/terragrunt/env/${TARGETENV}/${deploy_dir}/"
            run_terragrunt_init
            run_terragrunt_apply
        done
    else
        cd_deploy_dir "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}/env/${TARGETENV}/"
        find . -mindepth 2 -maxdepth 2 -type d | sed 's|^\.||' | while IFS= read -r dir; do
            deploy_dir="${dir#/}"
            region_dir="${deploy_dir%%/*}"
            aws_profile=$(get_accounts_profile "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}/accounts.json" "${TARGETENV}")
            assume_iam_role "${ROLE_TO_ASSUME}" "${aws_profile}" "${region_dir}"
            cd_deploy_dir "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}/env/${TARGETENV}/${deploy_dir}/"
            find ${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}${PROPERTIES_REPO_SUFFIX}/env/${TARGETENV}/${deploy_dir}/ -type f -exec cp -- {} ${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}/env/${TARGETENV}/${deploy_dir}/ \;
            run_terragrunt_init
            run_terragrunt_apply
        done
    fi
}

function tf_pre_deploy_functional_test {
    install_asdf "${HOME}"
    set_vars_script_and_clone_service
    git_checkout "${MERGE_COMMIT_ID}" "${CODEBUILD_SRC_DIR}/${GIT_REPO}"
    run_pre_deploy_functional_test
}

function tf_post_deploy_functional_test {
    install_asdf "${HOME}"
    set_vars_script_and_clone_service
    git_checkout "${MERGE_COMMIT_ID}" "${CODEBUILD_SRC_DIR}/${GIT_REPO}"
    if ! run_post_deploy_functional_test "${TEST_FAILURE}"; then
        echo "Failure detected from Post Deployment Functional Tests. Rolling back."
        MERGE_COMMIT_ID=$(rollback_env "${ENV_GIT_TAG}" "${MERGE_COMMIT_ID}" "${CODEBUILD_SRC_DIR}/${GIT_REPO}")
        export MERGE_COMMIT_ID
        create_global_vars_script "${MERGE_COMMIT_ID}" "${LATEST_COMMIT_HASH}" "${GIT_PROJECT}" "${GIT_REPO}" "${FROM_BRANCH}" "${TO_BRANCH}" "${PROPERTIES_REPO_SUFFIX}" "${GIT_SERVER_URL}" "${IMAGE_TAG}" "${SERVICE_COMMIT}" "${CODEBUILD_SRC_DIR}" 
        copy_zip_to_s3_bucket "${USERVAR_S3_CODEPIPELINE_BUCKET}" "${CODEBUILD_SRC_DIR}"
        exit 1
    fi
}

function certify_env {
    install_asdf "${HOME}"
    set_vars_script_and_clone_service
    add_git_tag "${CERTIFY_PREFIX}-${MERGE_COMMIT_ID}" "${MERGE_COMMIT_ID}" "${CODEBUILD_SRC_DIR}/${GIT_REPO}"
}

function trigger_pipeline {
    set_vars_script_and_clone_service
    create_global_vars_script "${MERGE_COMMIT_ID}" "${LATEST_COMMIT_HASH}" "${GIT_PROJECT}" "${GIT_REPO}" "${FROM_BRANCH}" "${TO_BRANCH}" "${PROPERTIES_REPO_SUFFIX}" "${GIT_SERVER_URL}" "${NEW_IMAGE_TAG}" "${SERVICE_COMMIT}" "${CODEBUILD_SRC_DIR}" 
    git_checkout "${MERGE_COMMIT_ID}" "${CODEBUILD_SRC_DIR}/${GIT_REPO}"
    if [ "${IGNORE_INTERNALS}" != "true" ] && check_git_changes_for_internals "${MERGE_COMMIT_ID}" "${BUILD_BRANCH}"; then
        export USERVAR_S3_CODEPIPELINE_BUCKET=${INTERNALS_CODEPIPELINE_BUCKET}
    fi
    copy_zip_to_s3_bucket "${USERVAR_S3_CODEPIPELINE_BUCKET}" "${CODEBUILD_SRC_DIR}"
}

function codebuild_status {
    set_vars_from_script "${CODEBUILD_SRC_DIR}/set_vars.sh"
    GIT_TOKEN=$(get_secret_manager_secret "${GIT_TOKEN_SM_ARN}" "${AWS_REGION}" | tail -n 1)
    GIT_USERNAME=$(get_secret_manager_secret "${GIT_USERNAME_SM_ARN}" "${AWS_REGION}" | tail -n 1)
    codebuild_status_callback "${MERGE_COMMIT_ID}" "${GIT_SERVER_URL}" "${GIT_USERNAME}" "${GIT_TOKEN}" "${IS_PIPELINE_LAST_STAGE}" "${CODEBUILD_BUILD_SUCCEEDING}" "${CODEBUILD_BUILD_URL}" "${CODEBUILD_BUILD_ID}"
}

function set_vars_script_and_clone_service {
    set_vars_from_script "${CODEBUILD_SRC_DIR}/set_vars.sh"  "${BUILD_BRANCH}"
    GIT_TOKEN=$(get_secret_manager_secret "${GIT_TOKEN_SM_ARN}" "${AWS_REGION}" | tail -n 1)
    GIT_USERNAME=$(get_secret_manager_secret "${GIT_USERNAME_SM_ARN}" "${AWS_REGION}" | tail -n 1)
    PROPERTIES_REPO_SUFFIX=$(get_properties_suffix "${GIT_PROPERTIES_SUFFIX}")
    export GIT_TOKEN
    export GIT_USERNAME
    export PROPERTIES_REPO_SUFFIX
    echo "PROPERTIES_REPO_SUFFIX: ${PROPERTIES_REPO_SUFFIX}"

    git_config "${GIT_USERNAME}@${GIT_EMAIL_DOMAIN}" "${GIT_USERNAME}"
    git_clone "${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}" "${GIT_USERNAME}" "${GIT_TOKEN}" "${GIT_SERVER_URL#https://}" "${GIT_PROJECT}" "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}" "${SVC_BRANCH}" && SERVICE_COMMIT=$(git -C "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}" rev-parse HEAD)
    export SERVICE_COMMIT
    echo "${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"} HEAD commit: ${SERVICE_COMMIT}"
    
    git_clone "${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}${PROPERTIES_REPO_SUFFIX}" "${GIT_USERNAME}" "${GIT_TOKEN}" "${GIT_SERVER_URL#https://}" "${GIT_PROJECT}" "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}${PROPERTIES_REPO_SUFFIX}" "${SVC_PROP_BRANCH}"&& PROPS_COMMIT=$(git -C "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}${PROPERTIES_REPO_SUFFIX}" rev-parse HEAD)
    export PROPS_COMMIT
    echo "${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}${PROPERTIES_REPO_SUFFIX} HEAD commit: ${PROPS_COMMIT}"
}

function  increment_semver {
    install_asdf "${HOME}"
    set_vars_script_and_clone_service
    semver_git_tag=$(increment_git_tag "${CODEBUILD_SRC_DIR}/${GIT_REPO}")
    add_git_tag "${semver_git_tag}" "AWS CodePipeline SemVer incremented" "${CODEBUILD_SRC_DIR}/${GIT_REPO}"
}