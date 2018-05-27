#!/usr/bin/env bash

set -e

ZONE=us-west1-a
REGION=us-west1
CLUSTER_VERSION=1.9.2-gke.1
MACHINE_TYPE=n1-standard-2
GCS_SA_NAME=gke-service-account
GCS_SA_DEST=/root/.gcp/gcp.json

echo 'Authenticate gcloud with your account:'
gcloud auth login

mkdir -p $(dirname $GCS_SA_DEST)

for ENV in stage production service; do
  PROJECT=cardinal-cicd-$ENV
  FE_GKE_CLUSTER_NAME=gke-fe-$ENV
  BE_GKE_CLUSTER_NAME=gke-be-$ENV
  GCS_SA_DEST=/root/.gcp/$FE_GKE_CLUSTER_NAME.json
  
  echo
  echo '----------------------------------------------------'
  echo "             Configure Project: $PROJECT"
  echo '----------------------------------------------------'
  echo

  gcloud config set project $PROJECT
  gcloud config set compute/zone $ZONE
  gcloud config set compute/region $REGION
  gcloud config set container/use_client_certificate true
  gcloud config set container/use_v1_api false
  GCP_PROJECT=$(gcloud info --format='value(config.project)')

   echo 'Create Public Kubernetes Cluster and generate ~/.kube/config file:'
   gcloud container clusters create $FE_GKE_CLUSTER_NAME \
    --machine-type=$MACHINE_TYPE \
    --enable-autoupgrade \
    --enable-autoscaling \
     --max-nodes=10 \
     --min-nodes=4 \
 	--zone $ZONE \
     --project $PROJECT
  
  echo '**Create Private Kubernetes Cluster and generate ~/.kube/config file:**'
   gcloud beta container clusters create $BE_GKE_CLUSTER_NAME \
       --private-cluster \
      --master-ipv4-cidr 172.16.0.16/28 \
       --enable-ip-alias \
   	  --enable-master-authorized-networks \
   	  --zone $ZONE \
       --create-subnetwork "" \
   	  --project $PROJECT
  
  echo '**Setting the authorized networ to the private cluster **'
  gcloud container clusters update $BE_GKE_CLUSTER_NAME \
      --enable-master-authorized-networks \
      --master-authorized-networks 0.0.0.0/0 \
      --project=$PROJECT
  
  echo 'Retrieve the Public Kubernetes Cluster credentials:'
  gcloud container clusters get-credentials $FE_GKE_CLUSTER_NAME \
    --zone $ZONE \
    --project $PROJECT

	echo 'Retrieve the Private Kubernetes Cluster credentials:'
	
    gcloud container clusters get-credentials $BE_GKE_CLUSTER_NAME \
      --zone $ZONE \
      --project $PROJECT

  echo "Create a service account for GCS in $GCP_PROJECT project:"
  gcloud iam service-accounts create $GCS_SA_NAME \
    --display-name $GCS_SA_NAME \
    --project $PROJECT

  GCS_SA_EMAIL=$(gcloud iam service-accounts list \
    --filter="displayName:$GCS_SA_NAME" \
    --format='value(email)' \
    --project $PROJECT)

  gcloud projects add-iam-policy-binding $GCP_PROJECT \
    --role roles/storage.admin \
    --member serviceAccount:$GCS_SA_EMAIL \
    --project $PROJECT

  echo 'Download the service account JSON file for your GCP project:'
  gcloud iam service-accounts keys create $GCS_SA_DEST \
    --iam-account $GCS_SA_EMAIL \
    --project $PROJECT
done

PROJECT=cardinal-cicd-service
ZONE=us-west1-a
FE_GKE_CLUSTER_NAME=gke-fe-service
BE_GKE_CLUSTER_NAME=gke-be-service
GCS_SA_DEST=/root/.gcp/gcp.json
cp /root/.gcp/$FE_GKE_CLUSTER_NAME.json $GCS_SA_DEST

gcloud config set project $PROJECT
gcloud config set compute/zone $ZONE
gcloud config set container/use_client_certificate true
GCP_PROJECT=$(gcloud info --format='value(config.project)')

kubectl config use-context gke_cardinal-cicd-service_us-west1-a_gke-fe-service

echo
echo '----------------------------------------------------'
echo "               Configure Spinnaker"
echo '----------------------------------------------------'
echo

# S P I N N A K E R
echo 'Use the latest version of Spinnaker:'
hal config version edit --version $(hal version latest -q)

echo 'Set up to persist to GCS:'
hal config storage gcs edit \
  --project $(gcloud info --format='value(config.project)') \
  --json-path $GCS_SA_DEST

echo 'Set up Spinnaker’s persistent storage:'
hal config storage edit --type gcs

echo 'Set up pulling from GCR:'
hal config provider docker-registry enable

echo 'Configure GCR docker registry:'
hal config provider docker-registry account add gcr-service \
  --password-file $GCS_SA_DEST \
  --username _json_key \
  --address gcr.io \
  --repositories $PROJECT/sample-app

echo 'Set up the Kubernetes provider:'
hal config provider kubernetes enable

for ENV in stage production service; do
  kubectl config use-context gke_cardinal-cicd-${ENV}_us-west1-a_gke-fe-$ENV
  echo
  echo '----------------------------------------------------'
  echo "             Kubernetes Contect: $ENV"
  echo '----------------------------------------------------'
  echo

  echo "Add the gke-$ENV GKE cluster:"
  hal config provider kubernetes account add gke-$ENV \
    --docker-registries gcr-service \
    --context $(kubectl config current-context)
done

for ENV in stage production service; do
  kubectl config use-context gke_cardinal-cicd-${ENV}_us-west1-a_gke-be-$ENV
  echo
  echo '----------------------------------------------------'
  echo "             Kubernetes Contect: $ENV"
  echo '----------------------------------------------------'
  echo

  echo "Add the gke-$ENV GKE cluster:"
  hal config provider kubernetes account add gke-be-$ENV \
    --docker-registries gcr-service \
    --context $(kubectl config current-context)
done

echo 'Deploy Spinnaker:'
hal config deploy edit \
  --account-name gke-fe-service \
  --type distributed

hal deploy apply

echo 'Enable oAuth:'
DOMAIN=jxtr.us

hal config security ui edit \
    --override-base-url http://spinnaker.$DOMAIN

hal config security api edit \
    --override-base-url http://spinnaker-api.$DOMAIN

hal deploy apply
# GO TO THE GCP CONSOLE>>SERVICES AND EDIT SPIN-DECK SERVICE
# CHANGE PORT TO 80
# CHANGE FROM SERVICE ClusterIP to LoadBalancer
# ADD THIS LINE FOR YOUR VALUE OF: loadBalancerIP: <<STATIC IP RESERVED>>
kubectl edit svc spin-deck -n spinnaker

# CHANGE PORT TO 80
# CHANGE FROM ClusterIP to LoadBalancer
# ADD THIS LINE FOR YOUR VALUE OF: loadBalancerIP: <<STATIC IP RESERVED>>
kubectl edit svc spin-gate -n spinnaker
