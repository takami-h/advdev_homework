#!/bin/bash
# Setup Production Project (initial active services: Green)
if [ "$#" -ne 1 ]; then
    echo "Usage:"
    echo "  $0 GUID"
    exit 1
fi

GUID=$1
echo "Setting up Parks Production Environment in project ${GUID}-parks-prod"

# Code to set up the parks production project. It will need a StatefulSet MongoDB, and two applications each (Blue/Green) for NationalParks, MLBParks and Parksmap.
# The Green services/routes need to be active initially to guarantee a successful grading pipeline run.

occmd="oc -n ${GUID}-parks-prod "

TEMPLATES_ROOT=$(dirname $0)/../templates

setup_app() {
    local app_name=$1
    local app_display_name=$2
    local image=$3
    local type_label=$4

    ${occmd} new-app ${image} --allow-missing-images=true --allow-missing-imagestream-tags=true \
       --name=${app_name} -l type=${type_label}
    ${occmd} set triggers dc/${app_name} --remove-all
    ${occmd} rollout cancel dc/${app_name}

    ${occmd} expose dc/${app_name} --port 8080

    ${occmd} set probe dc/${app_name} --readiness \
       --initial-delay-seconds 30 \
       --failure-threshold 3 \
       --get-url=http://:8080/ws/healthz/
    ${occmd} set probe dc/${app_name} --liveness \
       --initial-delay-seconds 30 \
       --failure-threshold 3 \
       --get-url=http://:8080/ws/healthz/

    ${occmd} create configmap ${app_name}-config \
       --from-literal=APPNAME="${app_display_name}"
    ${occmd} set env dc/${app_name} --from=configmap/${app_name}-config
}

setup_parks_backend() {
    local app_name=$1
    local app_display_name=$2
    local image=$3
    local type_label=$4
    
    echo "Setting up ${app_display_name} backend app"

    setup_app ${app_name} "${app_display_name}" ${image} ${type_label}
    ${occmd} set env dc/${app_name} --from=configmap/parksdb-config

    ${occmd} set deployment-hook dc/${app_name} --post \
       -- curl -s http://${app_name}:8080/ws/data/load/
}

setup_mongodb() {
    echo "Setting up MongoDB for backend apps"
    ${occmd} create -f ${TEMPLATES_ROOT}/mongodb-internal.svc.yml
    ${occmd} create -f ${TEMPLATES_ROOT}/mongodb.svc.yml
    ${occmd} create -f ${TEMPLATES_ROOT}/mongodb.statefulset.yml

    ${occmd} rollout status dc/mongodb -w

    ${occmd} create configmap parksdb-config \
       --from-literal=DB_HOST=mongodb \
       --from-literal=DB_PORT=27017 \
       --from-literal=DB_USERNAME=mongodb \
       --from-literal=DB_PASSWORD=mongodb \
       --from-literal=DB_NAME=parks \
       --from-literal=DB_REPLICASET=rs0
}

oc policy add-role-to-group system:image-puller system:serviceaccounts:${GUID}-parks-prod -n ${GUID}-parks-dev
oc policy add-role-to-user edit system:serviceaccount:${GUID}-jenkins:jenkins -n ${GUID}-parks-prod

setup_mongodb

setup_parks_backend "mlbparks-blue"  "MLB Parks (Blue)"  "${GUID}-parks-dev/mlbparks:0.0" "parksmap-backend-standby"
setup_parks_backend "mlbparks-green" "MLB Parks (Green)" "${GUID}-parks-dev/mlbparks:0.0" "parksmap-backend"

setup_parks_backend "nationalparks-blue"   "National Parks (Blue)"   "${GUID}-parks-dev/nationalparks:0.0" "parksmap-backend-standby"
setup_parks_backend "nationalparks-green"  "National Parks (Green)"  "${GUID}-parks-dev/nationalparks:0.0" "parksmap-backend"

oc policy add-role-to-user view --serviceaccount=default -n ${GUID}-parks-prod
setup_app "parksmap-blue"  "ParksMap (Blue)"   "${GUID}-parks-dev/parksmap:0.0" "parksmap-frontend"
setup_app "parksmap-green" "ParksMap (Green)"  "${GUID}-parks-dev/parksmap:0.0" "parksmap-frontend"
${occmd} expose svc/parksmap-green --name parksmap

