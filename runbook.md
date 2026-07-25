CLO835 Node Maintenance Runbook
Student ID: 117740258
Cluster: maint-117740258
Namespace: maint-117740258
Use this runbook for the live demo.
Before each important command, say what you expect to happen.

1. Clean Bootstrap
Run this before submission, not during the 10-minute demo.
./bootstrap.sh
Healthy result:
- Four nodes are Ready
- PV and PVC are Bound
- NFS Server is Running
- hostPath App is Running
- NFS App is Running
---Both applications are writing rows
Confirm that the printed Service IP and PV NFS IP are identical.
 
2. Show Final Git Commit
git status
git log -1
Expected:
nothing to commit, working tree clean
Say:
This is my final submitted commit. My working tree is clean.
 
3. Show Cluster Design
cat kind-config.yaml
kubectl get nodes -o wide
Say:
My kind cluster has one control-plane node and three worker nodes.
Show the hostPath label:
kubectl get nodes --show-labels
The hostPath node should have:
disk=local-117740258
Say:
This label pins the hostPath application to this worker.
 
4. Show Pod Placement
kubectl get pods -n maint-117740258 -o wide
Point out:
- hostPath App node
- NFS App node
- NFS Server node
Normal design:
hostPath App → maint-117740258-worker
NFS App      → another worker
NFS Server   → another worker
The NFS App and NFS Server nodes may change after a drain.
 
5. Show PV and PVC
kubectl get pv
kubectl get pvc -n maint-117740258
Expected:
pv-nfs-117740258     Bound
pvc-nfs-117740258    Bound
Say:
The PV and PVC are statically bound.
 
6. Record Baseline Data
hostPath App
kubectl exec -n maint-117740258 deployment/app-hostpath-117740258 -- wc -l /data/log.txt
kubectl exec -n maint-117740258 deployment/app-hostpath-117740258 -- tail -3 /data/log.txt
Say the row count aloud:
The hostPath baseline is ___ rows.
NFS App
kubectl exec -n maint-117740258 deployment/app-nfs-117740258 -- wc -l /data/log.txt
kubectl exec -n maint-117740258 deployment/app-nfs-117740258 -- tail -3 /data/log.txt
Say the row count aloud:
The NFS baseline is ___ rows.
 
7. Identify the Node Chosen by the Instructor
Show current placement:
kubectl get pods -n maint-117740258 -o wide
The selected worker may contain:
1.	The hostPath App
2.	The NFS App
3.	The NFS Server
State the expected result before running cordon or drain.
 
Scenario A: NFS App Node
Find the NFS App node:
NFS_APP_NODE=$(kubectl get pod -n maint-117740258 -l app=app-nfs-117740258 -o jsonpath='{.items[0].spec.nodeName}')

echo "$NFS_APP_NODE"
Prediction:
I expect the NFS App Pod to be evicted and recreated on another worker. It should mount the same PVC and keep all previous rows.
Cordon:
kubectl cordon "$NFS_APP_NODE"
Check:
kubectl get nodes
Drain:
kubectl drain "$NFS_APP_NODE" --ignore-daemonsets --delete-emptydir-data
Watch:
kubectl get pods -n maint-117740258 -o wide -w
Press Ctrl + C after the new NFS App Pod becomes Running.
Check placement:
kubectl get pods -n maint-117740258 -o wide
Check data:
kubectl exec -n maint-117740258 deployment/app-nfs-117740258 -- wc -l /data/log.txt
kubectl exec -n maint-117740258 deployment/app-nfs-117740258 -- tail -3 /data/log.txt
Say:
The new count is higher than the baseline. The Pod moved, but it mounted the same NFS data.
Tested result:
Before drain: 3013 rows
After drain: 3869 rows
Result: PASS
Uncordon:
kubectl uncordon "$NFS_APP_NODE"
kubectl get nodes
 
Scenario B: hostPath Node
The hostPath node is:
maint-117740258-worker
Prediction:
I expect the old hostPath Pod to be evicted. The replacement Pod should stay Pending because it can only run on the labeled worker, and that worker will be unschedulable.
Cordon:
kubectl cordon maint-117740258-worker
Drain:
kubectl drain maint-117740258-worker --ignore-daemonsets --delete-emptydir-data
Watch:
kubectl get pods -n maint-117740258 -o wide -w
The replacement hostPath Pod should become:
Pending
Press Ctrl + C.
Find the Pod:
HOSTPATH_POD=$(kubectl get pod -n maint-117740258 -l app=app-hostpath-117740258 -o jsonpath='{.items[0].metadata.name}')

echo "$HOSTPATH_POD"
Show the scheduling reason:
kubectl describe pod "$HOSTPATH_POD" -n maint-117740258
Expected Events include:
node(s) were unschedulable
node(s) didn't match Pod's node affinity/selector
Say:
The Pod uses the nodeSelector disk=local-117740258. Only this worker has the label. Because the worker is unschedulable, Kubernetes cannot place the replacement Pod.
Uncordon:
kubectl uncordon maint-117740258-worker
Watch recovery:
kubectl get pods -n maint-117740258 -o wide -w
Press Ctrl + C after the hostPath Pod becomes Running.
Check data:
kubectl exec -n maint-117740258 deployment/app-hostpath-117740258 -- wc -l /data/log.txt
kubectl exec -n maint-117740258 deployment/app-hostpath-117740258 -- tail -3 /data/log.txt
Say:
The Pod returned to the original worker and can read the same node-local hostPath data.
Tested result:
The replacement Pod was Pending while the node was cordoned.
After uncordon, it returned to the original worker.
The old hostPath data was still available.
Result: PASS
 
Scenario C: NFS Server Node
Run this scenario last during practice because it deletes the old NFS data.
Find the NFS Server node:
NFS_SERVER_NODE=$(kubectl get pod -n maint-117740258 -l app=nfs-server-117740258 -o jsonpath='{.items[0].spec.nodeName}')

echo "$NFS_SERVER_NODE"
Record the NFS count:
kubectl exec -n maint-117740258 deployment/app-nfs-117740258 -- wc -l /data/log.txt
Prediction:
I expect the NFS Server Pod to be evicted and recreated on another worker. The NFS App may stop writing while the server is unavailable. Because the server uses emptyDir, the old NFS data will not survive.
Cordon:
kubectl cordon "$NFS_SERVER_NODE"
Drain:
kubectl drain "$NFS_SERVER_NODE" --ignore-daemonsets --delete-emptydir-data
Watch:
kubectl get pods -n maint-117740258 -o wide -w
Possible states:
Terminating
Pending
ContainerCreating
Running
Press Ctrl + C after the new NFS Server Pod becomes Running.
Check NFS Server:
kubectl rollout status deployment/nfs-server-117740258 -n maint-117740258 --timeout=180s
Check Pod placement:
kubectl get pods -n maint-117740258 -o wide
Check the NFS data:
kubectl exec -n maint-117740258 deployment/app-nfs-117740258 -- wc -l /data/log.txt
kubectl exec -n maint-117740258 deployment/app-nfs-117740258 -- tail -5 /data/log.txt
Say:
The PV and PVC are still Bound, but the real files were stored in the NFS Server’s emptyDir. The old emptyDir was deleted with the old server Pod.
Tested result:
Before server drain: more than 3869 rows
After server recreation: 469 rows
The old NFS data was lost.
Result: PASS
Improvement:
To keep the data, I would give the NFS Server persistent storage or use an external highly available NFS system.
Uncordon:
kubectl uncordon "$NFS_SERVER_NODE"
kubectl get nodes
 
8. Drain Without Flags
The instructor may ask what happens without flags.
Try:
kubectl drain <node>
It may refuse because of:
---DaemonSet-managed Pods
---Pods using local emptyDir storage
Correct command:
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
Explanation:
--ignore-daemonsets leaves DaemonSet Pods running.
--delete-emptydir-data allows Pods with temporary emptyDir data to be removed.
 
9. Useful Troubleshooting Commands
Show Pods:
kubectl get pods -n maint-117740258 -o wide
Describe a Pod:
kubectl describe pod <pod-name> -n maint-117740258
Show recent events:
kubectl get events -n maint-117740258 --sort-by=.metadata.creationTimestamp
Show NFS Server logs:
kubectl logs -n maint-117740258 deployment/nfs-server-117740258
Show Deployments:
kubectl get deployments -n maint-117740258
Show PV and PVC:
kubectl get pv
kubectl get pvc -n maint-117740258
 
10. Cordon and Drain
Cordon:
kubectl cordon <node>
Cordon stops new normal Pods from being scheduled on the node. Existing Pods continue running.
Drain:
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
Drain makes the node unschedulable and evicts normal Pods.
Uncordon:
kubectl uncordon <node>
Uncordon allows the node to receive Pods again.
 
11. Tear Down
Only run this after the demo or before a clean bootstrap test:
kind delete cluster --name maint-117740258
