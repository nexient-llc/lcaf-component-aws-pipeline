#!/bin/bash

function set_vars_from_script {
    local vars_script=$1
    local dir=$2

    if [ -f "$vars_script" ]; then
        echo "Making $1 script executable and running it"
        cat "$vars_script"
        chmod +x "$vars_script"
        # shellcheck source=/dev/null
        source "$vars_script"
    else
        echo "Could not find $vars_script"
    fi
    if [ -z "$dir" ]; then
        echo "Branch var is empty or not passed: $dir"
    else
        if [ "$dir" == "$TO_BRANCH" ]; then
            echo "TO_BRANCH is equal to branch: $dir"
        else
            echo "[ERROR] TO_BRANCH is not equal to branch: $dir"
            exit 1
        fi
    fi
    if [ -z "$ENV_AWS_REGION" ]; then 
        ENV_AWS_REGION="${AWS_REGION}"
    fi
}

function install_asdf {
    local dir=$1

    echo "Sourcing ASDF"
    # shellcheck source=/dev/null
    source "$dir/.asdf/asdf.sh"
}

function install_asdf {
    local dir=$1

    echo "Sourcing ASDF"
    # shellcheck source=/dev/null
    source "$dir/.asdf/asdf.sh"
}

function git_clone {
    local branch=$1
    local clone_uri=$2
    local dir=$3

    echo "Cloning repo: $clone_uri"
    if [ -z "$branch" ]; then 
        git clone "$clone_uri" "$dir"
    else
        git clone -b "$branch" "$clone_uri" "$dir"
    fi
}

function git_checkout {
    local repository=$1
    local dir=$2
    local local_branch=$3

    echo "cd $dir"
    cd "$dir" || exit 1
    if [ -z "$local_branch" ]; then 
        echo "git checkout $repository"
        git checkout "$repository"
    else
        echo "git checkout -b $repository"
        git checkout -b "$repository"
    fi
}

function git_merge {
    local branch=$1
    local dir=$2

    echo "git merge from branch $branch"
    cd "$dir" || exit 1
    git merge "$branch"
}

function git_push {
    local dir=$1
    local branch=$2
    
    echo "git push"
    cd "$dir" || exit 1
    git push --set-upstream origin "$branch"
}

function git_commit {
    local dir=$1
    local message=$2

    cd "$dir" || exit 1
    git add .
    if [ -z "$message" ]; then 
        message="Build-agent commit."
    fi
    echo "git commit with message: $message"
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
    local branch=$1
    local dir=$2

    echo "Simulated merge from branch $branch"
    cd "$dir" || exit 1
    git merge --no-commit --no-ff "$branch"
}

function git_config {
    local user_email=$1
    local user_name=$2

    echo "Configuring git"
    if [ -z "$user_email" ]; then 
        user_email="nobody@nttdata.com"
    fi
    if [ -z "$user_name" ]; then 
        user_name="nobody"
    fi

    git config --global user.name "${user_name}"
    git config --global user.email "${user_email}"
}

function tool_versions_install {
    local dir=$1

    echo 'Installing all asdf plugins under .tool-versions'
    cd "$dir" || exit 1
    while IFS= read -r line; do asdf plugin add "$(echo "$line" | awk '{print $1}')" || true; done < .tool-versions
    asdf install
}

function assume_iam_role {
    local role_arn=$1
    local profile=$2
    local region=$3

    echo "Assuming the IAM deployment role"
    sts_creds=$(aws sts assume-role --role-arn "$role_arn" --role-session-name CodeBuildTerragruntDeployCrossAccountRole)
    access_key=$(echo "${sts_creds}" | jq -r '.Credentials.AccessKeyId')
    secret_access_key=$(echo "${sts_creds}" | jq -r '.Credentials.SecretAccessKey')
    session_token=$(echo "${sts_creds}" | jq -r '.Credentials.SessionToken')
    aws configure set profile."$profile".aws_access_key_id "${access_key}"
    aws configure set profile."$profile".aws_secret_access_key "${secret_access_key}"
    aws configure set profile."$profile".aws_session_token "${session_token}"
    aws configure set profile."$profile".region "$region" 
}

function get_accounts_profile {
    local accounts_json_path=$1
    local target_env=$2

    if [ -f  "$accounts_json_path" ]; then 
        aws_profile=$(jq -r ".$target_env" $accounts_json_path)
        echo "${aws_profile}"
    else
        echo "accounts.json not found"
        exit 1
    fi
}

function set_netrc {
    local machine=$1
    local login=$2
    local password=$3

    echo "Setting ~/.netrc variables"
    {   echo "machine $machine"; 
        echo "login $login"; 
        echo "password $password"; 
    }  >> ~/.netrc
    chmod 600 ~/.netrc
}

function run_terragrunt_init {
    echo "Running terragrunt init"
    terragrunt init  --terragrunt-non-interactive
}

function run_terragrunt_plan {
    local out_filename=$1

    echo "Running terragrunt plan"
    if [ -z "$out_filename" ]; then 
        terragrunt plan
    else
        terragrunt plan -out "$out_filename"
    fi
}

function run_terragrunt_apply {
    local var_filename=$1

    echo "Running terragrunt apply"
    if [ -z "$var_filename" ]; then 
        terragrunt apply -auto-approve 
    else
        terragrunt apply -var-file "$var_filename" -auto-approve 
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
    local merge_commit_id=$1
    local latest_commit_hash=$2
    local git_repo=$4
    local from_branch=$5
    local to_branch=$6
    local properties_repo_suffix=$7
    local git_server_url=$8
    local image_tag=$9
    local service_commit=${10}
    local codebuild_src_dir=${11}

    echo "Creating shell script with global variables"1
    cd "$codebuild_src_dir" || exit 1
    if [ -z "$merge_commit_id" ]; then 
        commit_id="$latest_commit_hash";
    else
        commit_id="$merge_commit_id";
    fi
    if [ "$git_repo" != "${git_repo%"$properties_repo_suffix"}" ]; then
        svc_commit="${service_commit}";
    else
        svc_commit="${commit_id}";
    fi
    if [ -z "$image_tag" ]; then 
        tag="${svc_commit}";
    else
        tag="${image_tag}-${svc_commit}";
    fi
    {   echo "export GIT_REPO=\"$git_repo\"";
        echo "export FROM_BRANCH=\"$from_branch\"";
        echo "export TO_BRANCH=\"$to_branch\"";
        echo "export MERGE_COMMIT_ID=\"${commit_id}\"";
        echo "export CONTAINER_IMAGE_NAME=\"$git_repo\"";
        echo "export GIT_SERVER_URL=\"${git_server_url#https://}\"";
        echo "export IMAGE_TAG=\"$tag\""; 
    } >> vars.sh
    mv -f vars.sh set_vars.sh
}

function copy_zip_to_s3_bucket {
    local s3_bucket=$1
    local dir=$2

    echo "Copying shell script to S3 bucket:$s3_bucket"
    cd "$dir" || exit 1
    zip -r "trigger_pipeline.zip" "set_vars.sh"
    aws s3 rm "s3://$s3_bucket" --recursive
    aws s3 cp "trigger_pipeline.zip" "s3://$s3_bucket"
}

function check_git_changes_for_internals {
    local commit_id=$1
    local main_branch="${2:-main}"
    local internals_diff

    echo "Checking if git changes are in the 'internals' folder."

    git fetch origin

    if [ "$commit_id" = "$(git rev-parse "origin/$main_branch")" ]; then
        echo "Commit hash is the same as origin/${main_branch}"
        internals_diff=$(git diff "origin/$main_branch^" "origin/$MAIN_BRANCH" -- "internals")
        if [[ -z "${internals_diff}" ]]; then
            echo "No git changes found in 'internals' folder"
            return 1
        else
            outside_internals_diff=$(git diff "origin/$main_branch^" "origin/$main_branch" --name-only | grep -v '^internals/')
            if [[ -n "${outside_internals_diff}" ]]; then
                echo "Changes found both inside and outside 'internals' folder."
                exit 1
            else
                echo "Git changes only found in 'internals' folder"
                return 0
            fi
        fi
    else
        internals_diff=$(git diff "$1" "origin/$main_branch" -- "internals")
        if [[ -z "${internals_diff}" ]]; then
            echo "No git changes found in 'internals' folder"
            return 1
        else
            outside_internals_diff=$(git diff "$1" "origin/$main_branch" --name-only | grep -v '^internals/')
            if [[ -n "${outside_internals_diff}" ]]; then
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
    local git_tag=$1
    local commit_id=$2
    local dir=$3

    echo "Adding git tag: $git_tag"
    cd "$dir" || exit 1
    git tag -a "$git_tag" -m "$commit_id"
    git push "$git_tag"
}

function rollback_env {
    local git_tag=$1
    local commit_id=$2
    local dir=$3

    echo "Rolling back to git tag: $git_tag"
    cd "$dir" || exit 1
    CERTIFIED_COMMIT=$(git log --format='%H' --tags="$git_tag-*" --no-walk | head -n1)
    if [ "${CERTIFIED_COMMIT}" == "$commit_id" ] || [ -z "${CERTIFIED_COMMIT}" ]; then
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

function end_stage_if_properties_trigger {
    local repository=$1
    local properties_suffix=$2

    if [ "$repository" != "${repository%"$properties_suffix"}" ]; then
        echo "$properties_suffix repo found to trigger pipeline: $repository"
        echo "Exiting stage as successful"
        exit 0
    fi
}

function get_properties_suffix {
    local suffix=$1

    if [ -z "$suffix" ]; then 
        echo "-properties"
    else
        echo "$suffix"
    fi
}

# TODO: Stubs

function run_post_deploy_functional_test {
    local test_failure=$1

    echo "TODO: Running post deploy functional test."
    if [ "$test_failure" == "true" ]; then
        echo "Failure"
        return 1
    fi
    echo "Success"
    return 0
}

function run_pre_deploy_functional_test {
    echo "TODO: Running pre deploy functional test."
}
