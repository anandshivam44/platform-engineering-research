# ArgoCD Deployment Runbook

## Overview

This runbook covers deploying, accessing, upgrading, and troubleshooting ArgoCD on a kind cluster using Helmfile.

| Property       | Value                                  |
|----------------|----------------------------------------|
| ArgoCD Version | v3.3.2                                 |
| Helm Chart     | `argo/argo-cd` v9.4.5                  |
| Cluster        | `kind-shivam-playgroung-1`             |
| Namespace      | `argocd`                               |
| Deployment     | Helmfile (`argocd-setup/helmfile.yaml`) |

---

## Prerequisites

| Tool       | Install Command                   | Purpose                     |
|------------|-----------------------------------|-----------------------------|
| `kind`     | `brew install kind`               | Local Kubernetes cluster    |
| `kubectl`  | `brew install kubernetes-cli`     | Cluster interaction         |
| `helm`     | `brew install helm`               | Kubernetes package manager  |
| `helmfile` | `brew install helmfile`           | Declarative Helm releases   |

---

## Repository Structure

```
argocd-research/
├── argocd-setup/
│   ├── helmfile.yaml           # Helm release declaration
│   └── values/
│       └── argocd.yaml         # ArgoCD chart values (resources, service, config)
├── clusters/
│   └── kind-shivam-playgroung-1/
│       ├── app-of-apps.yaml    # ArgoCD App-of-Apps Application manifest
│       └── apps/
│           └── nginx.yaml      # Example managed application
└── RUNBOOK.md
```

---

## 1. Create the Kind Cluster

```bash
kind create cluster --name shivam-playgroung-1
```

Verify the cluster is up:

```bash
kubectl cluster-info --context kind-shivam-playgroung-1
kubectl get nodes --context kind-shivam-playgroung-1
```

---

## 2. Deploy ArgoCD via Helmfile

```bash
cd argocd-setup
helmfile sync --kube-context kind-shivam-playgroung-1
```

Helmfile will:
1. Add the `argo` Helm repository (`https://argoproj.github.io/argo-helm`)
2. Create the `argocd` namespace automatically
3. Install the `argo/argo-cd` chart with values from `values/argocd.yaml`

Verify all pods are running:

```bash
kubectl get pods -n argocd --context kind-shivam-playgroung-1
```

Expected output — all 7 pods in `Running` state:

```
argocd-application-controller-0
argocd-applicationset-controller-*
argocd-dex-server-*
argocd-notifications-controller-*
argocd-redis-*
argocd-repo-server-*
argocd-server-*
```

---

## 3. Access the ArgoCD UI

The `argocd-server` service is `ClusterIP`. Use port-forwarding to access the UI locally:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 \
  --context kind-shivam-playgroung-1
```

Open in browser: **https://localhost:8080** (accept the self-signed certificate warning)

### Retrieve the Initial Admin Password

```bash
kubectl -n argocd --context kind-shivam-playgroung-1 \
  get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

| Field    | Value                                    |
|----------|------------------------------------------|
| Username | `admin`                                  |
| Password | _(output of the command above)_          |

> **Security note:** Delete the initial secret after saving the password:
> ```bash
> kubectl delete secret argocd-initial-admin-secret -n argocd \
>   --context kind-shivam-playgroung-1
> ```

---

## 4. Component Resource Limits

Resources are defined in `argocd-setup/values/argocd.yaml`.

| Component              | CPU Request | CPU Limit | Memory Request | Memory Limit |
|------------------------|-------------|-----------|----------------|--------------|
| `controller`           | 100m        | 500m      | 128Mi          | 512Mi        |
| `server`               | 50m         | 200m      | 64Mi           | 256Mi        |
| `repoServer`           | 50m         | 200m      | 64Mi           | 256Mi        |
| `applicationSet`       | 25m         | 100m      | 32Mi           | 128Mi        |
| `notifications`        | 25m         | 100m      | 32Mi           | 128Mi        |
| `dex`                  | 10m         | 50m       | 32Mi           | 64Mi         |
| `redis`                | 25m         | 100m      | 32Mi           | 128Mi        |

---

## 5. Upgrade ArgoCD

To change chart version or update values, edit `argocd-setup/helmfile.yaml` or `argocd-setup/values/argocd.yaml`, then run:

```bash
cd argocd-setup
helmfile sync --kube-context kind-shivam-playgroung-1
```

To pin a specific chart version, add `version` to `helmfile.yaml`:

```yaml
releases:
  - name: argocd
    chart: argo/argo-cd
    version: "9.4.5"   # pin version here
```

---

## 6. Apply the App-of-Apps (GitOps Bootstrap)

Once ArgoCD is running, bootstrap GitOps by applying the App-of-Apps manifest:

```bash
kubectl apply -f clusters/kind-shivam-playgroung-1/app-of-apps.yaml \
  --context kind-shivam-playgroung-1
```

This creates an ArgoCD `Application` that watches:
- **Repo:** `https://github.com/anandshivam44/platform-engineering-research.git`
- **Branch:** `main`
- **Path:** `clusters/kind-shivam-playgroung-1/apps`

ArgoCD will automatically sync and deploy all application manifests in that path with `prune: true` and `selfHeal: true`.

---

## 7. Teardown

### Uninstall ArgoCD only

```bash
cd argocd-setup
helmfile destroy --kube-context kind-shivam-playgroung-1
```

### Delete the entire kind cluster

```bash
kind delete cluster --name shivam-playgroung-1
```

---

## 8. Troubleshooting

### Pods not starting

```bash
kubectl describe pod <pod-name> -n argocd --context kind-shivam-playgroung-1
kubectl logs <pod-name> -n argocd --context kind-shivam-playgroung-1
```

### Port-forward disconnects

Re-run the port-forward command. Consider running it in a dedicated terminal or using a tool like `kubectl-relay`.

### ArgoCD app stuck in `Progressing`

```bash
# Force a sync
argocd app sync <app-name>

# Or via kubectl
kubectl patch application <app-name> -n argocd \
  --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}'
```

### Check ArgoCD server logs

```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server \
  --context kind-shivam-playgroung-1 --tail=100
```

### Check controller logs

```bash
kubectl logs -n argocd argocd-application-controller-0 \
  --context kind-shivam-playgroung-1 --tail=100
```

### helmfile sync fails

```bash
# Update the Helm repo cache
helm repo update

# Re-run sync with debug output
helmfile sync --kube-context kind-shivam-playgroung-1 --debug
```
