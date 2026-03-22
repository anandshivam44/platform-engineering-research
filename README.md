# k8-platform-engineering-research

Kubernetes / Argo CD platform engineering experiments (multi-cluster, app-of-apps, OIDC).

Full procedures: **[RUNBOOK.md](RUNBOOK.md)** · **Azure CLI (Entra) end-to-end:** [playbooks/azure-cli-entra-argocd-e2e.md](playbooks/azure-cli-entra-argocd-e2e.md)

---

## Azure OIDC — create the client secret in the cluster

`argocd-cm` references the secret with `clientSecret: $argocd-oidc-azure:clientSecret`. Create the Secret in the `argocd` namespace, then label it so Argo CD substitutes the value.

**Context:** `kind-shivam-playgroung-1` (adjust `--context` if needed.)

```bash
# 1) Create Secret (replace with your Entra app client secret; do not commit real values)
kubectl --context kind-shivam-playgroung-1 -n argocd create secret generic argocd-oidc-azure \
  --from-literal=clientSecret='YOUR_AZURE_CLIENT_SECRET' \
  --dry-run=client -o yaml | kubectl --context kind-shivam-playgroung-1 apply -f -

# 2) Required label — without this, Argo CD logs "key does not exist in secret"
kubectl --context kind-shivam-playgroung-1 -n argocd label secret argocd-oidc-azure \
  app.kubernetes.io/part-of=argocd --overwrite

# 3) Reload server so OIDC picks up config (if you changed CM or secret)
kubectl --context kind-shivam-playgroung-1 -n argocd rollout restart deployment argocd-server
```

In **Microsoft Entra ID**, register redirect URI **`https://localhost:8080/auth/callback`** (must match `data.url` in `argocd-cm` + `/auth/callback`).

See also: [clusters/kind-shivam-playgroung-1/argocd-applications/cluster-resources/argocd-cm.yaml](clusters/kind-shivam-playgroung-1/argocd-applications/cluster-resources/argocd-cm.yaml).

**Azure RBAC test users / groups:** [playbooks/azure-rbac-test-users.md](playbooks/azure-rbac-test-users.md)
