#!/bin/bash

#The following configures a GKE cluster and creates the Halyard VM

#Ensure the following APIs are enabled
#Google Identity and Access Management (IAM) API
#Google Cloud Resource Manager API
#Kubernetes Engine API

PROJECT=deploy-manifest-poc
GCP_PROJECT=$(gcloud config get-value project)
RESOURCE_ROOT=~/.gcp

#Choose desired zone and GKE cluster name
GKE_ZONE=us-central1-f
GKE_NAME=shared-services
POSTFIX=$1
HALYARD_HOST=halyard-host-$POSTFIX
CLUSTER_NAME=$GKE_NAME-$POSTFIX
CLUSTER_RESOURCE=$RESOURCE_ROOT/$CLUSTER_NAME
MSG_FORMAT="GCS"
HALYARD_SA=halyard-sa-$POSTFIX
SPIN_SA=spinnaker-sa-$POSTFIX

if [ ! -d "$CLUSTER_RESOURCE" ]; then
    echo "Cluster doesn't exists... exiting."
    exit 1
fi

#May not be required if using GCP console
#gcloud auth login
gcloud config set project $PROJECT

# Delete role bindings for a service account; takes a list of roles
delete_role_bindings () {
    for role in $2; do
        echo "Deleting role $role to $1"
        gcloud projects remove-iam-policy-binding $GCP_PROJECT \
            --member serviceAccount:$1 --role $role
    done
}

# Remove the halyard service account deleting associated roles
remove_halyard_sa () {
    #Halyard Setup
    HALYARD_SA_EMAIL=$(gcloud iam service-accounts list \
        --project=$GCP_PROJECT \
        --filter="displayName:$HALYARD_SA" \
        --format='value(email)')

    # Delete roles associated with the service account
    delete_role_bindings $HALYARD_SA_EMAIL \
        'roles/iam.serviceAccountKeyAdmin roles/container.developer'

    #Delete service account for Halyard VM
    echo "Y" | gcloud iam service-accounts delete $HALYARD_SA_EMAIL
}

# Remove the spinnaker service account deleting associated roles
remove_spinnaker_sa () {
    SPIN_SA_EMAIL=$(gcloud iam service-accounts list \
        --project=$GCP_PROJECT \
        --filter="displayName:$SPIN_SA" \
        --format='value(email)')

    # Delete roles associated with the service account
    delete_role_bindings $SPIN_SA_EMAIL \
        'roles/storage.admin roles/browser roles/iam.serviceAccountKeyAdmin roles/container.admin roles/pubsub.admin'

    # Delete service account for GCS/GCR
    echo "Y" | gcloud iam service-accounts delete $SPIN_SA_EMAIL
}

# Delete the halyard management VM
delete_halyard_vm () {
    # Delete Halyard VM
    echo "Y" | gcloud compute instances delete $HALYARD_HOST \
        --project=$GCP_PROJECT \
        --zone=$GKE_ZONE

    kubectl delete serviceaccount $SPIN_SA

    #Give spinnaker access to the cluster
    kubectl delete clusterrolebinding \
        spinnaker-role
}

# Cleanup bucket
BUCKET=spinnaker-data-$POSTFIX
gsutil -m rm -r gs://${BUCKET}

# Cleanup pubsub topics
TOPIC=topic-$CLUSTER_NAME
SUBSCRIPTION=subs-$CLUSTER_NAME

# Delete custom pubsub topic
delete_custom_topic () {
    gcloud beta pubsub subscriptions delete $SUBSCRIPTION
    gcloud beta pubsub topics delete $TOPIC
}

# Delete gcs notification and subscriptions
delete_gcs_topic () {
    gcloud beta pubsub subscriptions delete $SUBSCRIPTION
    gsutil notification delete -t $TOPIC
    gcloud beta pubsub topics delete $TOPIC
}

# Delete gcr topic
delete_gcr_topic () {
    gcloud beta pubsub subscriptions delete $SUBSCRIPTION
    gcloud beta pubsub topics delete projects/${PROJECT}/topics/gcr
}

# Select messaging format to use
case "$MSG_FORMAT" in
    CUSTOM)
        delete_custom_topic
    ;;
    GCS)
        delete_gcs_topic
    ;;
    GCR)
        delete_gcr_topic
    ;;
    *)
        echo "Invalid message format argument."
        exit 1
esac

# Remove halyard service account
remove_halyard_sa

# Remove spinnaker service account
remove_spinnaker_sa

# Delete halyard vm and kubernetes service accounts
delete_halyard_vm

# Remove local cluster resources
if [ ! -z "$GKE_NAME" ]
then
    echo "Cleaning up resources..."
    rm -rf $CLUSTER_RESOURCE
fi

# Delete the cluster
echo "Y" | gcloud container clusters delete $CLUSTER_NAME --zone $GKE_ZONE
