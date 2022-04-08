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

readonly GIT_ROOT=$(git rev-parse --show-toplevel)

source "${GIT_ROOT}/scripts/deploy/common-setup.sh"
source "${GIT_ROOT}/scripts/deploy/resource-status.sh"

#
# Define common functions.
#
printhelp() {
  cat <<EOF
cluster-up.sh: Creates a Kubernetes cluster in the Azure cloud and install OpenEBS.
Options:
  -l, --location     [Required] : The region.
  -s, --subscription [Required] : The subscription identifier.
  -n, --name string             : The Kubernetes cluster DNS name. Defaults to
                                  k8s-<git-commit>-<template>.
  -c, --client-id string        : The service principal identifier. Default to
                                  <name>-sp.
  -e, --client-tenant string    : The client tenant. Required if --client-id
                                  is used.
  -p, --client-secret string    : The service principal password.  Required if
                                  --client-id is used.
  -o, --output string           : The output directory. Defaults to
                                  ./_output/<name>.
  -r, --resource-group string   : The resource group name. Defaults to 
                                  <name>-rg
  -t, --template string         : The cluster template name or URL. Defaults
                                  to single-az.
  -v, --k8s-version string      : The Kubernetes version. Defaults to 1.22.
EOF
}

#
# Process the command line arguments.
#
unset AZURE_CLIENT_ID
unset AZURE_CLIENT_SECRET
unset AZURE_CLUSTER_DNS_NAME
unset AZURE_CLUSTER_TEMPLATE
unset AZURE_K8S_VERSION
unset AZURE_LOCATION
unset AZURE_RESOURCE_GROUP
unset AZURE_SUBSCRIPTION_ID
unset AZURE_TENANT_ID
unset OUTPUT_DIR
POSITIONAL=()

while [[ $# -gt 0 ]]
do
  ARG="$1"
  case $ARG in

    -c|--client-id)
      AZURE_CLIENT_ID="$2"
      shift 2 # skip the option arguments
      ;;

    -d|--debug)
      set -x
      shift
      ;;

    -e|--client-tenant)
      AZURE_TENANT_ID="$2"
      shift 2 # skip the option arguments
      ;;

    -l|--location)
      AZURE_LOCATION="$2"
      shift 2 # skip the option arguments
      ;;

    -n|--name)
      AZURE_CLUSTER_DNS_NAME="$2"
      shift 2 # skip the option arguments
      ;;

    -o|--output)
      OUTPUT_DIR="$2"
      shift 2 # skip the option arguments
      ;;

    -p|--client-secret)
      AZURE_CLIENT_SECRET="$2"
      shift 2 # skip the option arguments
      ;;
    
    -r|--resource-group)
      AZURE_RESOURCE_GROUP="$2"
      shift 2 # skip the option arguments
      ;;

    -s|--subscription)
      AZURE_SUBSCRIPTION_ID="$2"
      shift 2 # skip the option arguments
      ;;

    -t|--template)
      AZURE_CLUSTER_TEMPLATE="$2"
      shift 2 # skip the option arguments
      ;;

    -v|--k8s-version)
      AZURE_K8S_VERSION="$2"
      shift 2 # skip the option arguments
      ;;

    -?|--help)
      printhelp
      exit 1
      ;;

    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters


#
# Validate command-line arguments and initialize variables.
#
if [[ ${#POSITIONAL[@]} -ne 0 ]]; then
  echoerr "ERROR: Unknown positional parameters - ${POSITIONAL[*]}"
  printhelp
  exit 1
fi

if [[ -z ${AZURE_SUBSCRIPTION_ID:-} ]]; then
  echoerr "ERROR: The --subscription option is required."
  printhelp
  exit 1
fi

if [[ -z ${AZURE_LOCATION:-} ]]; then
  echoerr "ERROR: The --location option is required."
  printhelp
  exit 1
fi

if [[ -n ${AZURE_CLIENT_ID:-} ]]; then
  if [[ -z ${AZURE_CLIENT_SECRET:-} ]]; then
    echoerr "ERROR: The --client-secret option is required when --client-id is used."
    printhelp
    exit 1
  fi
  if [[ -z ${AZURE_TENANT_ID:-} ]]; then
    echoerr "ERROR: The --client-tenant option is required when --client-id is used."
    printhelp
    exit 1
  fi
fi

if [[ -z ${AZURE_CLUSTER_TEMPLATE:-} ]]; then
  AZURE_CLUSTER_TEMPLATE="single-az"
fi

if [[ -z ${AZURE_K8S_VERSION:-} ]]; then
  AZURE_K8S_VERSION="1.22"
fi

IS_AZURE_CLUSTER_TEMPLATE_URI=$(expr "$(expr "${AZURE_CLUSTER_TEMPLATE}" : "file://\|https://\|http://")" != 0 || true)

if [[ ${IS_AZURE_CLUSTER_TEMPLATE_URI} -eq 0 ]]; then
  AZURE_CLUSTER_TEMPLATE_ROOT=${GIT_ROOT}/scripts/deploy
  AZURE_CLUSTER_TEMPLATE_FILE=${AZURE_CLUSTER_TEMPLATE_ROOT}/cluster/${AZURE_CLUSTER_TEMPLATE}/aks-config.json

  if [[ ! -f "$AZURE_CLUSTER_TEMPLATE_FILE" ]]; then
    AZURE_CLUSTER_VALID_TEMPLATES=$(find "${AZURE_CLUSTER_TEMPLATE_ROOT}" -maxdepth 1 -printf "%P\n" | awk '{split($1,f,"."); printf (NR>1?", ":"") f[1]}')
    echoerr "ERROR: The template '$AZURE_CLUSTER_TEMPLATE' is not known. Select one of the following values: $AZURE_CLUSTER_VALID_TEMPLATES."
    printhelp
    exit 1
  fi

  AZURE_CLUSTER_TEMPLATE_FILE=file://${AZURE_CLUSTER_TEMPLATE_FILE}
else
  AZURE_CLUSTER_TEMPLATE_FILE=${AZURE_CLUSTER_TEMPLATE}
fi

if [[ -z ${AZURE_CLUSTER_DNS_NAME:-} ]]; then
  CLUSTER_PREFIX=$(whoami)
  if [[ ${CLUSTER_PREFIX:-root} == "root" ]]; then
    CLUSTER_PREFIX=k8s
  fi
  AZURE_CLUSTER_DNS_NAME=$(basename "$(mktemp -t "${CLUSTER_PREFIX}-${AZURE_CLUSTER_TEMPLATE}-${GIT_COMMIT}-XXX")")
fi

if [[ -z ${AZURE_RESOURCE_GROUP:-} ]]; then
  AZURE_RESOURCE_GROUP=${AZURE_CLUSTER_DNS_NAME}-rg
fi

if [[ -z ${OUTPUT_DIR:-} ]]; then
  OUTPUT_DIR="$GIT_ROOT/_output/$AZURE_CLUSTER_DNS_NAME"
fi

#
# Install required tools
#
install_helm

#
# Create the Kubernetes cluster
#
echo "Creating cluster ${AZURE_CLUSTER_DNS_NAME}"
"${GIT_ROOT}/scripts/deploy/azure-cluster-up.sh" \
  --subscription "${AZURE_SUBSCRIPTION_ID}" \
  --location "${AZURE_LOCATION}" \
  --client-id "${AZURE_CLIENT_ID}" \
  --client-tenant "${AZURE_TENANT_ID}" \
  --client-secret "${AZURE_CLIENT_SECRET}" \
  --name "${AZURE_CLUSTER_DNS_NAME}" \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --output "${OUTPUT_DIR}" \
  --k8s-version "${AZURE_K8S_VERSION}" \
  --template "${AZURE_CLUSTER_TEMPLATE}"

# Delete the cluster on subsequent errors.
trap_push "\"${OUTPUT_DIR}/cluster-down.sh\"" err

export KUBECONFIG="${OUTPUT_DIR}/kubeconfig/kubeconfig.${AZURE_LOCATION}.json"


# Install the Azure Disk CSI Driver
echo "Installing Azure Disk CSI Driver..."
helm install azuredisk-csi-driver azuredisk-csi-driver \
--repo https://raw.githubusercontent.com/kubernetes-sigs/azuredisk-csi-driver/main_v2/charts/ \
--version v2.0.0-beta.2 \
--namespace kube-system  

${GIT_ROOT}/scripts/deploy/aks-install-mayastor.sh