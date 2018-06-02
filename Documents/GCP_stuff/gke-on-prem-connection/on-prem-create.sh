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
# "-  install ElasticSearch Cluster on GKE                 -"
# "-                                                       -"
# "---------------------------------------------------------"

set -o errexit
set -o nounset
set -o pipefail

ROOT=$(dirname "${BASH_SOURCE}")
source $ROOT/common.sh

echo "install elasticsearch on ${ON_PREM_GKE_CONTEXT}"

kubectl config use-context ${ON_PREM_GKE_CONTEXT}
kubectl create -f manifests/es-discovery-svc.yaml
kubectl create -f manifests/es-svc.yaml
kubectl create -f manifests/es-master.yaml
kubectl rollout status -f manifests/es-master.yaml
kubectl create -f manifests/es-client.yaml
kubectl rollout status -f manifests/es-client.yaml
kubectl create -f manifests/es-data-svc.yaml
kubectl create -f manifests/es-data-sc.yaml
kubectl create -f manifests/es-data-stateful.yaml
kubectl rollout status -f manifests/es-data-stateful.yaml
kubectl get pods -o wide
