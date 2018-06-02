#!/bin/bash

# Copyright 2018 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


# "---------------------------------------------------------"
# "-                                                       -"
# "-  Uninstalls all k8s resources and deletes             -"
# "-  the GKE cluster                                      -"
# "-                                                       -"
# "---------------------------------------------------------"

# Do not set errexit as it makes partial deletes impossible
set -o nounset
set -o pipefail

ROOT=$(dirname "${BASH_SOURCE}")
source $ROOT/common.sh

kubectl config use-context ${ON_PREM_GKE_CONTEXT}
kubectl delete -f manifests/

# You have to wait the default pod grace period before you can delete the pvcs
echo "Sleeping 60 seconds before deleting PVCs. The default pod grace period."
sleep 60

# delete the pvcs
kubectl delete pvc -l component=elasticsearch,role=data

# Get credentials for the k8s cluster
#gcloud container clusters get-credentials $ON_PREM_CLUSTER_NAME --zone $ON_PREM_ZONE

# Cleanup the cluster
#echo "Deleting cluster"
#gcloud container clusters delete $ON_PREM_CLUSTER_NAME --zone $ON_PREM_ZONE --async
