# Azure test users for Argo CD RBAC (this environment)

Created with Azure CLI against tenant `939f575e-0369-4929-a7b3-9c18af593c11`.

| Login (UPN) | Group | Argo CD role |
|-------------|-------|----------------|
| `user2@workshivamanandgmail.onmicrosoft.com` | `sg-argocd-platform-admins` | `platform-admin` |
| `user3@workshivamanandgmail.onmicrosoft.com` | `sg-argocd-app-operators` | `app-operator` |

**Group Object IDs** (also in `policy.csv`):

- `sg-argocd-platform-admins`: `d8a37339-10b1-40fd-a32d-184838519df2`
- `sg-argocd-app-operators`: `ce68bf36-8010-4af0-b0ed-f69ce32568a4`

Passwords were set at user creation time and are **not** stored in this repo. Reset if needed:

```bash
az ad user update --id user2@workshivamanandgmail.onmicrosoft.com --password '<new-strong-password>'
```

## App registration

- Client ID: `bdf1cc2b-2d99-42a4-92ce-7b950257c64f`
- `groupMembershipClaims`: `SecurityGroup` (emits `groups` in token)
- Redirect URI: `https://localhost:8080/auth/callback`

## CLI verification (optional)

```bash
argocd admin settings rbac can --namespace argocd --kube-context kind-shivam-playgroung-1 \
  --default-role role:viewer d8a37339-10b1-40fd-a32d-184838519df2 get clusters 'https://kubernetes.default.svc'
# Expected: Yes

argocd admin settings rbac can --namespace argocd --kube-context kind-shivam-playgroung-1 \
  --default-role role:viewer ce68bf36-8010-4af0-b0ed-f69ce32568a4 get clusters 'https://kubernetes.default.svc'
# Expected: No
```

Use **plain group GUID** as the subject (matches the `groups` claim from Entra).
