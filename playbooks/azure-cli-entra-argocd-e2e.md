# End-to-end: Azure CLI for Entra ID + Argo CD OIDC

This guide uses **Azure CLI** (`az`) only to create an **app registration** (OAuth/OIDC client), **security groups**, **cloud users**, **group membership**, and token settings needed for **Argo CD** sign-in and **RBAC** (via the `groups` claim).

**Prerequisites**

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) installed.
- Entra ID rights: e.g. **Application Administrator**, **User Administrator**, **Groups Administrator** (or **Global Administrator**).
- If the tenant has **no Azure subscription**, sign in with tenant-only access:

```bash
az login --allow-no-subscriptions --tenant "<TENANT_ID>"
```

Replace `<TENANT_ID>` with **Directory (tenant) ID** from Entra ID **Overview**.

---

## 1) Variables (edit for your environment)

```bash
# Entra tenant
export TENANT_ID="<your-tenant-id>"

# DNS domain for cloud users (Entra → Users → domain like contoso.onmicrosoft.com)
export USER_DOMAIN="contoso.onmicrosoft.com"

# Argo CD external URL (must match browser + argocd-cm `url`, HTTPS if you use TLS on port-forward)
export ARGOCD_PUBLIC_URL="https://localhost:8080"

# OAuth redirect path Argo CD uses (do not change unless you customize Argo CD)
export REDIRECT_URI="${ARGOCD_PUBLIC_URL}/auth/callback"

# App registration display name
export APP_NAME="argocd-oidc"

# Group names
export GROUP_ADMINS="sg-argocd-platform-admins"
export GROUP_OPS="sg-argocd-app-operators"

# Test users (UPN prefix only; full UPN = prefix@USER_DOMAIN)
export USER_ADMIN_TEST="argocd-admin-test"
export USER_OPS_TEST="argocd-operator-test"
```

---

## 2) App registration (create + redirect URI + client secret + groups in token)

### 2.1 Create the application

Single-tenant (typical for corporate):

```bash
export APP_ID=$(az ad app create \
  --display-name "$APP_NAME" \
  --sign-in-audience AzureADMyOrg \
  --query appId -o tsv)

export APP_OBJECT_ID=$(az ad app show --id "$APP_ID" --query id -o tsv)

echo "Client ID (appId):     $APP_ID"
echo "Object ID (app reg):   $APP_OBJECT_ID"
```

### 2.2 Web redirect URI (authorization code flow)

Must match **exactly** what Argo CD sends (scheme + host + port + path):

```bash
az ad app update --id "$APP_ID" \
  --web-redirect-uris "$REDIRECT_URI"
```

### 2.3 Emit security groups in tokens (for Argo CD `groupsClaim: groups`)

```bash
az ad app update --id "$APP_ID" --set groupMembershipClaims=SecurityGroup
```

If users have many groups, Microsoft may use **group overage** (fewer IDs in the token); keep test groups small.

### 2.4 Create a client secret (confidential client)

```bash
export CLIENT_SECRET=$(az ad app credential reset \
  --id "$APP_ID" \
  --display-name "argocd-k8s" \
  --years 2 \
  --query password -o tsv)

echo "Save this client secret somewhere safe (password manager). It is shown once:"
echo "$CLIENT_SECRET"
```

**Issuer for OIDC v2.0** (use in `argocd-cm` / Helm `oidc.config`):

```text
https://login.microsoftonline.com/${TENANT_ID}/v2.0
```

### 2.5 (Optional) Enterprise application / service principal

An enterprise app is usually created automatically. To ensure a service principal exists:

```bash
az ad sp show --id "$APP_ID" >/dev/null 2>&1 || az ad sp create --id "$APP_ID"
```

---

## 3) Security groups

```bash
# mailNickname must be unique in the tenant (no spaces; often shortened)
az ad group create --display-name "$GROUP_ADMINS" --mail-nickname "sgargocdplatformadmins"
az ad group create --display-name "$GROUP_OPS"   --mail-nickname "sgargocdappoperators"

export GROUP_ADMINS_ID=$(az ad group show --group "$GROUP_ADMINS" --query id -o tsv)
export GROUP_OPS_ID=$(az ad group show --group "$GROUP_OPS" --query id -o tsv)

echo "Admin group Object ID: $GROUP_ADMINS_ID"
echo "Ops group Object ID:   $GROUP_OPS_ID"
```

Use these **Object IDs** in Argo CD `policy.csv` lines: `g, <ObjectId>, role:...`.

---

## 4) Cloud users + group membership

Passwords must satisfy your directory’s **password policy** (length, complexity). Do **not** commit real passwords.

```bash
ADMIN_UPN="${USER_ADMIN_TEST}@${USER_DOMAIN}"
OPS_UPN="${USER_OPS_TEST}@${USER_DOMAIN}"

# Strong passwords — replace with your own
ADMIN_PW='<StrongPasswordForAdminUser!>'
OPS_PW='<StrongPasswordForOpsUser!>'

az ad user create --display-name "Argo CD admin test" --user-principal-name "$ADMIN_UPN" --password "$ADMIN_PW"
az ad user create --display-name "Argo CD ops test"   --user-principal-name "$OPS_UPN"   --password "$OPS_PW"

ADMIN_OID=$(az ad user show --id "$ADMIN_UPN" --query id -o tsv)
OPS_OID=$(az ad user show --id "$OPS_UPN" --query id -o tsv)

az ad group member add --group "$GROUP_ADMINS_ID" --member-id "$ADMIN_OID"
az ad group member add --group "$GROUP_OPS_ID"   --member-id "$OPS_OID"
```

Reset password later:

```bash
az ad user update --id "$ADMIN_UPN" --password '<new-password>'
```

---

## 5) Verify app + groups (read-only)

```bash
# App
az ad app show --id "$APP_ID" --query "{appId:appId, groupMembershipClaims:groupMembershipClaims, web:web}" -o json

# Redirect URIs
az ad app show --id "$APP_ID" --query "web.redirectUris" -o tsv

# Group members
az ad group member list --group "$GROUP_ADMINS_ID" --query "[].userPrincipalName" -o tsv
az ad group member list --group "$GROUP_OPS_ID"   --query "[].userPrincipalName" -o tsv
```

---

## 6) Wire Argo CD (Kubernetes + Git values)

### 6.1 `argocd-cm` OIDC snippet (`oidc.config`)

Use **v2.0** issuer, **client ID**, and reference the **client secret** from a Kubernetes Secret (see [README](../README.md)):

```yaml
url: https://localhost:8080   # must match ARGOCD_PUBLIC_URL
oidc.config: |
  name: Azure
  issuer: https://login.microsoftonline.com/<TENANT_ID>/v2.0
  clientID: <APP_ID>
  clientSecret: $argocd-oidc-azure:clientSecret
  requestedScopes:
    - openid
    - profile
    - email
  groupsClaim: groups
```

### 6.2 Kubernetes Secret for client secret

```bash
kubectl -n argocd create secret generic argocd-oidc-azure \
  --from-literal=clientSecret="$CLIENT_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n argocd label secret argocd-oidc-azure app.kubernetes.io/part-of=argocd --overwrite
```

### 6.3 RBAC (`argocd-rbac-cm` / Helm `configs.rbac.policy.csv`)

Map **group Object IDs** (not display names):

```csv
g, <GROUP_ADMINS_ID>, role:platform-admin
g, <GROUP_OPS_ID>, role:app-operator
```

Restart after CM changes:

```bash
kubectl -n argocd rollout restart deployment argocd-server
```

---

## 7) End-to-end checklist

| Step | Azure CLI / action |
|------|-------------------|
| Login | `az login --allow-no-subscriptions --tenant $TENANT_ID` |
| App | `az ad app create` → capture `appId` |
| Redirect | `az ad app update --web-redirect-uris $REDIRECT_URI` |
| Groups in token | `az ad app update --set groupMembershipClaims=SecurityGroup` |
| Secret | `az ad app credential reset --id $APP_ID` |
| Groups | `az ad group create` ×2, note Object IDs |
| Users | `az ad user create` ×2 |
| Membership | `az ad group member add` |
| K8s | Secret + `argocd-cm` + `argocd-rbac-cm` + restart `argocd-server` |

---

## 8) Cleanup (optional)

```bash
# Remove users (destructive)
# az ad user delete --id "$ADMIN_UPN"
# az ad user delete --id "$OPS_UPN"

# Remove groups
# az ad group delete --group "$GROUP_ADMINS_ID"
# az ad group delete --group "$GROUP_OPS_ID"

# Remove app registration (destructive)
# az ad app delete --id "$APP_ID"
```

---

## 9) References

- [Azure CLI – `az ad app`](https://learn.microsoft.com/cli/azure/ad/app)
- [Azure CLI – `az ad group`](https://learn.microsoft.com/cli/azure/ad/group)
- [Azure CLI – `az ad user`](https://learn.microsoft.com/cli/azure/ad/user)
- [Argo CD – OIDC](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/)
- [Argo CD – RBAC](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/)

Related repo docs: [README](../README.md), [RUNBOOK](../RUNBOOK.md), [azure-rbac-test-users.md](azure-rbac-test-users.md).
