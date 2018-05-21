#!/bin/bash

#The following configures a GKE cluster and creates the Halyard VM

#Ensure the following APIs are enabled
#Google Identity and Access Management (IAM) API
#Google Cloud Resource Manager API
#Google Pub/Sub API
#Kubernetes Engine API

PROJECT=deploy-manifest-poc
GCP_PROJECT=$(gcloud config get-value project)
RESOURCE_ROOT=~/.gcp
#Choose desired zone and GKE cluster name
GKE_ZONE=us-central1-f
GKE_NAME=shared-services
# Make sure the version configured is supported in the zone above
GKE_VERSION=1.9.7-gke.0
HALYARD_SCRIPT=setup-halyard-host
GCS_TEMPLATE=gcs-jinja.json

# Return random string length 5; used to randomize resource names
random_string () {
   echo $(od -vAn -N4 -tx < /dev/urandom) | sed -e 's/^[ \t]*//'
}

POSTFIX=$(random_string)
HALYARD_HOST=halyard-host-$POSTFIX
CLUSTER_NAME=$GKE_NAME-$POSTFIX
CLUSTER_RESOURCE=$RESOURCE_ROOT/$CLUSTER_NAME
SPIN_SA=spinnaker-sa-$POSTFIX
SPIN_SA_KEY=spinnaker-sa.json
HALYARD_SA=halyard-sa-$POSTFIX

# Create the Halyard vm to manage the spinnaker installation and other
# stack admin tasks
create_halyard_vm () {
    #Create Halyard VM
    gcloud compute instances create $HALYARD_HOST \
        --project=$GCP_PROJECT \
        --zone=$GKE_ZONE \
        --scopes=cloud-platform \
        --service-account=$1 \
        --image-project=ubuntu-os-cloud \
        --image-family=ubuntu-1404-lts \
        --machine-type=n1-standard-4
}

# Wait for halyard vm to come up based on the name provided
# timeout 10 tries
wait_for_halyard_vm () {
    VM_INFO=""
    COUNTER=0
    until [ "$VM_INFO" != "" ]; do
        VM_INFO=$(gcloud compute instances list --format text --filter="name=$1" | grep "deviceName")
        if [ "$VM_INFO" != "" ]
        then
            return 0
        fi
        if [ $COUNTER -gt 10 ]
        then
            return 1
        fi
        COUNTER=$((COUNTER+1))
        sleep 2
    done
}

# Get service account email pattern given a particular display name
get_sa_email () {
    SA_EMAIL=$(gcloud iam service-accounts list \
        --project=$GCP_PROJECT \
        --filter="displayName:$1" \
        --format='value(email)')
    echo $SA_EMAIL
}

# Create the GKE cluster and configure kubernetes service account
create_gke_cluster () {
    # Cluster exists when its resources are created; please note
    # on error cases the clean script needs to be run.
    if [ -d "$CLUSTER_RESOURCE" ]; then
        echo "Cluster exists... exiting."
        exit 1
    fi
    # Create cluster resource location folder
    mkdir -p $CLUSTER_RESOURCE
    # Unset legacy auth
    gcloud config unset container/use_client_certificate
    gcloud container clusters create $CLUSTER_NAME \
        --cluster-version=$GKE_VERSION --machine-type=n1-standard-2 --zone $GKE_ZONE
    if [ $? -eq 0 ]
    then
        gcloud container clusters get-credentials $CLUSTER_NAME \
            --zone=$GKE_ZONE

        kubectl create serviceaccount spinnaker-service-account

        #Give spinnaker access to the cluster
        kubectl create clusterrolebinding \
            --user system:serviceaccount:default:spinnaker-service-account \
            spinnaker-role \
            --clusterrole cluster-admin

        #Only necessary if spinnaker will be deployed to this cluster
        kubectl create namespace spinnaker

        SERVICE_ACCOUNT_TOKEN=`kubectl get serviceaccounts spinnaker-service-account -o jsonpath='{.secrets[0].name}'`

        #Get token and base64 decode it since all secrets are stored in base64 in Kubernetes and store it for later use
        kubectl get secret $SERVICE_ACCOUNT_TOKEN -o jsonpath='{.data.token}' | base64 --decode > $CLUSTER_RESOURCE/${CLUSTER_NAME}_token.txt
        #Change to proper cluster wait
        sleep 10
    else
        echo "Failed to create a cluster."
        exit 1
    fi
}

# Assign role bindings for a service account; takes a list of roles
assign_role_bindings () {
    for role in $2; do
        echo "Assigning role $role to $1"
        gcloud projects add-iam-policy-binding $GCP_PROJECT \
            --member serviceAccount:$1 --role $role
    done
}

# Setup halyard service account
halyard_service_account () {
    gcloud iam service-accounts create $HALYARD_SA \
        --project=$GCP_PROJECT \
        --display-name $HALYARD_SA
    HALYARD_SA_EMAIL=$(get_sa_email $HALYARD_SA)

    #Assign roles for Halyard
    assign_role_bindings $HALYARD_SA_EMAIL \
        'roles/iam.serviceAccountKeyAdmin roles/container.developer'
}

# Setup spinnaker service account
spinnaker_service_account () {
    gcloud iam service-accounts create $SPIN_SA \
        --project=$GCP_PROJECT \
        --display-name $SPIN_SA
    SPIN_SA_EMAIL=$(get_sa_email $SPIN_SA)

    #Create GCP credentials file for Spinnaker configuration
    gcloud iam service-accounts keys create $CLUSTER_RESOURCE/$SPIN_SA_KEY \
        --iam-account $SPIN_SA_EMAIL

    #Assign roles for Spinnaker
    assign_role_bindings $SPIN_SA_EMAIL \
        'roles/storage.admin roles/browser roles/iam.serviceAccountKeyAdmin roles/container.admin roles/pubsub.admin'
}

# Copy resources needed by halyard host
copy_resources () {
    # Sometimes the VM fails to receive the first file; retry.
    for i in $(seq 1 5);
    do
        gcloud compute scp --zone $GKE_ZONE $CLUSTER_RESOURCE/$SPIN_SA_KEY $HALYARD_HOST:~/ && s=0 && break || s=$? && sleep 2
    done
    if [ $? -eq 0 ]; then
        gcloud compute scp --zone $GKE_ZONE $CLUSTER_RESOURCE/${CLUSTER_NAME}_token.txt $HALYARD_HOST:~/
        gcloud compute scp --zone $GKE_ZONE ./${HALYARD_SCRIPT}.sh $HALYARD_HOST:~/
        gcloud compute scp --zone $GKE_ZONE ./${GCS_TEMPLATE} $HALYARD_HOST:~/
    else
        echo "Failed to copy file, please retry the deploy."
    fi
}

# Launch halyard setup script
run_halyard () {
    gcloud compute ssh $HALYARD_HOST --zone $GKE_ZONE \
        --command "chmod +x ~/${HALYARD_SCRIPT}.sh"
    gcloud compute ssh $HALYARD_HOST --zone $GKE_ZONE \
        --command "bash ~/${HALYARD_SCRIPT}.sh ${POSTFIX} 1>&2 > ~/${HALYARD_SCRIPT}.log"
}

#May not be required if using GCP console
#gcloud auth login
gcloud config set project $PROJECT

#GKE Setup
create_gke_cluster

#Halyard Setup

#Create service account for Halyard VM
halyard_service_account

#Create the admin VM
create_halyard_vm $HALYARD_SA_EMAIL

#Create service account for GCS/GCR
spinnaker_service_account

#Wait for halyard vm to come up
wait_for_halyard_vm $HALYARD_HOST

#Perform halyard tasks
if [ $? -eq 0 ]
then
    #Copy over the token that was created earlier to the Halyard VM
    copy_resources

    #Run halyard commands
    run_halyard
else
    echo "Failed to run Halyard VM"
fi
