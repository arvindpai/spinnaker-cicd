
##Concepts of Spinnaker :
Spinnaker is an open source, multi-cloud continuous delivery platform that helps you release software changes with high velocity and confidence.

* It provides two core sets of features: cluster management and deployment management. 

You use Spinnaker’s deployment management features to construct and manage continuous delivery workflows.
### Introduction of Continous Deployment :
###Pipeline


Pipelines are the key deployment management construct in Spinnaker. They consist of a sequence of actions, known as stages. You can pass parameters from stage to stage along the pipeline. You can start a pipeline manually, or you can configure it to be started by automatic triggering events, such as a Jenkins job completing, a new Docker image appearing in your registry, a CRON schedule, or a stage in another pipeline. You can configure the pipeline to emit notifications to interested parties at various points during pipeline execution (such as on pipeline start/complete/fail), by email, SMS or HipChat.

* Stage

A Stage in Spinnaker is an action that forms an atomic building block for a pipeline. You can sequence stages in a Pipeline in any order, though some stage sequences may be more common than others. Spinnaker provides a number of stages such as Deploy, Resize, Disable, Manual Judgment, and many more. You can see the full list of stages and read about implementation details for each provider in the Reference section.

* Deployment strategies


Spinnaker treats cloud-native deployment strategies as first class constructs, handling the underlying orchestration such as verifying health checks, disabling old server groups and enabling new server groups. Spinnaker supports the red/black (a.k.a. blue/green) strategy, with rolling red/black and canary strategies in active development.
### Architecture:
  Execution of this POC will create the following GCP resources.
  
  ![](cicd_spinnaker.png)

#### GKE Cluster 1
* gke-spinnaker cluster (hosting Spinnaker Pods)

|cluster-ipv4-cidr|zone|Initial Node count|Node Image
|---|---|---|---|
|10.128.0.0/19|us-east1-d|3|COS

#### GKE Cluster 2
* private-cluster

|cluster-ipv4-cidr|zone|Initial Node count|Node Image
|---|---|---|---|
|10.138.0.0/19|us-west1-b|3|COS

#### Other Resources

* External Ip Addresses :

|name|External Address|Type|Version
|---|---|---|---|
|spin-deck|35.203.186.39|static|IPv4
|spin-gate|35.203.159.237|static|IPv4

  *  Spinnaker Load Balancer :
  
|name|servicetype|Endpoints|Pods
|---|---|---|---|
|spin-deck|load balancer|35.203.186.39:80|1
|spin-gate|load balancer|35.203.159.237:80|1

* Cloud DNS :

|DNS name|Type|TTL(secs)|Data
|---|---|---|---|
|spinnaker.$DOMAIN|A|5|35.203.186.39
|spinnaker-api.$DOMAIN|A|5|35.203.159.237

* Note : Ip address are bound to change 

###Prerequisites for Spinnaker :

There are several environments Halyard can deploy Spinnaker to, and they can be split into three groups, each entirely handled by Halyard.

* Local installations of Debian packages.
* Distributed installations via a remote bootstrapping process.
* Local git installations from github.

### Deployment Tools for Spinnaker :

* Halyard
* Helm

#### Spinnaker Version

If you want to change Spinnaker versions using Halyard, you can read about supported versions like so:

```
hal version list

And pick a new version like so:

hal config version edit --version $VERSION

hal deploy apply 

```

###Deploy Spinnaker to GKE Cluster using Halyard:


####First Shell terminal :
```
echo
echo '----------------------------------------------------'
echo "            Build Halyard Container
echo '----------------------------------------------------'
echo

cd gke-cicd/

docker build -t hal -f Dockerfile  .

docker run -p 8084:8084 -p 9000:9000   --name halyard --rm   -v ~/.hal:/root/.hal   -v $(PWD):/workdir   -it hal
```
####Second Shell Terminal :
```
#!/usr/bin/env bash

DNS_ZONE=jxtr
DNS_DOMAIN=jxtr.us
DNS_PROJECT=helmsman-2018

REGION=us-west1
GKE_ZONE=us-west1-b

PROJECT=my-cloud-services
GKE_NAME=cloud-services

SPIN_SA=spinnaker-storage-account
HALYARD_SA=halyard-service-account

# May not be required if using GCP console
gcloud auth login
gcloud config set project $PROJECT
gcloud config set compute/zone $GKE_ZONE

GCLOUD_USER=$(gcloud auth list \
  --filter=status:ACTIVE \
  --format="value(account)" \
  | sed 's/@gflocks\.com//')

# Set the DNS name for spin-deck and spin-gate
# i.e. spin-deck => spinnaker-stefanoh
# i.e. spin-gate => spinnaker-api-stefanoh
DNS_NAME_FOR_SPIN_DECK=spinnaker-$GCLOUD_USER
DNS_NAME_FOR_SPIN_GATE=spinnaker-api-$GCLOUD_USER

################################################################################
#                                                                              #
#               Enables Services                                               #
#                                                                              #
################################################################################

# Enables a service for consumption for a project
# https://cloud.google.com/sdk/gcloud/reference/services/enable
#
# To get a list of available services:
# gcloud services list --available

# Enable gcloud alpha/beta services
gcloud alpha services enable -q
gcloud beta services enable -q

# Google Cloud APIs
gcloud services enable cloudapis.googleapis.com
# Identity and Access Management (IAM) API
gcloud services enable iam.googleapis.com
# Cloud Resource Manager API
gcloud services enable cloudresourcemanager.googleapis.com
# Compute Engine API
gcloud services enable compute.googleapis.com
# Kubernetes Engine API
gcloud services enable container.googleapis.com
# Container Registry API
gcloud services enable containerregistry.googleapis.com
# Cloud Container Builder API
gcloud services enable cloudbuild.googleapis.com
# Stackdriver Logging API
gcloud services enable logging.googleapis.com
# Stackdriver Monitoring API
gcloud services enable monitoring.googleapis.com
# Google Cloud Storage JSON API
gcloud services enable storage-api.googleapis.com
# Google Cloud Storage
gcloud services enable storage-component.googleapis.com
# Cloud Source Repositories API
gcloud services enable sourcerepo.googleapis.com

################################################################################
#                                                                              #
#               Secure GCP Environment by removing SSH/RDP/ICMP                #
#                                                                              #
################################################################################

# Delete Google Compute Engine firewall rules
# https://cloud.google.com/sdk/gcloud/reference/compute/firewall-rules/delete
gcloud compute firewall-rules delete default-allow-ssh -q
gcloud compute firewall-rules delete default-allow-rdp -q
gcloud compute firewall-rules delete default-allow-icmp -q

################################################################################
#                                                                              #
#               Create a GKE Cluster for Spinnaker Deployment                  #
#                                                                              #
################################################################################

# Create a cluster for running containers
# https://cloud.google.com/sdk/gcloud/reference/container/clusters/create
gcloud container clusters create $GKE_NAME \
  --machine-type=n1-standard-2 \
  --zone $GKE_ZONE \
  --labels env=infra,release=stable,created_by=$GCLOUD_USER

# Fetch credentials for a running cluster
# https://cloud.google.com/sdk/gcloud/reference/container/clusters/get-credentials
gcloud container clusters get-credentials $GKE_NAME \
  --zone=$GKE_ZONE

################################################################################
#                                                                              #
#               Create Service Accounts for Spinnaker                          #
#                                                                              #
################################################################################

# Grant a role to an application-specific service account
# https://kubernetes.io/docs/admin/authorization/rbac/
kubectl create serviceaccount spinnaker-service-account

# Give spinnaker access to the cluster
kubectl create clusterrolebinding \
  --user system:serviceaccount:default:spinnaker-service-account \
  spinnaker-role \
  --clusterrole cluster-admin

# Creates the Spinnaker namespace, this is only necessary if spinnaker will be 
# deployed to this cluster.
# https://kubernetes-v1-4.github.io/docs/user-guide/kubectl/kubectl_create_namespace/
kubectl create namespace spinnaker

# Get the service account token for Spinnaker serviceAccount resource
SERVICE_ACCOUNT_TOKEN=`kubectl get serviceaccounts spinnaker-service-account \
  -o jsonpath='{.secrets[0].name}'`

# Get token and base64 decode it since all secrets are stored in base64 in 
# Kubernetes and store it for later use
# https://kubernetes.io/docs/concepts/configuration/secret/
kubectl get secret $SERVICE_ACCOUNT_TOKEN \
  -o jsonpath='{.data.token}' | base64 -d > ${GKE_NAME}_token.txt

################################################################################
#                                                                              #
#               Setup Halyard                                                  #
#                                                                              #
################################################################################

GCP_PROJECT=$(gcloud config get-value project)

# Create a service account for Halyard
# https://cloud.google.com/sdk/gcloud/reference/iam/service-accounts/create
gcloud iam service-accounts create $HALYARD_SA \
  --project=$GCP_PROJECT \
  --display-name $HALYARD_SA

HALYARD_SA_EMAIL=$(gcloud iam service-accounts list \
  --project=$GCP_PROJECT \
  --filter="displayName:$HALYARD_SA" \
  --format='value(email)')

# Add IAM policy binding for Halyard
# https://cloud.google.com/sdk/gcloud/reference/projects/add-iam-policy-binding
gcloud projects add-iam-policy-binding $GCP_PROJECT \
  --role roles/iam.serviceAccountKeyAdmin \
  --member serviceAccount:$HALYARD_SA_EMAIL

gcloud projects add-iam-policy-binding $GCP_PROJECT \
  --role roles/container.developer \
  --member serviceAccount:$HALYARD_SA_EMAIL

# create a service account for a GCS/GCR
# https://cloud.google.com/sdk/gcloud/reference/iam/service-accounts/create
gcloud iam service-accounts create $SPIN_SA \
  --project=$GCP_PROJECT \
  --display-name $SPIN_SA

SPIN_SA_EMAIL=$(gcloud iam service-accounts list \
  --project=$GCP_PROJECT \
  --filter="displayName:$SPIN_SA" \
  --format='value(email)')

# Add IAM policy binding for GCS
# https://cloud.google.com/sdk/gcloud/reference/projects/add-iam-policy-binding
gcloud projects add-iam-policy-binding $GCP_PROJECT \
  --role roles/storage.admin \
  --member serviceAccount:$SPIN_SA_EMAIL

# Add IAM policy binding for GCR
# https://cloud.google.com/sdk/gcloud/reference/projects/add-iam-policy-binding
gcloud projects add-iam-policy-binding $GCP_PROJECT \
  --member serviceAccount:$SPIN_SA_EMAIL \
  --role roles/browser

################################################################################
#                                                                              #
#               Reserve static IPs and assign DNS                              #
#                                                                              #
################################################################################

# Reserve IP addresses
# https://cloud.google.com/sdk/gcloud/reference/compute/addresses/create
gcloud compute addresses create spin-deck \
  --region $REGION

gcloud compute addresses create spin-gate \
  --region $REGION

SPIN_DECK_IP=$(gcloud compute addresses describe spin-deck \
  --project=$PROJECT \
  --region $REGION \
  --format='value(address)')

SPIN_GATE_IP=$(gcloud compute addresses describe spin-gate \
  --project=$PROJECT \
  --region $REGION \
  --format='value(address)')

# Make scriptable and transactional changes to your record-sets
# https://cloud.google.com/sdk/gcloud/reference/dns/record-sets/transaction/
gcloud dns record-sets transaction start \
  --project $DNS_PROJECT \
  -z $DNS_ZONE

# Append a record-set addition to the transaction
gcloud dns record-sets transaction add \
  --name="$DNS_NAME_FOR_SPIN_DECK.$DNS_DOMAIN." \
  --ttl=300 "$SPIN_DECK_IP" \
  --type=A \
  -z $DNS_ZONE

gcloud dns record-sets transaction add \
  --name="$DNS_NAME_FOR_SPIN_GATE.$DNS_DOMAIN." \
  --ttl=300 "$SPIN_GATE_IP" \
  --type=A \
  -z $DNS_ZONE

# Execute the transaction on Cloud DNS
gcloud dns record-sets transaction execute \
  --project $DNS_PROJECT \
  -z $DNS_ZONE

################################################################################
#                                                                              #
#               Setup Spinnaker with Halyard                                   #
#                                                                              #
################################################################################

##VARIABLES##
# Configure Kubernetes with desired cluster and project
GKE_CLUSTER_NAME=cloud-services
GKE_CLUSTER_ZONE=us-west1-b
# Project where GKE cluster resides
PROJECT=$(gcloud config get-value project)
SPIN_SA=spinnaker-storage-account
SPIN_SA_DEST=~/.gcp/gcp.json

mkdir -p $(dirname $SPIN_SA_DEST)
SPIN_SA_EMAIL=$(gcloud iam service-accounts list \
  --filter="displayName:$SPIN_SA" \
  --format='value(email)')

# Create a private key for Spinnaker service account
# https://cloud.google.com/sdk/gcloud/reference/iam/service-accounts/keys/create
gcloud iam service-accounts keys create $SPIN_SA_DEST \
  --iam-account $SPIN_SA_EMAIL

# Set the desired Spinnaker version
# https://www.spinnaker.io/reference/halyard/commands/#hal-config-version-edit
hal config version edit --version $(hal version latest -q)

# Edit configuration for the GCS persistent store
# https://www.spinnaker.io/reference/halyard/commands/#hal-config-storage-gcs-edit
hal config storage gcs edit \
  --project $(gcloud info --format='value(config.project)') \
  --json-path $SPIN_SA_DEST

# Edit Spinnaker’s persistent storage.
# https://www.spinnaker.io/reference/halyard/commands/#hal-config-storage-edit
hal config storage edit --type gcs

# Set the dockerRegistry provider as enabled
# https://www.spinnaker.io/reference/halyard/commands/#hal-config-provider-docker-registry-enable
hal config provider docker-registry enable

# Add an account to the dockerRegistry provider
# https://www.spinnaker.io/reference/halyard/commands/#hal-config-provider-docker-registry-account-add
hal config provider docker-registry account add gcr \
  --address gcr.io \
  --password-file $SPIN_SA_DEST \
  --username _json_key \
  --repositories $PROJECT/sample-app

# Fetch credentials for a running cluster
# NOTE: The following will need to be executed for each cluster
# https://cloud.google.com/sdk/gcloud/reference/container/clusters/get-credentials
gcloud container clusters get-credentials $GKE_CLUSTER_NAME \
  --project=$PROJECT \
  --zone $GKE_CLUSTER_ZONE

# Set credentials with the token that was created for Spinnaker
# https://kubernetes-v1-4.github.io/docs/user-guide/kubectl/kubectl_config_set-credentials/
CURRENT_CONTEXT=`kubectl config current-context`
kubectl config set-credentials $CURRENT_CONTEXT \
  --token $(cat ${GKE_CLUSTER_NAME}_token.txt)

# Add an account to the kubernetes provider
# https://www.spinnaker.io/reference/halyard/commands/#hal-config-provider-kubernetes-account-add
hal config provider kubernetes account add $GKE_CLUSTER_NAME \
  --docker-registries gcr \
  --context $(kubectl config current-context)

# Set the kubernetes provider as enabled
# https://www.spinnaker.io/reference/halyard/commands/#hal-config-provider-kubernetes-enable
hal config provider kubernetes enable

# Edit Spinnaker’s deployment footprint and configuration
# https://www.spinnaker.io/reference/halyard/commands/#hal-config-deploy-edit
hal config deploy edit \
  --account-name $GKE_CLUSTER_NAME \
  --type distributed

# When Spinnaker is deployed to a remote host, the UI server may be configured to do SSL termination, or sit behind an externally configured proxy server or load balancer.
# https://www.spinnaker.io/reference/halyard/commands/#hal-config-security-ui-edit
hal config security ui edit \
  --override-base-url http://$DNS_NAME_FOR_SPIN_DECK.$DNS_DOMAIN

hal config security api edit \
  --override-base-url http://$DNS_NAME_FOR_SPIN_GATE.$DNS_DOMAIN

# Deploys Spinnaker
# https://www.spinnaker.io/reference/halyard/commands/#hal-deploy-apply
hal deploy apply

################################################################################
#                                                                              #
#               Expose Spinnaker Ingress                                       #
#                                                                              #
################################################################################

# Edit a resource on the server
# https://kubernetes-v1-4.github.io/docs/user-guide/kubectl/kubectl_edit/

# CHANGE PORT TO 80
# CHANGE FROM ClusterIP to LoadBalancer
# ADD THIS LINE FOR YOUR VALUE OF: loadBalancerIP: 35.227.184.28
#
# Get the IP for spin-deck by running:
echo $SPIN_DECK_IP
kubectl edit svc spin-deck -n spinnaker #     <------------ HOW CAN WE AUTOMATE THIS????

# CHANGE PORT TO 80
# CHANGE FROM ClusterIP to LoadBalancer
# ADD THIS LINE FOR YOUR VALUE OF: loadBalancerIP: 35.203.146.246
#
# Get the IP for spin-gate by running:
echo $SPIN_GATE_IP
kubectl edit svc spin-gate -n spinnaker #     <------------ HOW CAN WE AUTOMATE THIS????

################################################################################
#                                                                              #
#               Configure the Spinnaker with RBAC & V2 Provider                            #
#                                                                              #
################################################################################

cat > spinnaker-service-account.yaml <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: spinnaker-role
rules:
- apiGroups: [""]
  resources: ["configmaps", "namespaces", "pods", "secrets", "services"]
  verbs: ["*"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["list", "get"]
- apiGroups: ["apps"]
  resources: ["controllerrevisions", "deployments", "statefulsets"]
  verbs: ["*"]
- apiGroups: ["extensions", "app"]
  resources: ["daemonsets", "deployments", "ingresses", "networkpolicies", "replicasets"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: spinnaker-role-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: spinnaker-role
subjects:
- namespace: default
  kind: ServiceAccount
  name: spinnaker-service-account
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: spinnaker-service-account
  namespace: default
EOF

kubectl apply -f spinnaker-service-account.yaml

hal config provider kubernetes enable

hal config provider kubernetes account add spinnaker \
  --provider-version v2 \
  --context $(kubectl config current-context)

hal config features edit --artifacts true

hal deploy apply

################################################################################
#                                                                              #
#               Configure oAuth in Spinnaker                                   #
#                                                                              #
################################################################################

# To create a CLIENT_ID and CLIENT_SECRET
# https://www.spinnaker.io/setup/security/authentication/oauth/providers/google/
#
# SET THE 'Authorized redirect URIs' to http://cah-spinnaker-api.jxtr.us/login

CLIENT_ID=xxx
CLIENT_SECRET=xxx
PROVIDER=google

hal config security authn oauth2 edit \
  --client-id $CLIENT_ID \
  --client-secret $CLIENT_SECRET \
  --provider $PROVIDER \
  --user-info-requirements hd=gflocks.com

hal config security authn oauth2 enable

hal deploy apply


################################################################################
#                                                                              #
#               Configure SSL for Spinnaker                                    #
#                                                                              #
################################################################################

# Automagically generate self-signed SSL certs
#
# mkdir certs
# docker run -v $(PWD)/certs:/certs \
#   -e SSL_SUBJECT=jxtr.us \
#   paulczar/omgwtfssl

# Create the CA key.
openssl genrsa -des3 -out ca.key 4096

# Self-sign the CA certificate.
openssl req -new -x509 -days 365 -key ca.key -out ca.crt

# Create the server key. Keep this file safe!
openssl genrsa -des3 -out server.key 4096

# Generate a certificate signing request for the server. Specify `localhost` or 
# Gate’s eventual fully-qualified domain name (FQDN) as the Common Name (CN).
openssl req -new -key server.key -out server.csr

# Use the CA to sign the server’s request. If using an external CA, they will
# do this for you.
openssl x509 -req -days 365 -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt

# Format server certificate into Java Keystore (JKS) importable form
YOUR_KEY_PASSWORD=hunter2
openssl pkcs12 -export -clcerts -in server.crt -inkey server.key -out server.p12 -name spinnaker -password pass:$YOUR_KEY_PASSWORD

# Create Java Keystore by importing CA certificate
keytool -keystore keystore.jks -import -trustcacerts -alias ca -file ca.crt

# Import server certificate
keytool \
  -importkeystore \
  -srckeystore server.p12 \
  -srcstoretype pkcs12 \
  -srcalias spinnaker \
  -srcstorepass $YOUR_KEY_PASSWORD \
  -destkeystore keystore.jks \
  -deststoretype jks \
  -destalias spinnaker \
  -deststorepass $YOUR_KEY_PASSWORD \
  -destkeypass $YOUR_KEY_PASSWORD

# Use Halyard to Configure Gate
KEYSTORE_PATH=keystore.jks

hal config security api ssl edit \
  --key-alias spinnaker \
  --keystore $KEYSTORE_PATH \
  --keystore-password \
  --keystore-type jks \
  --truststore $KEYSTORE_PATH \
  --truststore-password \
  --truststore-type jks

hal config security api ssl enable

# For Deck:
SERVER_CERT=server.crt
SERVER_KEY=server.key

hal config security ui ssl edit \
  --ssl-certificate-file $SERVER_CERT \
  --ssl-certificate-key-file $SERVER_KEY \
  --ssl-certificate-passphrase

hal config security ui ssl enable

hal config security ui edit \
  --override-base-url https://$DNS_NAME_FOR_SPIN_DECK.$DNS_DOMAIN

hal config security api edit \
  --override-base-url https://$DNS_NAME_FOR_SPIN_GATE.$DNS_DOMAIN

# CHANGE PORT TO 443
kubectl edit svc spin-deck -n spinnaker
kubectl edit svc spin-gate -n spinnaker
```

##### Create two additional External Static Ip Addresses (Reserve them under VPC Networks/External Ip Addresses) :
```
35.203.186.39 : spin-ui

35.203.159.237 : spin-gate
```

### Validation Steps:
```
a) Check for spinnaker login page : http://spinnaker.$DOMAIN/login, the login page should appear.
b) Click on Create Application and a pop up should appear with Application related details.
c) Click on Load Balancer, the popup with LB details should appear.
d) Click on Pipelines, all its details should appear.
```
###Troubleshooting steps :
```
1) Check  main task details in the Tomcat JVM Container in the First Shell terminal.
2) Hal deploy will also depict what the exceptions are "Marked in Red" in the Second shell terminal.
3) Hal configurations can be overwritten by cleaning Hal Deploy with steps stated in Tear Down and re-run again.
```   
   
   
#### TearUp Spinnaker Workloads :
```
hal deploy clean
rm -rf ~/.hal/*
```
#### Reference Materials :
#####Using HALYARD :

* [Halyard on GKE](https://www.spinnaker.io/setup/quickstart/halyard-gke/)

#####Kubernetes Deploy Manifest : V2 provider :
   
* [Kubernetes provider : V2](https://www.spinnaker.io/setup/install/providers/kubernetes-v2/) 

##### Continous Delivery using HELM to Create Pipeline using Spinnaker on GKE :

* [Continuous delivery spinnaker kubernetes engine](https://cloud.google.com/solutions/continuous-delivery-spinnaker-kubernetes-engine)
