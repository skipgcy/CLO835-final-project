#!/usr/bin/env bash

set -euo pipefail

STUDENT_ID="117740258"
CLUSTER_NAME="maint-${STUDENT_ID}"
NAMESPACE="maint-${STUDENT_ID}"
HOSTPATH_NODE="${CLUSTER_NAME}-worker"

echo "========================================"
echo "CLO835 Node Maintenance Drill"
echo "Student ID: ${STUDENT_ID}"
echo "Cluster: ${CLUSTER_NAME}"
echo "========================================"

echo
echo "[1/9] Checking required commands..."

for command in docker kind kubectl; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "ERROR: ${command} is not installed or not in PATH."
    exit 1
  fi
done

docker info >/dev/null 2>&1 || {
  echo "ERROR: Docker is not running."
  exit 1
}

echo "Required commands are available."

echo
echo "[2/9] Checking for an existing kind cluster..."

if kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  echo "Cluster ${CLUSTER_NAME} already exists."
  echo "Delete it before running a clean bootstrap:"
  echo "kind delete cluster --name ${CLUSTER_NAME}"
  exit 1
fi

echo
echo "[3/9] Creating the kind cluster..."

kind create cluster \
  --name "${CLUSTER_NAME}" \
  --config kind-config.yaml

kubectl config use-context "kind-${CLUSTER_NAME}"

echo
echo "[4/9] Waiting for all Kubernetes nodes..."

kubectl wait \
  --for=condition=Ready \
  nodes \
  --all \
  --timeout=180s

kubectl get nodes -o wide

echo
echo "[5/9] Labeling the hostPath worker..."

kubectl label node "${HOSTPATH_NODE}" \
  "disk=local-${STUDENT_ID}" \
  --overwrite

kubectl get node "${HOSTPATH_NODE}" --show-labels

echo
echo "[6/9] Applying the namespace and NFS server..."

kubectl apply -f manifests/00-namespace.yaml
kubectl apply -f manifests/01-nfs-server.yaml
kubectl apply -f manifests/02-nfs-service.yaml

echo
echo "Waiting for the NFS server..."

kubectl rollout status \
  deployment/nfs-server-${STUDENT_ID} \
  -n "${NAMESPACE}" \
  --timeout=180s

echo
echo "Getting the NFS Service IP..."

NFS_SERVICE_IP=$(kubectl get service "nfs-svc-${STUDENT_ID}" \
  -n "${NAMESPACE}" \
  -o jsonpath='{.spec.clusterIP}')

if [[ -z "${NFS_SERVICE_IP}" || "${NFS_SERVICE_IP}" == "None" ]]; then
  echo "ERROR: Could not get the NFS Service ClusterIP."
  kubectl get service "nfs-svc-${STUDENT_ID}" \
    -n "${NAMESPACE}" \
    -o yaml
  exit 1
fi

echo "NFS Service IP: ${NFS_SERVICE_IP}"

echo
echo "Applying the NFS PV with the current Service IP..."

sed "s/__NFS_SERVICE_IP__/${NFS_SERVICE_IP}/g" \
  manifests/03-nfs-pv.yaml \
  | kubectl apply -f -

kubectl apply -f manifests/04-nfs-pvc.yaml

echo
echo "[7/9] Waiting for storage binding..."

for attempt in $(seq 1 60); do
  PV_STATUS=$(kubectl get pv "pv-nfs-${STUDENT_ID}" \
    -o jsonpath='{.status.phase}' 2>/dev/null || true)

  PVC_STATUS=$(kubectl get pvc "pvc-nfs-${STUDENT_ID}" \
    -n "${NAMESPACE}" \
    -o jsonpath='{.status.phase}' 2>/dev/null || true)

  if [[ "${PV_STATUS}" == "Bound" && "${PVC_STATUS}" == "Bound" ]]; then
    echo "PV and PVC are Bound."
    break
  fi

  if [[ "${attempt}" -eq 60 ]]; then
    echo "ERROR: PV/PVC did not become Bound."
    kubectl get pv
    kubectl get pvc -n "${NAMESPACE}"
    exit 1
  fi

  sleep 2
done

kubectl get pv "pv-nfs-${STUDENT_ID}"
kubectl get pvc "pvc-nfs-${STUDENT_ID}" \
  -n "${NAMESPACE}"

echo
echo "Verifying the PV uses the current NFS Service IP..."

PV_NFS_IP=$(kubectl get pv "pv-nfs-${STUDENT_ID}" \
  -o jsonpath='{.spec.nfs.server}')

echo "Service IP: ${NFS_SERVICE_IP}"
echo "PV NFS IP:  ${PV_NFS_IP}"

if [[ "${PV_NFS_IP}" != "${NFS_SERVICE_IP}" ]]; then
  echo "ERROR: PV NFS server IP does not match the Service IP."
  exit 1
fi

echo
echo "Applying the writer applications..."

kubectl apply -f manifests/05-app-hostpath.yaml
kubectl apply -f manifests/06-app-nfs.yaml

echo
echo "[8/9] Waiting for writer applications..."

kubectl rollout status \
  deployment/app-hostpath-${STUDENT_ID} \
  -n "${NAMESPACE}" \
  --timeout=180s

kubectl rollout status \
  deployment/app-nfs-${STUDENT_ID} \
  -n "${NAMESPACE}" \
  --timeout=180s


echo
echo "[9/9] Verifying application output..."

sleep 15

HOSTPATH_POD=$(kubectl get pod \
  -n "${NAMESPACE}" \
  -l "app=app-hostpath-${STUDENT_ID}" \
  -o jsonpath='{.items[0].metadata.name}')

NFS_APP_POD=$(kubectl get pod \
  -n "${NAMESPACE}" \
  -l "app=app-nfs-${STUDENT_ID}" \
  -o jsonpath='{.items[0].metadata.name}')

echo
echo "===== POD PLACEMENT ====="
kubectl get pods -n "${NAMESPACE}" -o wide

echo
echo "===== HOSTPATH DATA ====="
kubectl exec \
  -n "${NAMESPACE}" \
  "${HOSTPATH_POD}" \
  -- sh -c 'wc -l /data/log.txt; tail -3 /data/log.txt'

echo
echo "===== NFS DATA ====="
kubectl exec \
  -n "${NAMESPACE}" \
  "${NFS_APP_POD}" \
  -- sh -c 'wc -l /data/log.txt; tail -3 /data/log.txt'

echo
echo "========================================"
echo "Bootstrap completed successfully."
echo "Cluster: ${CLUSTER_NAME}"
echo "Namespace: ${NAMESPACE}"
echo "========================================"
