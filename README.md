CLO835 Project 8: Node Maintenance Drill

Student Information

Student ID: 117740258

Project Overview

This project uses a local kind Kubernetes cluster.

The cluster has:

1 control-plane node
3 worker nodes

The project runs two writer applications:

1. A hostPath application
2. An NFS application

Both applications write one line to `/data/log.txt` every 5 seconds.

Each line includes:

My student ID
Current date and time
Storage type

Example:
117740258 Sat Jul 18 22:36:21 UTC 2026 hostpath


Project Structure
<img width="1265" height="655" alt="image" src="https://github.com/user-attachments/assets/fc533ef3-3869-49b9-b3f7-7f60c318a975" />

CLO835-node-maintenance/
kind-config.yaml
bootstrap.sh
README.md
runbook.md
manifests/
   00-namespace.yaml
   01-nfs-server.yaml
   02-nfs-service.yaml
   03-nfs-pv.yaml
   04-nfs-pvc.yaml
   05-app-hostpath.yaml
   06-app-nfs.yaml
evidence/


Requirements

The following tools are required:

Docker
kind
kubectl
Git
Bash

This project does not use Helm, Kustomize, EKS, or cloud storage.

Cluster Information

Cluster name:maint-117740258


Namespace:maint-117740258


Nodes:
maint-117740258-control-plane
maint-117740258-worker
maint-117740258-worker2
maint-117740258-worker3


The first worker has this label:
disk=local-117740258


The hostPath application uses this label in its `nodeSelector`.

HostPath Application

Deployment name:app-hostpath-117740258


The application is pinned to:maint-117740258-worker


It uses this directory on the node:/tmp/maint-117740258-hostpath


The directory is mounted inside the container at:/data


HostPath data is local to one node. The data does not move with the Pod.

If the hostPath node is drained, the new Pod stays Pending because the only matching node is unschedulable.

After the node is uncordoned, the Pod can run on the same node again and read the old data.

NFS Server

Deployment name:nfs-server-117740258


Image:gists/nfs-server:2.6.4


The NFS Server uses:hostNetwork: true


It exports:/exports


The server uses NFS version 4.1.

The exported directory uses:emptyDir


This means the data is temporary. If the NFS Server Pod is deleted and recreated, the old NFS data is lost.

NFS Service and Storage

Service name:nfs-svc-117740258


PV name:pv-nfs-117740258


PVC name:pvc-nfs-117740258


The PV uses:ReadWriteMany


The PVC uses static binding with:
storageClassName: 


The NFS mount options are:
mountOptions:
  - vers=4.1
  - proto=tcp
  - timeo=20
  - retrans=1


 NFS Application

Deployment name:app-nfs-117740258


The application mounts the PVC at:/data

The NFS application is not pinned to one node.

It uses Pod anti-affinity so that it does not run on the same worker as the NFS Server.

If the NFS application node is drained, the Pod can move to another worker and mount the same PVC. Its old data should still be available.

 Bootstrap

Run the following command:./bootstrap.sh


The script:
1. Checks the required tools
2. Creates the kind cluster
3. Waits for the nodes
4. Labels the hostPath worker
5. Deploys the namespace, NFS server and NFS service
6. Waits for the PV and PVC
7. Waits for all Deployments
8. Shows Pod placement
9. Shows data from both applications
bootstrap.sh reads the current NFS Service ClusterIP and injects it into the static PV manifest using sed. This keeps clean deployments reproducible when Kubernetes assigns a different Service IP.

Check the System
Check nodes:kubectl get nodes
Check Pods:kubectl get pods -n maint-117740258 -o wide


Check storage:
kubectl get pv
kubectl get pvc -n maint-117740258


Check hostPath data:
kubectl exec -n maint-117740258 deployment/app-hostpath-117740258 -- tail -3 /data/log.txt


Check NFS data:
kubectl exec -n maint-117740258 deployment/app-nfs-117740258 -- tail -3 /data/log.txt


 Main Learning Points

This project shows that:

1. Cordon stops new Pods from using a node.
2. Drain removes normal Pods from a node.
3. A pinned Pod may stay Pending after a drain.
4. hostPath data belongs to one node.
5. NFS data can be shared by Pods on different nodes.
6. An NFS Server is a shared dependency.
7. A PV object can still exist even if the real NFS data is lost.

See runbook.md for the live demo commands.
