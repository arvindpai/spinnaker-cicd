#The following is for granting access and configuring a cluster which is in a different project than the Spinnaker cluster/VM


##VARIABLES##
GCP_SPIN_PROJECT=spinnaker-project-name
APP_CLUSTER=application-cluster-name
#Zone of app cluster
GKE_ZONE=us-central1-f
GCP_APP_PROJECT=application-project-name
HALYARD_HOST=halyard-host
HALYARD_SA=halyard-service-account

gcloud container clusters get-credentials $APP_CLUSTER --zone $GKE_ZONE --project $GCP_APP_PROJECT


#Get the SA email from the Spinnaker project
HALYARD_SA_EMAIL=$(gcloud iam service-accounts list \
  --project=$GCP_SPIN_PROJECT \
  --filter="displayName:$HALYARD_SA" \
  --format='value(email)')

gcloud projects add-iam-policy-binding $GCP_APP_PROJECT \
  --role roles/container.developer \
  --member serviceAccount:$HALYARD_SA_EMAIL

gcloud container clusters get-credentials $APP_CLUSTER \
    --zone=$GKE_ZONE

kubectl create serviceaccount spinnaker-service-account

#Give cluster edit access to spinnaker

kubectl create clusterrolebinding \
  --user system:serviceaccount:default:spinnaker-service-account \
  spinnaker-role \
  --clusterrole edit

SERVICE_ACCOUNT_TOKEN=`kubectl get serviceaccounts spinnaker-service-account -o jsonpath='{.secrets[0].name}'`

#Get token and base64 decode it since all secrets are stored in base64 in Kubernetes and store it for later use
kubectl get secret $SERVICE_ACCOUNT_TOKEN -o jsonpath='{.data.token}' | base64 -d > ${APP_CLUSTER}_token.txt

#SCP the token to the Halyard VM
gcloud compute scp ./${APP_CLUSTER}_token.txt $HALYARD_HOST:~/ --project $GCP_SPIN_PROJECT

