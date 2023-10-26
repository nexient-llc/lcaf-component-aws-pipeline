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
    cd "${CODEBUILD_SRC_DIR}/${GIT_REPO}" || exit 1

    if check_git_changes_for_internals "${MERGE_COMMIT_ID}" "${BUILD_BRANCH}" && [ "${INTERNALS_PIPELINE}" == "true" ]; then
        terragrunt_internals "plan"
    elif ! check_git_changes_for_internals "${MERGE_COMMIT_ID}" "${BUILD_BRANCH}" && [ "${INTERNALS_PIPELINE}" == "true" ]; then
        echo "Exiting terragrunt plan as git changes found outside internals with this stage INTERNALS_PIPELINE == true"
        exit 0
    elif check_git_changes_for_internals "${MERGE_COMMIT_ID}" "${BUILD_BRANCH}" && [ "${INTERNALS_PIPELINE}" != "true" ]; then
        echo "Exiting terragrunt plan as git changes found inside internals with this stage INTERNALS_PIPELINE != true"
        exit 0
    else
        terragrunt_service "apply"
    fi
}

function terragrunt_deploy {
    install_asdf "${HOME}"
    set_vars_script_and_clone_service
    git_checkout "${MERGE_COMMIT_ID}" "${CODEBUILD_SRC_DIR}/${GIT_REPO}"
    tool_versions_install "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}"
    set_netrc "${GIT_SERVER_URL}" "${GIT_USERNAME}" "${GIT_TOKEN}"
    cd "${CODEBUILD_SRC_DIR}/${GIT_REPO}" || exit 1

    if [ "${INTERNALS_PIPELINE}" == "true" ]; then
        terragrunt_internals "apply"
    else
        terragrunt_service "apply"
    fi
}

function terragrunt_internals {
    local type=$1

    cd "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}/internals/${INTERNALS_SERVICE}/provider/aws/terragrunt/env/${TARGETENV}/" || exit 1
    aws_profile=$(get_accounts_profile "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}/internals/${INTERNALS_SERVICE}/provider/aws/terragrunt/accounts.json" "${TARGETENV}")
    find . -mindepth 2 -maxdepth 2 -type d | sed 's|^\.||' | while IFS= read -r dir; do
        deploy_dir="${dir#/}"
        region_dir="${deploy_dir%%/*}"
        assume_iam_role "${ROLE_TO_ASSUME}" "${aws_profile}" "${region_dir}"
        copy_dependency_to_internals \
            "${INTERNALS_SERVICE}" \
            "$TOOLS_DIR/caf-build-agent/components/module/linkfiles/pipeline_providers/aws/aws_pipeline-to-aws_cloud/codebuild/common/specs/actions/codebuild/buildspec.yml" \
            "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}/internals/${INTERNALS_SERVICE}/provider/aws/terragrunt/env/${TARGETENV}/${deploy_dir}" \
            "https://github.com/nexient-llc/git-webhook-lambda.git" \
            "${CODEBUILD_SRC_DIR}/git-webhook"
        cd "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}/internals/${INTERNALS_SERVICE}/provider/aws/terragrunt/env/${TARGETENV}/${deploy_dir}/" || exit 1
        run_terragrunt_init
        if [ "$type" == "plan" ]; then
            run_terragrunt_plan
        else
            run_terragrunt_apply
        fi
    done
}

function terragrunt_service {
    local type=$1

    cd "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}/env/${TARGETENV}/" || exit 1
    find . -mindepth 2 -maxdepth 2 -type d | sed 's|^\.||' | while IFS= read -r dir; do
        deploy_dir="${dir#/}"
        region_dir="${deploy_dir%%/*}"
        aws_profile=$(get_accounts_profile "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}/accounts.json" "${TARGETENV}")
        assume_iam_role "${ROLE_TO_ASSUME}" "${aws_profile}" "${region_dir}"
        cd "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}/env/${TARGETENV}/${deploy_dir}/" || exit 1
        find ${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}${PROPERTIES_REPO_SUFFIX}/env/${TARGETENV}/${deploy_dir}/ -type f -exec cp -- {} ${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}/env/${TARGETENV}/${deploy_dir}/ \;
        run_terragrunt_init
        if [ "$type" == "plan" ]; then
            run_terragrunt_plan
        else
            run_terragrunt_apply
        fi
    done
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
        create_global_vars_script \
            "${MERGE_COMMIT_ID}" \
            "${LATEST_COMMIT_HASH}" \
            "${GIT_PROJECT}" \
            "${GIT_REPO}" \
            "${FROM_BRANCH}" \
            "${TO_BRANCH}" \
            "${PROPERTIES_REPO_SUFFIX}" \
            "${GIT_SERVER_URL}" \
            "${IMAGE_TAG}" \
            "${SERVICE_COMMIT}" \
            "${CODEBUILD_SRC_DIR}" \
            "${CODEBUILD_WEBHOOK_MERGE_COMMIT}" \
            "${CODEBUILD_WEBHOOK_BASE_REF}" \
            "${CODEBUILD_WEBHOOK_HEAD_REF}" \
            "${CODEBUILD_SOURCE_REPO_URL}" \
            "${GIT_ORG}"
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
    create_global_vars_script \
        "${MERGE_COMMIT_ID}" \
        "${LATEST_COMMIT_HASH}" \
        "${GIT_PROJECT}" \
        "${GIT_REPO}" \
        "${FROM_BRANCH}" \
        "${TO_BRANCH}" \
        "${PROPERTIES_REPO_SUFFIX}" \
        "${GIT_SERVER_URL}" \
        "${IMAGE_TAG}" \
        "${SERVICE_COMMIT}" \
        "${CODEBUILD_SRC_DIR}" \
        "${CODEBUILD_WEBHOOK_MERGE_COMMIT}" \
        "${CODEBUILD_WEBHOOK_BASE_REF}" \
        "${CODEBUILD_WEBHOOK_HEAD_REF}" \
        "${CODEBUILD_SOURCE_REPO_URL}" \
        "${GIT_ORG}"
    git_checkout \
        "${MERGE_COMMIT_ID}" \
        "${CODEBUILD_SRC_DIR}/${GIT_REPO}"
    if [ "${IGNORE_INTERNALS}" != "true" ] && check_git_changes_for_internals "${MERGE_COMMIT_ID}" "${BUILD_BRANCH}"; then
        export USERVAR_S3_CODEPIPELINE_BUCKET=${INTERNALS_CODEPIPELINE_BUCKET}
    fi
    copy_zip_to_s3_bucket "${USERVAR_S3_CODEPIPELINE_BUCKET}" "${CODEBUILD_SRC_DIR}"
}

function codebuild_status {
    set_vars_from_script "${CODEBUILD_SRC_DIR}/set_vars.sh"
    codebuild_status_callback \
        "${MERGE_COMMIT_ID}" 
        "${GIT_SERVER_URL}" 
        "${GIT_USERNAME}" 
        "${GIT_TOKEN}" 
        "${IS_PIPELINE_LAST_STAGE}" 
        "${CODEBUILD_BUILD_SUCCEEDING}" 
        "${CODEBUILD_BUILD_URL}" 
        "${CODEBUILD_BUILD_ID}"
}

function set_vars_script_and_clone_service {
    set_vars_from_script "${CODEBUILD_SRC_DIR}/set_vars.sh" "${BUILD_BRANCH}"

    if [ -z "$GIT_SERVER_URL" ]; then
        if [ -z "$CODEBUILD_SOURCE_REPO_URL" ]; then
            echo "[ERROR] cannot find repository url"
        else
            protocol="${CODEBUILD_SOURCE_REPO_URL%%://*}://"
            domain="${CODEBUILD_SOURCE_REPO_URL#*://}"
            base="${domain%%/*}"
            export GIT_SERVER_URL="$protocol$base"
            export GIT_REPO=$(echo "$CODEBUILD_SOURCE_REPO_URL" | sed 's|.*/||' | sed "s/\.git$//")
        fi
    fi
    if [ -z "$GIT_ORG" ]; then
        if [ -z "$CODEBUILD_SOURCE_REPO_URL" ]; then
            echo "[ERROR] cannot find repository url"
            export GIT_ORG="scm/${GIT_PROJECT}"
        else
            domain="${CODEBUILD_SOURCE_REPO_URL#*://}"
            base="${domain%%/*}"
            export GIT_ORG=$(echo "${domain}" | sed "s/^${base}\///" | sed "s/\/${GIT_REPO}\.git$//")
        fi
    fi
    if [ -z "$CODEBUILD_WEBHOOK_MERGE_COMMIT" ]; then
        export MERGE_COMMIT_ID="${CODEBUILD_WEBHOOK_MERGE_COMMIT}"
    fi

    export PROPERTIES_REPO_SUFFIX="-${CODEBUILD_WEBHOOK_MERGE_COMMIT:-properties}"
    export FROM_BRANCH="${FROM_BRANCH:-${CODEBUILD_WEBHOOK_HEAD_REF:-$FROM_BRANCH}}"
    export TO_BRANCH="${CODEBUILD_WEBHOOK_BASE_REF:-$TO_BRANCH}"

    git_clone_service
    git_clone_service_properties
    set_commit_vars
}

function set_commit_vars {
    if [ -z "$LATEST_COMMIT_HASH" ]; then
        if [ "$GIT_REPO" == "${GIT_REPO%"$PROPERTIES_REPO_SUFFIX"}" ]; then
            export LATEST_COMMIT_HASH="${SERVICE_COMMIT}"
        else
            export LATEST_COMMIT_HASH="${PROPS_COMMIT}"
        fi
    fi

    if [ -z "$MERGE_COMMIT_ID" ]; then
        MERGE_COMMIT_ID=$(git -C "${CODEBUILD_SRC_DIR}/${GIT_REPO}" rev-parse "${FROM_BRANCH}")
    fi
}

function git_clone_service {
    local trimmed_git_url="${GIT_SERVER_URL#https://}/${GIT_ORG}/${GIT_REPO}.git"
    git_config "${GIT_USERNAME}@${GIT_EMAIL_DOMAIN}" "${GIT_USERNAME}"
    git_clone \
        "$SVC_BRANCH" \
        "https://$GIT_USERNAME:$GIT_TOKEN@${trimmed_git_url}" \
        "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}" &&
        SERVICE_COMMIT=$(git -C "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}" rev-parse HEAD)
    export SERVICE_COMMIT
    echo "${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"} HEAD commit: ${SERVICE_COMMIT}"
}

function git_clone_service_properties {
    local trimmed_git_url="${GIT_SERVER_URL#https://}/${GIT_ORG}/${GIT_REPO}.git"
    git_clone \
        "$SVC_PROP_BRANCH" \
        "https://$GIT_USERNAME:$GIT_TOKEN@${trimmed_git_url%.git}${PROPERTIES_REPO_SUFFIX}.git" \
        "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}${PROPERTIES_REPO_SUFFIX}" &&
        PROPS_COMMIT=$(git -C "${CODEBUILD_SRC_DIR}/${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}${PROPERTIES_REPO_SUFFIX}" rev-parse HEAD)
    export PROPS_COMMIT
    echo "${GIT_REPO%"${PROPERTIES_REPO_SUFFIX}"}${PROPERTIES_REPO_SUFFIX} HEAD commit: ${PROPS_COMMIT}"
}
