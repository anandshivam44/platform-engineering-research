# ArgoCD Multi-Cluster Runbook

ArgoCD via Helmfile. Management cluster: `kind-shivam-playgroung-1` (dev). Remote cluster: `kind-shivam-playground-2` (prod). Namespace: `argocd`.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full design.

**Prerequisites:** `kind`, `kubectl`, `helm`, `helmfile`, `argocd` CLI

```bash
brew install kind kubectl helm helmfile argocd
```

---

## 1. Create clusters

```bash
kind create cluster --name shivam-playgroung-1
kind create cluster --name shivam-playground-2
```

Verify:

```bash
kubectl get nodes --context kind-shivam-playgroung-1
kubectl get nodes --context kind-shivam-playground-2
```

## 2. Deploy ArgoCD on the management cluster (dev)

```bash
cd setup-argocd
helmfile sync --kube-context kind-shivam-playgroung-1
kubectl get pods -n argocd --context kind-shivam-playgroung-1
```

## 3. Access ArgoCD UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 --context kind-shivam-playgroung-1
```

Open **https://localhost:8080**. Username: `admin`. Password:

```bash
kubectl -n argocd --context kind-shivam-playgroung-1 get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

## 4. Register remote cluster (prod) in ArgoCD

Log in to ArgoCD CLI:

```bash
argocd login localhost:8080 --insecure --username admin --password <password>
```

### Register prod cluster

```bash
argocd cluster add kind-shivam-playground-2 --name kind-shivam-playground-2 -y
```

Then patch the cluster secret with the Docker-internal IP (kind clusters need this):

```bash
PROD_IP=$(docker inspect shivam-playground-2-control-plane --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')

TOKEN=$(kubectl --context kind-shivam-playground-2 -n kube-system get secret argocd-manager-long-lived-token -o jsonpath='{.data.token}' | base64 -d)
CA_DATA=$(kubectl --context kind-shivam-playground-2 -n kube-system get secret argocd-manager-long-lived-token -o jsonpath='{.data.ca\.crt}' | base64 -d | base64)
CONFIG_JSON="{\"bearerToken\": \"$TOKEN\", \"tlsClientConfig\": {\"insecure\": false, \"caData\": \"$CA_DATA\"}}"

kubectl --context kind-shivam-playgroung-1 -n argocd create secret generic cluster-kind-shivam-playground-2 \
  --from-literal=name=kind-shivam-playground-2 \
  --from-literal=server=https://${PROD_IP}:6443 \
  --from-literal=config="$CONFIG_JSON"
kubectl --context kind-shivam-playgroung-1 -n argocd label secret cluster-kind-shivam-playground-2 argocd.argoproj.io/secret-type=cluster
```

Verify all clusters:

```bash
argocd cluster list
```

## 5. Bootstrap — apply root app-of-apps

All commands run against the management cluster where ArgoCD lives.

Apply the **root** Argo CD Application; it deploys both cluster app-of-apps (`playground-1.app-of-apps` and `playground-2.app-of-apps`):

```bash
kubectl apply -f clusters/argocd-root-app.yaml --context kind-shivam-playgroung-1
```

### (Alternative) Apply each cluster app-of-apps manually

```bash
kubectl apply -f clusters/kind-shivam-playgroung-1/argocd-app-of-apps.yaml --context kind-shivam-playgroung-1
kubectl apply -f clusters/kind-shivam-playground-2/argocd-app-of-apps.yaml --context kind-shivam-playgroung-1
```

### (Alternative) Use ApplicationSet instead of per-cluster app-of-apps

```bash
kubectl apply -f applicationsets/nginx.yaml --context kind-shivam-playgroung-1
```

## 6. Verify deployments

```bash
kubectl get pods -n nginx --context kind-shivam-playgroung-1
kubectl get pods -n nginx --context kind-shivam-playground-2
```

Check chart versions:

```bash
argocd app list
```

## 7. Add a new application

1. Create `base/<app>-values.yaml` with shared defaults
2. For each cluster, create `clusters/<env>/<cluster>/argocd-apps/<app>.yaml`
3. Commit and push — the app-of-apps picks it up automatically

## 8. Teardown

```bash
# Remove root app (manages both app-of-apps), then child apps if needed
argocd app delete root-app-of-apps --cascade -y
argocd app delete playground-2.app-of-apps --cascade -y
argocd app delete playground-1.app-of-apps --cascade -y

kubectl --context kind-shivam-playgroung-1 -n argocd delete secret cluster-kind-shivam-playground-2

cd setup-argocd && helmfile destroy --kube-context kind-shivam-playgroung-1

kind delete cluster --name shivam-playground-2
kind delete cluster --name shivam-playgroung-1
```

## 9. Troubleshooting

```bash
# Pod status and logs
kubectl describe pod <pod> -n argocd --context kind-shivam-playgroung-1
kubectl logs <pod> -n argocd --context kind-shivam-playgroung-1

# Force sync
argocd app sync <app-name>

# ArgoCD server and controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --context kind-shivam-playgroung-1 --tail=100
kubectl logs -n argocd argocd-application-controller-0 --context kind-shivam-playgroung-1 --tail=100

# Helmfile debug
helm repo update && helmfile sync --kube-context kind-shivam-playgroung-1 --debug
```
