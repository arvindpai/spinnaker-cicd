#!/bin/bash

#The following is to be run from within the Halyard VM


##VARIABLES##
#Configure Kubernetes with desired cluster and project
GKE_CLUSTER_NAME=shared-services
GKE_CLUSTER_ZONE=us-central1-f
#Project where GKE cluster resides
PROJECT=$(gcloud config get-value project)
SPIN_SA=spinnaker-storage-account
SPIN_SA_DEST=~/.gcp/gcp.json


#Install kubectl
KUBECTL_LATEST=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
curl -LO https://storage.googleapis.com/kubernetes-release/release/$KUBECTL_LATEST/bin/linux/amd64/kubectl
chmod +x kubectl
sudo mv kubectl /usr/local/bin/kubectl


#Install Halyard
curl -O https://raw.githubusercontent.com/spinnaker/halyard/master/install/debian/InstallHalyard.sh
sudo bash InstallHalyard.sh
. ~/.bashrc

mkdir -p $(dirname $SPIN_SA_DEST)
SPIN_SA_EMAIL=$(gcloud iam service-accounts list \
--filter="displayName:$SPIN_SA" \
--format='value(email)')

#Create GCP credentials file for Spinnaker configuration
gcloud iam service-accounts keys create $SPIN_SA_DEST \
--iam-account $SPIN_SA_EMAIL

#Configure Spinnaker version
hal config version edit --version $(hal version latest -q)

#Configure GCS
hal config storage gcs edit \
--project $(gcloud info --format='value(config.project)') \
--json-path ~/.gcp/gcp.json

hal config storage edit --type gcs

#Configure GCR
hal config provider docker-registry enable
hal config provider docker-registry account add my-gcr-account \
--address gcr.io \
--password-file ~/.gcp/gcp.json \
--username _json_key 

#Configure GKE Provider 
#The following will need to be executed for each cluster

gcloud container clusters get-credentials $GKE_CLUSTER_NAME  --project=$PROJECT --zone $GKE_CLUSTER_ZONE

#Set credentials with the token that was created for Spinnaker
CURRENT_CONTEXT=`kubectl config current-context`

kubectl config set-credentials $CURRENT_CONTEXT --token $(cat ${GKE_CLUSTER_NAME}_token.txt)

hal config provider kubernetes account add $GKE_CLUSTER_NAME \
--docker-registries my-gcr-account \
--context $(kubectl config current-context)

hal config provider kubernetes enable

hal config provider kubernetes account edit $GKE_CLUSTER_NAME \
  --provider-version v2 \
  --context $(kubectl config current-context)

hal config features edit --artifacts true

#The following command is enabled by default; it sets the installation environment as the local VM
#hal config deploy edit --type localdebian

#Only needed if Halyard is to be installed on GKE
hal config deploy edit \
--account-name $GKE_CLUSTER_NAME \
--type distributed

CLIENT_ID=1090327584986-m7jhc1scev8fb49vdhukg8e59nelvmpo.apps.googleusercontent.com
CLIENT_SECRET=3J1iLM_rVIx5Fa8xF1G5IXsM
PROVIDER=google

hal config security authn oauth2 edit \
--client-id $CLIENT_ID \
--client-secret $CLIENT_SECRET \
--provider $PROVIDER 

hal config security authn oauth2 enable



ADMIN=vjraj@gflocks.com              # An administrator's email address
CREDENTIALS=/home/paia/creds/gke-multi-container-service-e1df93c7992b.json   # The downloaded service account credentials
DOMAIN=gflocks.com                 # Your organization's domain.

hal config security authz google edit \
--admin-username $ADMIN \
--credential-path $CREDENTIALS \
--domain $DOMAIN

hal config security authz edit --type google

hal config security authz enable

GROUP=spinnaker # The new group membership
PROVIDER=kubernetes
ACCOUNT=shared-services

hal config provider kubernetes account edit $GKE_CLUSTER_NAME \
--required-group-membership $GROUP

hal deploy apply

#Halyard should now be installed
#Run `hal deploy connect` to test that the application is running correctly at http://localhost:9000/



#This step is done when DNS is provided :

kubectl expose service spin-deck --name deck-lb --type LoadBalancer -n spinnaker
kubectl expose service spin-gate --name gate-lb --type LoadBalancer -n spinnaker
kubectl -n spinnaker get svc


# Replace localhost with dns name :

hal config security ui edit \
  --override-base-url http://localhost:9000

hal config security api edit \
  --override-base-url http://localhost:8084
hal deploy apply




