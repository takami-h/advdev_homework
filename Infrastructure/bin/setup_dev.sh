#!/bin/bash
# Setup Development Project
if [ "$#" -ne 1 ]; then
    echo "Usage:"
    echo "  $0 GUID"
    exit 1
fi

GUID=$1
echo "Setting up Parks Development Environment in project ${GUID}-parks-dev"

# Code to set up the parks development project.

setup_app() {
    local app_name=$1
    local s2i_builder=$2
    local type_label=$3
    
    oc new-build --binary=true --name=${app_name} ${s2i_builder}
    oc new-app ${GUID}-parks-dev/${app_name}:0.0-0 --allow-missing-imagestream-tags=true \
       --name=${app_name} -l type=${type_label}
    oc set triggers dc/${app_name} --remove-all

    oc expose dc/${app_name} --port 8080

    oc set probe dc/${app_name} --readiness \
       --initial-delay-seconds 30 \
       --failure-threshold 3 \
       --get-url=http://:8080/ws/healthz/
    oc set probe dc/${app_name} --liveness \
       --initial-delay-seconds 30 \
       --failure-threshold 3 \
       --get-url=http://:8080/ws/healthz/
}

setup_mongodb() {
    echo "Setting up MongoDB for backend apps"
    oc new-app mongodb-persistent --name=mongodb \
       --param=MONGODB_USER=mongodb \
       --param=MONGODB_PASSWORD=mongodb \
       --param=MONGODB_DATABASE=parks

    oc create configmap parksdb-config \
       --from-literal=DB_HOST=mongodb \
       --from-literal=DB_PORT=27017 \
       --from-literal=DB_USERNAME=mongodb \
       --from-literal=DB_PASSWORD=mongodb \
       --from-literal=DB_NAME=parks
}

setup_mlbparks() {
    echo "Setting up MLBParks backend app"

    setup_app "mlbparks" "jboss-eap70-openshift:1.7" "parksmap-backend"

    oc create configmap mlbparks-config \
       --from-literal=APPNAME="MLB Parks (Dev)"
    oc set env dc/mlbparks --from=configmap/parksdb-config
    oc set env dc/mlbparks --from=configmap/mlbparks-config

    oc set deployment-hook dc/mlbparks --post \
       -- curl -s http://mlbparks:8080/ws/data/load/
}

setup_nationalparks() {
    echo "Setting up Nationalparks backend app"

    setup_app "nationalparks" "redhat-openjdk18-openshift:1.2" "parksmap-backend"

    oc create configmap nationalparks-config \
       --from-literal=APPNAME="National Parks (Dev)"
    oc set env dc/nationalparks --from=configmap/parksdb-config
    oc set env dc/nationalparks --from=configmap/nationalparks-config
    
    oc set deployment-hook dc/nationalparks --post \
       -- curl -s http://nationalparks:8080/ws/data/load/
}

setup_parksmap() {
    echo "Setting up Parksmap frontend web app"

    oc policy add-role-to-user view --serviceaccount=default
    setup_app "parksmap" "redhat-openjdk18-openshift:1.2" "parksmap-frontend"

    oc create configmap parksmap-config \
       --from-literal=APPNAME="ParksMap (Dev)"
    oc set env dc/parksmap --from=configmap/parksmap-config

    oc expose svc/parksmap
}

oc project ${GUID}-parks-dev

oc policy add-role-to-user edit system:serviceaccount:${GUID}-jenkins:jenkins

setup_mongodb

setup_mlbparks
setup_nationalparks
setup_parksmap
