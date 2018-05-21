#!/bin/bash

#The following is to be run from within the Halyard VM

#Configure Kubernetes with desired cluster and project
GKE_CLUSTER_NAME=shared-services
GKE_CLUSTER_ZONE=us-central1-f
POSTFIX=$1

#Project where GKE cluster resides
GCP_PROJECT=$(gcloud config get-value project)
SPIN_SA=spinnaker-sa-$POSTFIX
SPIN_SA_KEY=spinnaker-sa.json
PROJECT=gke-test1
MSG_FORMAT="GCS"
BUCKET=spinnaker-data-$POSTFIX
GCS_TEMPLATE=gcs-jinja.json
CLUSTER_NAME=$GKE_CLUSTER_NAME-$POSTFIX
CLUSTER_TOKEN=${CLUSTER_NAME}_token.txt
SPINNAKER_SA=$SPIN_SA_KEY
IMAGE_REGISTRY=$PROJECT/sample-code
TOPIC=topic-$CLUSTER_NAME
SUBSCRIPTION=subs-$CLUSTER_NAME

ROER_VERSION=v0.11.3
ROER_NAME=roer-linux-amd64
ROER_PACKAGE=https://github.com/spinnaker/roer/releases/download/$ROER_VERSION/$ROER_NAME

# If some of the required files are missing, print error message
if [ ! -f $SPINNAKER_SA ] || [ ! -f $CLUSTER_TOKEN ]; then
    echo "Service account error... exiting."
    exit 1
fi

# Get the current cluster user
get_cluster_user () {
    gcloud auth list --filter=status:ACTIVE --format="value(account)" | cut -d "@" -f 1
}

# Install packages needed by halyard vm
install_vm_packages () {
    #Install kubectl
    KUBECTL_LATEST=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
    curl -LO https://storage.googleapis.com/kubernetes-release/release/$KUBECTL_LATEST/bin/linux/amd64/kubectl
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/kubectl

    #Install Halyard
    curl -O https://raw.githubusercontent.com/spinnaker/halyard/master/install/debian/InstallHalyard.sh
    sudo bash InstallHalyard.sh -y --user $CLUSTER_USER
}

# Setup GCR
gcr_setup () {
    GCR_ACCOUNT=gcr-$CLUSTER_NAME

    #Configure GCR
    echo "Cofiguring GCR registry with key $SPINNAKER_SA"
    hal config provider docker-registry enable
    hal config provider docker-registry account add $GCR_ACCOUNT \
        --password-file $SPINNAKER_SA \
        --username _json_key \
        --address gcr.io \
        --repositories $IMAGE_REGISTRY
}

# Configure GKE provider
provider_setup () {
    #Configure GKE Provider
    #The following will need to be executed for each cluster
    gcloud container clusters get-credentials $CLUSTER_NAME  --project=$GCP_PROJECT --zone $GKE_CLUSTER_ZONE

    #Set credentials with the token that was created for Spinnaker
    CURRENT_CONTEXT=`kubectl config current-context`

    kubectl config set-credentials $CURRENT_CONTEXT --token $(cat $CLUSTER_TOKEN)

    hal config provider kubernetes account add $CLUSTER_NAME \
        --docker-registries $GCR_ACCOUNT \
        --context $(kubectl config current-context) \
        --provider-version v2

    hal config provider kubernetes enable

    #Only needed if Halyard is to be installed on GKE
    hal config deploy edit \
        --account-name $CLUSTER_NAME \
        --type distributed
}

# Setup artifact account
setup_artifact_account () {
    ARTIFACT_ACCOUNT_NAME=gcsaa-$CLUSTER_NAME

    hal config features edit --artifacts true

    hal config artifact gcs account add $ARTIFACT_ACCOUNT_NAME \
        --json-path $SPINNAKER_SA

    hal config artifact gcs enable

}
# Setup GCP storage bucket
setup_bucket () {
    gcloud auth activate-service-account --key-file=$SPINNAKER_SA

    gsutil mb -p $PROJECT gs://${BUCKET}

    #Configure GCS
    echo "Configuring GCS bucket with key $SPINNAKER_SA"
    hal config storage gcs edit \
        --project $(gcloud info --format='value(config.project)') \
        --json-path $SPINNAKER_SA
    hal config storage edit --type gcs
}

# Configure support for pipeline templates
setup_pipeline_templates () {
    hal config features edit --pipeline-templates true
}

# Create custom pub sub topic
create_custom_topic () {
    ####### Sending your own Pub/Sub messages

    # First, record the fact that your $MESSAGE_FORMAT is CUSTOM, this will be needed later.
    MESSAGE_FORMAT=CUSTOM

    # You need a topic with name $TOPIC to publish messages to:
    gcloud beta pubsub topics create $TOPIC

    # This topic needs a a pull subscription named $SUBSCRIPTION to let Spinnaker read
    # messages from. It is important that Spinnaker is the only system reading from
    # this single subscription. You can always create more subscriptions for this topic if you want multiple systems to recieve the same messages.
    gcloud beta pubsub subscriptions create $SUBSCRIPTION --topic $TOPIC
}

# Create GCS pub sub topic
create_gcs_topic () {
    ####### Receiving messages from Google Cloud Storage (GCS)

    # First, record the fact that your $MESSAGE_FORMAT is GCS, this will be needed later.
    MESSAGE_FORMAT=GCS

    # Given that you’ll be listening to changes in a GCS bucket ($BUCKET), the following command
    # will create (or use an existing) topic with name $TOPIC to publish messages to:
    gsutil notification create -t $TOPIC -f json gs://${BUCKET}

    # Finally, create a pull subscription named $SUBSCRIPTION to listen to changes to this topic:
    gcloud beta pubsub subscriptions create $SUBSCRIPTION --topic $TOPIC
}

# Create GCR pub sub topic
create_gcr_topic () {
    ####### Receiving messages from Google Container Registry (GCR)

    # First, record the fact that your $MESSAGE_FORMAT is GCR, this will be needed later.
    MESSAGE_FORMAT=GCR

    # Given a project name $PROJECT, GCR will always try to publish messages to
    # a topic named projects/${PROJECT}/topics/gcr for any repositories in $PROJECT.
    # To ensure that GCR has a valid topic to publish to, try to create the following topic:
    gcloud beta pubsub topics create projects/${PROJECT}/topics/gcr

    # Finally, create a pull subscription named $SUBSCRIPTION to listen to changes to this topic:
    gcloud beta pubsub subscriptions create $SUBSCRIPTION \
        --topic projects/${PROJECT}/topics/gcr
}

# Setup the pub sub entries
setup_pub_sub () {
    case "$MSG_FORMAT" in
        CUSTOM)
            create_custom_topic
        ;;
        GCS)
            create_gcs_topic
        ;;
        GCR)
            create_gcr_topic
        ;;
        *)
            echo "Invalid message format argument."
            exit 1
    esac

    # See 'A Pub/Sub Subscription' section above
    echo "Using message format: $MESSAGE_FORMAT"

    # You can pick this name, it's meant to be human-readable
    PUBSUB_NAME=pubsub-$CLUSTER_NAME
    echo "Creating pubsub name: $PUBSUB_NAME"

    # First, make sure that Google Pub/Sub support is enabled:
    hal config pubsub google enable

    # Next, add your subscription
    hal config pubsub google subscription add $PUBSUB_NAME \
        --subscription-name $SUBSCRIPTION \
        --json-path $SPINNAKER_SA \
        --project $PROJECT \
        --template-path $GCS_TEMPLATE \
        --message-format $MESSAGE_FORMAT
}

# Install roer tool for pipeline configuration
install_roer () {
    wget $ROER_PACKAGE
}

CLUSTER_USER=paia
#$(get_cluster_user)

# Install packages needed by halyard vm
install_vm_packages

# Configure Spinnaker version
hal config version edit --version $(hal version latest -q)

# Setup GCR
gcr_setup

# Configure GKE provider
provider_setup

# Setup artifact account
setup_artifact_account

# Setup GCP bucket to use for the Spinnaker data
setup_bucket

# Setup support for Pub Sub and configure topic/subscriptions
setup_pub_sub

# Setup support for templates
setup_pipeline_templates

# Install ROER tool
install_roer

# Deploy Spinnaker
hal deploy apply
