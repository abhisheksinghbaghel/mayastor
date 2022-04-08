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

kubectl label nodes --selector agentpool=storagepool openebs.io/engine=mayastor --overwrite

kubectl apply -f "${PKG_ROOT}/scripts/deploy/actions/hugepage-enabler-daemonset.yaml"
kubectl rollout status daemonset/hugepage --watch --timeout 5m
kubectl apply -f "${PKG_ROOT}/scripts/deploy/actions/kured-config.yaml"
sleep 5m

kubectl create namespace mayastor
kubectl apply -f https://raw.githubusercontent.com/openebs/mayastor-control-plane/master/deploy/operator-rbac.yaml
kubectl apply -f https://raw.githubusercontent.com/openebs/mayastor-control-plane/master/deploy/mayastorpoolcrd.yaml

kubectl apply -f "${PKG_ROOT}/scripts/deploy/config/etcd-azure.yaml"
kubectl apply -f https://raw.githubusercontent.com/openebs/mayastor/master/deploy/etcd/svc.yaml
kubectl apply -f https://raw.githubusercontent.com/openebs/mayastor/master/deploy/etcd/svc-headless.yaml
kubectl rollout status statefulset/mayastor-etcd --namespace mayastor --watch --timeout 5m

kubectl apply -f https://raw.githubusercontent.com/openebs/mayastor/master/deploy/nats-deployment.yaml
kubectl rollout status statefulset/nats --namespace mayastor --watch --timeout 5m

kubectl apply -f https://raw.githubusercontent.com/openebs/mayastor/master/deploy/csi-daemonset.yaml
kubectl rollout status daemonset/mayastor-csi --namespace mayastor --watch --timeout 5m

kubectl apply -f https://raw.githubusercontent.com/openebs/mayastor-control-plane/master/deploy/core-agents-deployment.yaml
kubectl rollout status deployment/core-agents --namespace mayastor --watch --timeout 5m

kubectl apply -f https://raw.githubusercontent.com/openebs/mayastor-control-plane/master/deploy/rest-deployment.yaml
kubectl apply -f https://raw.githubusercontent.com/openebs/mayastor-control-plane/master/deploy/rest-service.yaml
kubectl rollout status deployment/rest --namespace mayastor --watch --timeout 5m

kubectl apply -f https://raw.githubusercontent.com/openebs/mayastor-control-plane/master/deploy/csi-deployment.yaml
kubectl rollout status deployment/csi-controller --namespace mayastor --watch --timeout 5m

kubectl apply -f https://raw.githubusercontent.com/openebs/mayastor-control-plane/master/deploy/msp-deployment.yaml
kubectl rollout status deployment/msp-operator --namespace mayastor --watch --timeout 5m

kubectl apply -f https://raw.githubusercontent.com/openebs/mayastor/master/deploy/mayastor-daemonset.yaml
kubectl rollout status daemonset/mayastor --namespace mayastor --watch --timeout 5m