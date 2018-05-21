#The following configures a GKE cluster and creates the Halyard VM

#Ensure the following APIs are enabled
#Google Identity and Access Management (IAM) API 
#Google Cloud Resource Manager API
#Kubernetes Engine API

##VARIABLES##
PROJECT=gke-multi-container-service
GCP_PROJECT=$(gcloud config get-value project)
HALYARD_SA=halyard-service-account
#Choose desired zone and GKE cluster name 
GKE_ZONE=us-central1-f
GKE_NAME=shared-services
SPIN_SA=spinnaker-storage-account
HALYARD_HOST=halyard-host


#May not be required if using GCP console
#gcloud auth login
gcloud config set project $PROJECT


#You may skip to Halyard Setup if Spinnaker will not be installed on GKE

#GKE Setup 
#See gke_app_cluster.sh for an example for configuring a cluster in a different project

gcloud container clusters create $GKE_NAME \
 --machine-type=n1-standard-2 --zone $GKE_ZONE
gcloud container clusters get-credentials $GKE_NAME \
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
kubectl get secret $SERVICE_ACCOUNT_TOKEN -o jsonpath='{.data.token}' | base64 -d > ${GKE_NAME}_token.txt


#Halyard Setup

#Create service account for Halyard VM 
gcloud iam service-accounts create $HALYARD_SA \
   --project=$GCP_PROJECT \
   --display-name $HALYARD_SA
HALYARD_SA_EMAIL=$(gcloud iam service-accounts list \
    --project=$GCP_PROJECT \
    --filter="displayName:$HALYARD_SA" \
    --format='value(email)')

#Used to download GCS/GCR credentials
gcloud projects add-iam-policy-binding $GCP_PROJECT \
    --role roles/iam.serviceAccountKeyAdmin \
    --member serviceAccount:$HALYARD_SA_EMAIL

#Used to download Kubernetes credentials
gcloud projects add-iam-policy-binding $GCP_PROJECT \
    --role roles/container.developer \
    --member serviceAccount:$HALYARD_SA_EMAIL

#Create service account for GCS/GCR

gcloud iam service-accounts create $SPIN_SA \
    --project=$GCP_PROJECT \
    --display-name $SPIN_SA

SPIN_SA_EMAIL=$(gcloud iam service-accounts list \
    --project=$GCP_PROJECT \
    --filter="displayName:$SPIN_SA" \
    --format='value(email)')

gcloud projects add-iam-policy-binding $GCP_PROJECT \
	--member serviceAccount:$SPIN_SA_EMAIL \
    --role roles/storage.admin 
    

gcloud projects add-iam-policy-binding $GCP_PROJECT \
   --member serviceAccount:$SPIN_SA_EMAIL \
   --role roles/browser

gcloud projects add-iam-policy-binding $GCP_PROJECT \
    --role roles/iam.serviceAccountKeyAdmin \
    --member serviceAccount:$SPIN_SA_EMAIL

gcloud projects add-iam-policy-binding $GCP_PROJECT \
    --role roles/container.admin \
    --member serviceAccount:$SPIN_SA_EMAIL
#Create Halyard VM

gcloud compute instances create $HALYARD_HOST \
    --project=$GCP_PROJECT \
    --zone=us-central1-f \
    --scopes=cloud-platform \
    --service-account=$HALYARD_SA_EMAIL \
    --image-project=ubuntu-os-cloud \
    --image-family=ubuntu-1404-lts \
    --machine-type=n1-standard-4


#Copy over the token that was created earlier to the Halyard VM
gcloud compute scp ./${GKE_NAME}_token.txt $HALYARD_HOST:~/

#SSH into the Halyard VM
#Do this from a local workstation in order for port forwarding to work
#Continue with the halyard_host.sh scripts
GCP_PROJECT=$(gcloud config get-value project)
HALYARD_HOST=halyard-host
gcloud compute ssh $HALYARD_HOST \
    --project=$GCP_PROJECT \
    --zone=us-central1-f \
    --ssh-flag="-L 9000:localhost:9000" \
    --ssh-flag="-L 8084:localhost:8084"


