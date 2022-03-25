#!/bin/bash
# Copyright 2021 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail

readonly PKG_ROOT="$(git rev-parse --show-toplevel)"

kubectl delete -f https://raw.githubusercontent.com/openebs/mayastor/master/deploy/mayastor-daemonset.yaml --ignore-not-found=true
kubectl rollout status daemonset/mayastor --namespace mayastor --watch --timeout 5m

kubectl delete -f https://raw.githubusercontent.com/openebs/mayastor-control-plane/master/deploy/msp-deployment.yaml --ignore-not-found=true
kubectl rollout status deployment/msp-operator --namespace mayastor --watch --timeout 5m

kubectl delete -f https://raw.githubusercontent.com/openebs/mayastor-control-plane/master/deploy/csi-deployment.yaml --ignore-not-found=true
kubectl rollout status deployment/csi-controller --namespace mayastor --watch --timeout 5m

kubectl delete -f https://raw.githubusercontent.com/openebs/mayastor-control-plane/master/deploy/rest-deployment.yaml --ignore-not-found=true
kubectl delete -f https://raw.githubusercontent.com/openebs/mayastor-control-plane/master/deploy/rest-service.yaml
kubectl rollout status deployment/rest --namespace mayastor --watch --timeout 5m

kubectl delete -f https://raw.githubusercontent.com/openebs/mayastor-control-plane/master/deploy/core-agents-deployment.yaml --ignore-not-found=true
kubectl rollout status deployment/core-agents --namespace mayastor --watch --timeout 5m

kubectl delete -f https://raw.githubusercontent.com/openebs/mayastor/master/deploy/csi-daemonset.yaml --ignore-not-found=true
kubectl rollout status daemonset/mayastor-csi --namespace mayastor --watch --timeout 5m

kubectl delete -f https://raw.githubusercontent.com/openebs/mayastor/master/deploy/nats-deployment.yaml --ignore-not-found=true
kubectl rollout status statefulset/nats --namespace mayastor --watch --timeout 5m

kubectl delete -f "${PKG_ROOT}/scripts/deploy/actions/etcd-azure.yaml" --ignore-not-found=true
kubectl delete -f https://raw.githubusercontent.com/openebs/mayastor/master/deploy/etcd/svc.yaml --ignore-not-found=true
kubectl delete -f https://raw.githubusercontent.com/openebs/mayastor/master/deploy/etcd/svc-headless.yaml --ignore-not-found=true

kubectl delete namespace mayastor --ignore-not-found=true
kubectl delete -f https://raw.githubusercontent.com/openebs/mayastor-control-plane/master/deploy/operator-rbac.yaml --ignore-not-found=true
kubectl delete -f https://raw.githubusercontent.com/openebs/mayastor-control-plane/master/deploy/mayastorpoolcrd.yaml --ignore-not-found=true

kubectl delete -f "${PKG_ROOT}/scripts/deploy/actions/hugepage-enabler-daemonset.yaml" --ignore-not-found=true
kubectl rollout status daemonset/hugepage --watch --timeout 5m

kubectl delete -f "${PKG_ROOT}/scripts/deploy/actions/kured-config.yaml" --ignore-not-found=true