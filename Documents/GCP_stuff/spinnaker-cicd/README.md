# Setup basic Spinnaker in GKE cluster

## Introduction

This script automates setup of Spinnaker in a GCP GKE managed cluster. It uses bash to accomplish most tasks. It is meant to provide a stable base installation for CICD POCs.

## Architecture

The script provides cluster creation, service account creation, role assignment, bucket creation, and pub/sub
topic creation and subscriptions.

The deploy script is executed inside a cloud shell environment. The script will setup GCP resources and configure Spinnaker using halyard.

Resources created by the tool is appended by a random string used as an "id" for the deployment.
```
[cluster-name]-[id]
```

## Project Structure

scripts:
spinnaker-gke-halyard-deploy.sh
spinnaker-gke-halyard-clean.sh
halyard-host-pubsub-v2.sh
portforward.sh

resources:
/home/[user]/.gcp/

## Prerequisites

Please install gcloud suite.

```
Google Cloud SDK - https://cloud.google.com/sdk/
```

Ensure the following APIs are enabled
- Google Identity and Access Management (IAM) API
- Google Cloud Resource Manager API
- Google Pub/Sub API
- Kubernetes Engine API

## Deployment

Deploy fresh installation of Spinnaker on GKE.

```
1. login to cloud shell

2. create bash script

3. sh spinnaker-gke-halyard-deploy.sh

```

## Validation

Connect to halyard host and setup ssh tunnel.

```
gcloud compute ssh $USER@$HALYARD_HOST --project=$PROJECT --zone=$ZONE --ssh-flag="-L 9000:localhost:9000"  --ssh-flag="-L 8084:localhost:8084"
```

Once connected to halyard-host.
```
hal deploy connect
```

Open browser and make sure Spinnaker ui appears.

## Template POC

Prerequisite:
Create an application and pipeline configuration on the UI.

```
1. gcloud compute ssh $USER@$HALYARD_HOST --project=$PROJECT --zone=$ZONE

2. export SPINNAKER_API=http://localhost:8084

3. ./roer-linux-amd64 pipeline-template convert deploy-app

4. Copy template to template.yml removing INFO[] markers; edit variables/template

5. ./roer-linux-amd64 pipeline-template publish template.yml
```

## Tear Down

```
1. find cluster id to delete
ls /home/[user]/.gcp

2. note the cluster id from above
[cluster-name]-[id]

3. sh spinnnaker-gke-halyard-clean.sh [id]

```

## Troubleshooting

## Authors

* **Arnold Cabreza** - *Initial repo*

## Lincense

This project is licensed under the Apache License - see the [LICENSE.md](LICENSE.md) file for details
