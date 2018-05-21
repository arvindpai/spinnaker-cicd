#!/bin/bash -e

USER=paia
HALYARD_HOST=halyard-host-88261f64
PROJECT=deploy-manifest-poc
ZONE=us-central1-f

gcloud compute ssh $USER@$HALYARD_HOST --project=$PROJECT --zone=$ZONE --ssh-flag="-L 9000:localhost:9000" --ssh-flag="-L 8084:localhost:8084"
# Once logged in execute hal deploy connect
