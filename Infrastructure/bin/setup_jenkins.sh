#!/bin/bash
# Setup Jenkins Project
if [ "$#" -ne 3 ]; then
    echo "Usage:"
    echo "  $0 GUID REPO CLUSTER"
    echo "  Example: $0 wkha https://github.com/wkulhanek/ParksMap na39.openshift.opentlc.com"
    exit 1
fi

GUID=$1
REPO=$2
CLUSTER=$3
echo "Setting up Jenkins in project ${GUID}-jenkins from Git Repo ${REPO} for Cluster ${CLUSTER}"

# Code to set up the Jenkins project to execute the
# three pipelines.
# This will need to also build the custom Maven Slave Pod
# Image to be used in the pipelines.
# Finally the script needs to create three OpenShift Build
# Configurations in the Jenkins Project to build the
# three micro services. Expected name of the build configs:
# * mlbparks-pipeline
# * nationalparks-pipeline
# * parksmap-pipeline
# The build configurations need to have two environment variables to be passed to the Pipeline:
# * GUID: the GUID used in all the projects
# * CLUSTER: the base url of the cluster used (e.g. na39.openshift.opentlc.com)

occmd="oc -n ${GUID}-parks-prod "

TEMPLATES_ROOT=$(dirname $0)/../templates

new_build() {
    local bc_name=$1
    local context_dir=$2
    
    ${occmd} new-build ${REPO} \
       --name=${bc_name} --strategy=pipeline --context-dir=${context_dir}

    ${occmd} cancel-build bc/${bc_name}
    ${occmd} set env bc/${bc_name} CLUSTER=${CLUSTER} GUID=${GUID}
}

${occmd} new-app ${TEMPLATES_ROOT}/advdev-jenkins-template.yml && \
    ${occmd} rollout status dc/$(${occmd} get dc -o jsonpath='{ .items[0].metadata.name }') -w 

cat ${TEMPLATES_ROOT}/jenkins-slave-appdev.Dockerfile | ${occmd} new-build --name=jenkins-slave-appdev -D - 

new_build "mlbparks-pipeline" "MLBParks"
new_build "nationalparks-pipeline" "Nationalparks"
new_build "parksmap-pipeline" "ParksMap"

