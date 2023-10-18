#!/bin/bash

function cp_docker_settings {
    # https://docs.aws.amazon.com/codebuild/latest/userguide/troubleshooting.html#troubleshooting-maven-repos
    cp ./settings.xml-DOCKERBUILD /root/.m2/settings.xml
}

function run_mvn_clean_install {
    echo "Running mvn clean install -DskipTests"
    mvn clean install -DskipTests
}

function run_mvn_test {
    echo "Running mvn test"
    mvn test
}
