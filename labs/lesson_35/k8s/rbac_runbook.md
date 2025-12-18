# lab35 RBAC Runbook

## 1. Questions to ask

1. WHO is this? (ServiceAccount / User / Group)
2. WHERE do they work? (namespace(s))
3. WHAT exactly do they need? (resources + verbs)
4. HOW broad? (Role vs ClusterRole)

## 2. Common patterns

### Read-only viewer in namespace

- Subject: ServiceAccount or User
- Role:
  - apiGroups: "", resources: pods,services,verbs: get,list,watch
  - apiGroups: apps, resources: deployments,replicasets,verbs: get,list,watch
- Binding: RoleBinding in that namespace only

### Config-only editor

- Role with CRUD on configmaps/secrets only
- No permissions to touch pods/services/deployments

### Cluster-wide readonly

- ClusterRole with get/list/watch on namespaces,pods,services,deployments
- ClusterRoleBinding to User/Group for ops/support team

## 3. Debugging RBAC

1. kubectl auth can-i <verb> <resource> -n <ns> --as=<subject>
2. kubectl describe role/clusterrole <name>
3. kubectl describe rolebinding/clusterrolebinding <name>
4. Remember:
   - Role is namespaced
   - RoleBinding is namespaced
   - ClusterRoleBinding is cluster-wide
