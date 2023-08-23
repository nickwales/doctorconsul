#!/bin/bash

export CONSUL_HTTP_TOKEN=root
export CONSUL_HTTP_SSL_VERIFY=false

export RED='\033[1;31m'
export BLUE='\033[1;34m'
export DGRN='\033[0;32m'
export GRN='\033[1;32m'
export YELL='\033[0;33m'
export NC='\033[0m'

export DC1="http://127.0.0.1:8500"
export DC2="http://127.0.0.1:8501"
export DC3="https://127.0.0.1:8502"
export DC4="https://127.0.0.1:8503"
export DC5=""
export DC6=""

export KDC3="k3d-dc3"
export KDC3_P1="k3d-dc3-p1"
export KDC4="k3d-dc4"
export KDC4_P1="k3d-dc4-p1"

export FAKESERVICE_VER="v0.26.0"

export HELM_CHART_VER=""
# HELM_CHART_VER="--version 1.2.0-rc1"                # pinned consul-k8s chart version


export GCP_PROJECT_ID=hc-1de95f2aa38e498ab96760d6cba
export GCP_REGION=us-east1
# Get the project from the GCP UI upper right hamburger > project settings

export AWS_REGION=us-east-1

# ==============================================================================================================================
#                                                        General Functions
# ==============================================================================================================================

consul_binary_check() {
  echo -e "${GRN}Consul Binary Check: ${NC}"

  # Check if 'consul' command is available
  if ! command -v consul &> /dev/null
  then
      echo -e "${RED}Consul command could not be found. ${NC}"
      echo -e "Please make sure it is installed and available in your PATH."
      printf "${RED}"'Make sure Consul is on the latest enterprise version!!! '"${NC}\n"
      exit 1
  fi

  # Print the location of 'consul'
  echo -e "Consul is located at: ${YELL}$(which consul)"

  # Run 'consul version' and print only the lines that contain 'Consul'
  echo -e "${YELL}$(consul version | grep Consul) ${NC}"
  printf "${RED}"'Make sure Consul is on the latest enterprise version!!! '"${NC}\n"
}

CleanupTempStuff () {    # Delete temporary files and kill lingering processes

  echo ""
  echo -e "${RED}Nuking the Env Variables...${NC}"
  for var in $(env | grep -Eo '^DC[34][^=]*')
    do
        unset $var
    done

  if [[ $PWD == *"doctorconsul"* ]]; then
    echo -e "${RED}Nuking the tokens...${NC}"

    rm -f ./tokens/*
  else
      echo -e "${RED}The kill script should only be executed from within the Doctor Consul Directory.${NC}"
  fi

  echo -e "${RED}Nuking kubectl local port forwards...${NC}"
  pkill kubectl
  echo ""
}

fakeservice_from_internet() {
  find ./kube/configs/dc3/services/*.yaml -type f -exec sed -i "s/^\( *\)image: .*/\1image: nicholasjackson\/fake-service:$FAKESERVICE_VER/" {} \;
  find ./kube/configs/dc4/services/*.yaml -type f -exec sed -i "s/^\( *\)image: .*/\1image: nicholasjackson\/fake-service:$FAKESERVICE_VER/" {} \;
  # Pull fake service from the interwebz instead of local k3d registry (which doesn't exist when using EKS)
}

fakeservice_from_k3d() {
  find ./kube/configs/dc3/services/*.yaml -type f -exec sed -i "s/^\( *\)image: .*/\1image: k3d-doctorconsul.localhost:12345\/nicholasjackson\/fake-service:$FAKESERVICE_VER/" {} \;
  find ./kube/configs/dc4/services/*.yaml -type f -exec sed -i "s/^\( *\)image: .*/\1image: k3d-doctorconsul.localhost:12345\/nicholasjackson\/fake-service:$FAKESERVICE_VER/" {} \;
  # Puts the files back to a local k3d registry if they were previously changed (same as checked into the repo)
}

wait_for_consul_connect_inject_service() {
    local context="$1"
    local deployment_name="$2"
    local label="$3"

    echo -e "${RED}Waiting for ${label} connect-inject service to be ready...${NC}"
    until kubectl get deployment "${deployment_name}" -n consul --context "${context}" -ojson | jq -r .status.availableReplicas | grep 1 > /dev/null; do
        echo -e "${RED}Waiting for ${label} connect-inject service to be ready...${NC}"
        sleep 3
    done
    echo -e "${YELL}${label} connect-inject service is READY! ${NC}"
    echo -e ""

    # Example:
    # wait_for_consul_connect_inject_service $KDC3 "consul-connect-injector" "DC3 (default)"
}

k3dPeeringToVM() {
  # Peers the local k3d clusters to the doctor consul docker compose clusters DC1 / DC2 (they must be running, obviously)

  # ------------------------------------------
  # Peer DC3/default -> DC1/default
  # ------------------------------------------

  echo -e ""
  echo -e "${GRN}DC3/default -> DC1/default${NC}"

  consul peering generate-token -name dc3-default -http-addr="$DC1" > tokens/peering-dc1_default-dc3-default.token

  kubectl create secret generic peering-token-dc1-default-dc3-default --namespace consul --from-literal=data=$(cat tokens/peering-dc1_default-dc3-default.token)
  kubectl label secret peering-token-dc1-default-dc3-default -n consul "consul.hashicorp.com/peering-token=true"
  kubectl apply --namespace consul -f ./kube/configs/peering/peering_dc3-default_dc1-default.yaml

  # ------------------------------------------
  # Peer DC3/default -> DC1/Unicorn
  # ------------------------------------------

  echo -e ""
  echo -e "${GRN}DC3/default -> DC1/Unicorn${NC}"

  consul peering generate-token -name dc3-default -partition="unicorn" -http-addr="$DC1" > tokens/peering-dc3-default_dc1-unicorn.token

  kubectl create secret generic peering-token-dc3-default-dc1-unicorn --namespace consul --from-literal=data=$(cat tokens/peering-dc3-default_dc1-unicorn.token)
  kubectl label secret peering-token-dc3-default-dc1-unicorn -n consul "consul.hashicorp.com/peering-token=true"
  kubectl apply --namespace consul -f ./kube/configs/peering/peering_dc3-default_dc1-unicorn.yaml

  # ------------------------------------------
  # Peer DC3/default -> DC2/Unicorn
  # ------------------------------------------

  echo -e ""
  echo -e "${GRN}DC3/default -> DC2/Unicorn${NC}"

  consul peering generate-token -name dc3-default -partition="unicorn" -http-addr="$DC2" > tokens/peering-dc3-default_dc2-unicorn.token

  kubectl create secret generic peering-token-dc3-default-dc2-unicorn --namespace consul --from-literal=data=$(cat tokens/peering-dc3-default_dc2-unicorn.token)
  kubectl label secret peering-token-dc3-default-dc2-unicorn -n consul "consul.hashicorp.com/peering-token=true"
  kubectl apply --namespace consul -f ./kube/configs/peering/peering_dc3-default_dc2-unicorn.yaml
}

UpgradeConsulBinary() {
  (
    # If no argument is provided, prompt the user for input
    if [ -z "$1" ]; then
        while true; do
            read -p "Please specify a Consul version (or enter 'latest' or 'latest+ent'): " input_version
            if [[ "$input_version" =~ ^(latest|latest\+ent|[0-9]+\.[0-9]+\.[0-9]+(\+ent)?)$ ]]; then
                CONSUL_VER=${input_version}
                break
            else
                echo "Invalid format. Please enter a valid Consul version (or 'latest' or 'latest+ent')."
            fi
        done
    else
        if [[ ! "$1" =~ ^(latest|latest\+ent|[0-9]+\.[0-9]+\.[0-9]+(\+ent)?)$ ]]; then
            echo "Invalid argument format."
            exit 1
        fi
        CONSUL_VER="$1"
    fi

    if [ "$CONSUL_VER" == "latest" ]; then
        CONSUL_VER="$(curl -s "https://api.github.com/repos/hashicorp/consul/releases/latest" | jq -r .tag_name | sed 's/^v//')"
    elif [ "$CONSUL_VER" == "latest+ent" ]; then
        CONSUL_VER="$(curl -s "https://api.github.com/repos/hashicorp/consul/releases/latest" | jq -r .tag_name | sed 's/^v//')+ent"
    fi

    curl -s "https://api.github.com/repos/hashicorp/consul/releases/latest" | jq -r .tag_name | sed 's/^v//'

    DIR=$HOME/consul_temp
    BIN_DIR=/usr/local/bin

    echo -e "${YELL}local binary directory is:${NC}$BIN_DIR"
    echo -e "${YELL}Temp Directory is:${NC}"$DIR
    echo ""

    if [ ! -d "$DIR" ]; then
    mkdir "$DIR"
    fi

    cd "$DIR" || exit

    echo -e "${GRN}Downloading and unzipping Consul: ${NC}"
    wget -q https://releases.hashicorp.com/consul/$CONSUL_VER/consul_${CONSUL_VER}_linux_amd64.zip
    unzip consul_${CONSUL_VER}_linux_amd64.zip

    echo ""
    echo -e "${GRN}Moving Consul ($CONSUL_VER) to $BIN_DIR${NC}"
    mv consul consul-$CONSUL_VER
    sudo mv consul-$CONSUL_VER $BIN_DIR

    # if [ -e "$BIN_DIR/consul" ] || [ -L "$BIN_DIR/consul" ]; then    # Nuke symlink or existing consul binary.
    #     sudo rm "$BIN_DIR/consul"
    # fi

    sudo ln -sf $BIN_DIR/consul_${CONSUL_VER} $BIN_DIR/consul    # New symlink

    echo ""
    echo -e "${RED}Deleting Temp directory:${NC} $DIR"
    rm -rf $DIR

    echo ""

  )
}


# ==============================================================================================================================
#                                                AWS (EKSOnly) Functions
# ==============================================================================================================================

update_aws_context() {
    echo -e "${GRN}Setting Contexts from EKSonly (https://github.com/ramramhariram/EKSonly):${NC}"
    echo ""
    echo -e "${YELL}Terraform EKSOnly state file is currently:${NC} $EKSONLY_TF_STATE_FILE"
    echo ""
    aws eks update-kubeconfig --region $AWS_REGION --name nEKS0 --alias $KDC3
    aws eks update-kubeconfig --region $AWS_REGION --name nEKS1 --alias $KDC3_P1
    aws eks update-kubeconfig --region $AWS_REGION --name nEKS2 --alias $KDC4
    aws eks update-kubeconfig --region $AWS_REGION --name nEKS3 --alias $KDC4_P1
    echo ""
}

nuke_consul_k8s() {
  set +e
  echo -e "${GRN}Deleting Consul Helm installs in each Cluster:${NC}"

  echo -e "${YELL}DC3:${NC} $(consul-k8s uninstall -auto-approve -context $KDC3)" &
  echo -e "${YELL}DC3_P1:${NC} $(consul-k8s uninstall -auto-approve -context $KDC3_P1)" &
  echo -e "${YELL}DC4:${NC} $(consul-k8s uninstall -auto-approve -context $KDC4)" &
  echo -e "${YELL}DC4_P1:${NC} $(consul-k8s uninstall -auto-approve -context $KDC4_P1)" &

  echo ""

  echo -e "${GRN}Deleting additional DC3 Loadbalancer services:${NC}"
  kubectl delete --namespace consul --context $KDC3 -f ./kube/prometheus/dc3-prometheus-service.yaml
  kubectl delete svc unicorn-frontend -n unicorn --context $KDC3 &
  kubectl delete svc consul-api-gateway -n consul --context $KDC3 &

  echo -e "${GRN}Deleting additional DC3 (Cernunnos) Loadbalancer services:${NC}"
  kubectl delete svc leroy-jenkins -n paris --context $KDC3_P1 &
  kubectl delete svc pretty-please -n paris --context $KDC3_P1 &

  echo -e "${GRN}Deleting additional DC4 Loadbalancer services:${NC}"
  kubectl delete svc sheol-app -n sheol --context $KDC4 &
  kubectl delete svc sheol-app1 -n sheol-app1 --context $KDC4 &
  kubectl delete svc sheol-app2 -n sheol-app2 --context $KDC4 &

  # If you need to nuke all the CRDs to nuke namespaces, this can be used. Don't typically need to do this just to "tf destroy" though.
  # This is really on for rebuilding Doctor Consul useing the same eksonly clusters.
  CONTEXTS=("$KDC3" "$KDC3_P1" "$KDC4" "$KDC4_P1")

  for CONTEXT in "${CONTEXTS[@]}"; do
    kubectl get crd -n consul --context $CONTEXT -o jsonpath='{.items[*].metadata.name}' | tr -s ' ' '\n' | grep "consul.hashicorp.com" | while read -r CRD
    do
      kubectl patch crd/$CRD -n consul --context $CONTEXT -p '{"metadata":{"finalizers":[]}}' --type=merge
      kubectl delete crd/$CRD --context $CONTEXT
    done
  done

  for CONTEXT in "${CONTEXTS[@]}"; do
    kubectl delete namespace consul --context $CONTEXT &
  done

  for CONTEXT in "${CONTEXTS[@]}"; do
    kubectl delete namespace unicorn --context $CONTEXT &
  done

  for CONTEXT in "${CONTEXTS[@]}"; do
    kubectl delete namespace externalz --context $CONTEXT &
  done

  kubectl delete namespace sheol --context $KDC4 &
  kubectl delete namespace sheol-app1 --context $KDC4 &
  kubectl delete namespace sheol-app2 --context $KDC4 &
  kubectl delete namespace paris --context $KDC3_P1 &

  CleanupTempStuff

  wait

}

# ==============================================================================================================================
#                                                     GKE Functions
# ==============================================================================================================================

# Function to create GKE cluster

create_gke_cluster() {
    local CLUSTER_NAME="$1"

    (gcloud container clusters create-auto "$CLUSTER_NAME" \
      --project $GCP_PROJECT_ID \
      --region $GCP_REGION --release-channel "regular" \
      --network "projects/$GCP_PROJECT_ID/global/networks/default" \
      --subnetwork "projects/$GCP_PROJECT_ID/regions/$GCP_REGION/subnetworks/default" \
      --cluster-ipv4-cidr "/17" > /dev/null 2>&1 && echo "Cluster $CLUSTER_NAME creation successful!" || echo "Cluster creation failed!") &
}

# Change gke contexts to match doctor consul friendly ones.

update_gke_context() {
    local CLUSTER_NAME="$1"

    echo ""
    echo -e "${GRN}$CLUSTER_NAME:${NC}"

    # Update kube config from GKE
    gcloud container clusters get-credentials $CLUSTER_NAME --region $GCP_REGION --project $GCP_PROJECT_ID

    # Delete the context
    kubectl config delete-context "$CLUSTER_NAME"

    # Rename the context
    kubectl config rename-context gke_${GCP_PROJECT_ID}_${GCP_REGION}_$CLUSTER_NAME $CLUSTER_NAME
}

# ==============================================================================================================================
#                                                             FIN
# ==============================================================================================================================

echo ""
echo -e "${GRN}Functions file is done sourced. ${NC}"
echo ""
