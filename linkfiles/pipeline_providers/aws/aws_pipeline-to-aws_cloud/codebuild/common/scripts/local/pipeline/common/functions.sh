#!/bin/bash

function set_vars_from_script {
    if [ -f "$1" ]; then
        echo "Making $1 script executable and running it"
        cat "$1"
        chmod +x "$1"
        # shellcheck source=/dev/null
        source "$1"
    else
        echo "Could not find $1"
    fi
    if [ -z "$2" ]; then
        echo "Branch var is empty or not passed: $2"
    else
        if [ "$2" == "$TO_BRANCH" ]; then
            echo "TO_BRANCH is equal to branch: $2"
        else
            echo "[ERROR] TO_BRANCH is not equal to branch: $2"
            exit 1
        fi
    fi
    if [ -z "$ENV_AWS_REGION" ]; then 
        ENV_AWS_REGION="${AWS_REGION}"
    fi
}

function get_secret_manager_secret {
    echo "Retrieving git secret for: $1"
    local return_var
    return_var="$(aws secretsmanager get-secret-value --secret-id "$1" --region "$2" | jq -r '.SecretString')"
    echo "$return_var"
}

function install_asdf {
    echo "Sourcing ASDF"
    source "$1/.asdf/asdf.sh"
}

function git_clone {
    echo "Cloning repo: $1"
    if [ -z "$7" ]; then 
        git clone "https://$2:$3@$4/scm/$5/$1.git" "$6"
    else
        git clone -b "$7" "https://$2:$3@$4/scm/$5/$1.git" "$6"
    fi
}

function git_checkout {
    echo "cd $2"
    cd "$2" || exit 1
    if [ -z "$3" ]; then 
        echo "git checkout $1"
        git checkout "$1"
    else
        echo "git checkout -b $1"
        git checkout -b "$1"
    fi
}

function git_merge {
    echo "git merge from branch $1"
    cd "$2" || exit 1
    git merge "$1"
}

function git_push {
    echo "git push"
    cd "$1" || exit 1
    git push --set-upstream origin "$2"
}

function git_commit {
    cd "$1" || exit 1
    git add .
    if [ -z "$2" ]; then 
        export message="AWS CodeBuild linting, formatting, and recommiting."
    else
        message="$2"
    fi
    echo "git commit with message: $2"
    git commit -m "${message}"
}

function git_status_porcelain_changes {
    echo "Running git status --porcelain"
    if [ -n "$(git status --porcelain)" ]; then
        echo "there are detectable git changes"
        return 0
    else
        echo "No changes found"
        return 1
    fi
}

function sim_merge {
    echo "Simulated merge from branch $1"
    cd "$2" || exit 1
    git merge --no-commit --no-ff "$1"
}

function git_config {
    echo "Configuring git"
    if [ -z "$1" ]; then 
        user_email="codebuild@aws.com"
        user_name="Codebuild"
    else
        user_email="$1"
        user_name="$2"
    fi
    git config --global user.name "${user_name}"
    git config --global user.email "${user_email}"
}

function tool_versions_install {
    echo 'Installing all asdf plugins under .tool-versions'
    cd "$1" || exit 1
    while IFS= read -r line; do asdf plugin add "$(echo "$line" | awk '{print $1}')" || true; done < .tool-versions
    asdf install
}

function assume_iam_role {
    echo "Assuming the IAM deployment role"
    sts_creds=$(aws sts assume-role --role-arn "$1" --role-session-name CodeBuildTerragruntDeployCrossAccountRole)
    access_key=$(echo "${sts_creds}" | jq -r '.Credentials.AccessKeyId')
    secret_access_key=$(echo "${sts_creds}" | jq -r '.Credentials.SecretAccessKey')
    session_token=$(echo "${sts_creds}" | jq -r '.Credentials.SessionToken')
    aws configure set profile."$2".aws_access_key_id "${access_key}"
    aws configure set profile."$2".aws_secret_access_key "${secret_access_key}"
    aws configure set profile."$2".aws_session_token "${session_token}"
    aws configure set profile."$2".region "$3" 
}

function get_accounts_profile {
    if [ -f  "$1" ]; then 
        aws_profile=$(jq -r ".$2" $1)
        echo "${aws_profile}"
    else
        echo "accounts.json not found"
        exit 1
    fi
}

function set_netrc {
    echo "Setting ~/.netrc variables"
    {   echo "machine $1"; 
        echo "login $2"; 
        echo "password $3"; 
    }  >> ~/.netrc
    chmod 600 ~/.netrc
}

function run_terragrunt_init {
    echo "Running terragrunt init"
    terragrunt init  --terragrunt-non-interactive
}

function run_terragrunt_plan {
    echo "Running terragrunt plan"
    if [ -z "$1" ]; then 
        terragrunt plan
    else
        terragrunt plan -out "$1"
    fi
}

function run_terragrunt_apply {
    echo "Running terragrunt apply"
    if [ -z "$1" ]; then 
        terragrunt apply -auto-approve 
    else
        terragrunt apply -var-file "$1" -auto-approve 
    fi
}

function codebuild_status_callback {
    if [ $6 -eq 1 ]; then build_status="SUCCESSFUL"; else build_status="FAILED"; fi
    payload="{\"state\""':'"\"${build_status}\", \
        \"key\""':'"\"$1\", \
        \"url\""':'"\"$7\", \
        \"name\""':'"\"$1""\", \
        \"description\""':'"\"Build $8 completed with status ${build_status}\"}"
    header="Content-Type"':'" application/json"
    if [ "${build_status}" == "FAILED" ] || [ "$5" == "true" ]; then
        curl -u "$3"':'"$4" -H "${header}" -d "${payload}" "https://$2/rest/build-status/1.0/commits/$1" -v
    fi
    echo "Codebuild finished with status:${build_status}"
}

function cd_deploy_dir {
    echo "Changing dir to deploy: $1"
    cd "$1" || exit 1
}

function copy_dependency_to_internals {
    if [ "$1" == "pipelines" ]; then
        INTERNALS_FILE="$2/caf-build-agent/components/module/linkfiles/pipeline_providers/aws/aws_pipeline-to-aws_cloud/codebuild/common/specs/actions/codebuild/buildspec.yml"
    else
        cd "$2/caf-build-agent/components/git-webhook-lambda" || exit 1
        pwd
        # shellcheck source=/dev/null
        source "./build_deployable_zip.sh"
        INTERNALS_FILE="./lambda.zip"
    fi
    echo "Copying $1 to $3"
    cp "${INTERNALS_FILE}" "$3"
}

function create_global_vars_script {
    echo "Creating shell script with global variables"
    cd "${11}" || exit 1
    if [ -z "$1" ]; then 
        MERGE_COMMIT_ID="$2";
    else
        MERGE_COMMIT_ID="$1";
    fi
    if [ "$4" != "${4%"$7"}" ]; then
        SERVICE_COMMIT="${10}";
    else
        SERVICE_COMMIT="${MERGE_COMMIT_ID}";
    fi
    if [ -z "$9" ]; then 
        IMAGE_TAG="${SERVICE_COMMIT}";
    else
        IMAGE_TAG="${9}-${SERVICE_COMMIT}";
    fi
    {   echo "export GIT_PROJECT=\"$3\"";
        echo "export GIT_REPO=\"$4\"";
        echo "export FROM_BRANCH=\"$5\"";
        echo "export TO_BRANCH=\"$6\"";
        echo "export MERGE_COMMIT_ID=\"${MERGE_COMMIT_ID}\"";
        echo "export CONTAINER_IMAGE_NAME=\"$4\"";
        echo "export GIT_SERVER_URL=\"${8#https://}\"";
        echo "export IMAGE_TAG=\"$IMAGE_TAG\""; 
    } >> vars.sh
    mv -f vars.sh set_vars.sh
}

function copy_zip_to_s3_bucket {
    echo "Copying shell script to S3 bucket:$1"
    cd "$2" || exit 1
    zip -r "trigger_pipeline.zip" "set_vars.sh"
    aws s3 rm "s3://$1" --recursive
    aws s3 cp "trigger_pipeline.zip" "s3://$1"
}

function check_git_changes_for_internals {
    MAIN_BRANCH="${2:-main}"
    echo "Checking if git changes are in the 'internals' folder."

    git fetch origin

    if [ "$1" = "$(git rev-parse "origin/$MAIN_BRANCH")" ]; then
        echo "Commit hash is the same as origin/${MAIN_BRANCH}"
        INTERNALS_DIFF=$(git diff "origin/$MAIN_BRANCH^" "origin/$MAIN_BRANCH" -- "internals")
        if [[ -z "${INTERNALS_DIFF}" ]]; then
            echo "No git changes found in 'internals' folder"
            return 1
        else
            OUTSIDE_INTERNALS_DIFF=$(git diff "origin/$MAIN_BRANCH^" "origin/$MAIN_BRANCH" --name-only | grep -v '^internals/')
            if [[ -n "${OUTSIDE_INTERNALS_DIFF}" ]]; then
                echo "Changes found both inside and outside 'internals' folder."
                exit 1
            else
                echo "Git changes only found in 'internals' folder"
                return 0
            fi
        fi
    else
        INTERNALS_DIFF=$(git diff "$1" "origin/$MAIN_BRANCH" -- "internals")
        if [[ -z "${INTERNALS_DIFF}" ]]; then
            echo "No git changes found in 'internals' folder"
            return 1
        else
            OUTSIDE_INTERNALS_DIFF=$(git diff "$1" origin/$MAIN_BRANCH --name-only | grep -v '^internals/')
            if [[ -n "${OUTSIDE_INTERNALS_DIFF}" ]]; then
                echo "Changes found both inside and outside 'internals' folder."
                exit 1
            else
                echo "Git changes only found in 'internals' folder"
                return 0
            fi
        fi
    fi
}

function add_git_tag {
    echo "Adding git tag: $1"
    cd "$3" || exit 1
    git tag -a "$1" -m "$2"
    git push "$1"
}

function increment_git_tag {
    cd "$1" || exit 1
    
    latest=$(git tag | sort -V | tail -n 1)

    if [[ -z "$latest" ]]; then
        echo "0.1.0"
        return
    fi

    major="$(echo "$latest" | cut -d. -f1)"
    minor="$(echo "$latest" | cut -d. -f2)"
    patch="$(echo "$latest" | cut -d. -f3)"

    patch=$((patch + 1))

    echo "$major.$minor.$patch"
}

function rollback_env {
    echo "Rolling back to git tag: $1"
    cd "$3" || exit 1
    CERTIFIED_COMMIT=$(git log --format='%H' --tags="$1-*" --no-walk | head -n1)
    if [ "${CERTIFIED_COMMIT}" == "$2" ] || [ -z "${CERTIFIED_COMMIT}" ]; then
        echo "[ERROR] Rollback failed."
        exit 1
    fi
    echo "${CERTIFIED_COMMIT}"
}

function run_make_configure {
    echo "Running make configure"
    make configure
}

function run_make_git_config {
    echo "Running make git-config"
    make git-config
}

function run_make_check {
    echo "Running make check"
    make check
}

function run_make_codebuild_ca_token {
    echo "Running make codebuild_ca_token"
    make codebuild_ca_token
}

function tag_shared_service {
    echo "Adding tags to shared service."
    yq e ".tags.shared_service_name = \"$1\"" inputs.yaml -i
    yq e ".tags.shared_service_version = \"$2\"" inputs.yaml -i
    yq e ".tags.properties_version = \"$3\"" inputs.yaml -i
}

function end_stage_if_properties_trigger {
    if [ "$1" != "${1%"$2"}" ]; then
        echo "$2 repo found to trigger pipeline: $1"
        echo "Exiting stage as successful"
        exit 0
    fi
}


function get_properties_suffix {
    if [ -z "$1" ]; then 
        echo "-properties"
    else
        echo "$1"
    fi
}

# TODO: Stubs

function run_post_deploy_functional_test {
    echo "TODO: Running post deploy functional test."
    if [ "$1" == "true" ]; then
        echo "Failure"
        return 1
    fi
    echo "Success"
    return 0
}

function run_pre_deploy_functional_test {
    echo "TODO: Running pre deploy functional test."
}
