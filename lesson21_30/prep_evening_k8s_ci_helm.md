# prep_evening_k8s_ci_helm.md

---

# K8s CI Polish: Lint, Kustomize & Helm

**Date:** 2025-12-07

**Topic:** Add **GitHub Actions CI** for your Kubernetes manifests (lint + validate), introduce **Kustomize** overlays for lab27, and scaffold a **Helm chart** for `lab27-web`.

---

## Goals

- Add **CI checks** for k8s YAML: `yamllint` + schema validation (`kubeconform`).
- Introduce **Kustomize** for lab27 manifests (base + dev overlay).
- Scaffold a minimal **Helm chart** for `lab27-web` (Deployment + Service).
- Wire everything into a **GitHub Actions workflow** that runs on every push/PR.

---

## Pocket Cheat

| Thing / File | What it does | Why |
| --- | --- | --- |
| `.yamllint.yml` | YAML style rules | Catch stupid mistakes early |
| `kustomize/base/` | Base k8s manifests | Single source of truth |
| `kustomize/overlays/dev/` | Dev overlay for lab27 | Namespace/labels/replicas tweaks |
| `helm/lab27-web/` | Helm chart | Templateable Deployment/Service |
| `.github/workflows/k8s-ci.yml` | CI workflow | Auto lint/validate on push/PR |
| `yamllint labs/` | YAML lint | Basic hygiene |
| `kubeconform -summary ...` | Schema validation | Catch bad fields/kind/apiVersion |
| `kubectl kustomize ...` | Render Kustomize | See resulting YAML |
| `helm lint` / `helm template` | Chart checks + render | Verify Helm output |

---

## Notes

- Already have **raw manifests** for `lab27` (lesson_27–29).
- Kustomize will **compose** those manifests into a base and environment-specific overlays.
- Helm will give a **parametrizable chart** for `lab27-web`.
- CI will prevent “broke YAML” or “invalid apiVersion” from sneaking into `main`.

---

## Security Checklist

- CI uses only **open-source tools** (yamllint, kubeconform, Helm) with no secrets required.
- Do **not** put any real secrets in Helm `values.yaml` or Kustomize overlays. Keep them generic/dev.
- Workflow runs on GitHub-hosted runners and only reads your public repo content.

---

## Pitfalls

- Forgetting to limit `yamllint` path → it tries to lint everything (including virtualenvs, etc.).
- Kustomize base pointing to wrong relative paths → `kubectl kustomize` fails.
- Helm chart directory name must match `name` in `Chart.yaml` (or be consistent with expectations).
- `kubeconform` or `helm template` failing because of typos in apiVersion or resource types.

---

## Layout

```
labs/prep_evening/
└─ k8s_kustomize/
│  └─ kustomize/
│     │ │ └─ base/
│     │ │    ├─ kind-config.yaml
│     │ │    ├─ kustomization.yaml
│     │ │    ├─ namespace.yaml
│     │ │    ├─ redis-deployment.yaml
│     │ │    ├─ redis-service.yaml
│     │ │    ├─ web-config.yaml
│     │ │    ├─ web-deployment.yaml
│     │ │    ├─ web-ingress.yaml
│     │ │    ├─ web-service.yaml
│     │ │    └─ monitoring/
│     │ │       ├─ kube-state-metrics-deployment.yaml
│     │ │       ├─ kube-state-metrics-rbac.yaml
│     │ │       ├─ monitoring-namespace.yaml
│     │ │       ├─ prometheus-config.yaml
│     │ │       ├─ prometheus-deployment.yaml
│     │ │       └─ prometheus-service.yaml
│     │ └─ compose/
│     │    ├─ docker-compose.yml
│     │    └─ provisioning/
│     │       └─ datasources/
│     │          └─ lab29-prometheus.yml
│     └─ overlays/
│        └─ dev/
│           ├─ kustomization.yaml
│           └─ patch-web-replicas.yaml
└─ k8s_helm/
   └─ helm/
     │ │ └─ base/
     │ │    ├─ kind-config.yaml
     │ │    ├─ namespace.yaml
     │ │    ├─ redis-deployment.yaml
     │ │    ├─ redis-service.yaml
     │ │    └─ monitoring/
     │ │       ├─ kube-state-metrics-deployment.yaml
     │ │       ├─ kube-state-metrics-rbac.yaml
     │ │       ├─ monitoring-namespace.yaml
     │ │       ├─ prometheus-config.yaml
     │ │       ├─ prometheus-deployment.yaml
     │ │       └─ prometheus-service.yaml
     │ └─ compose/
     │    ├─ docker-compose.yml
     │    └─ provisioning/
     │       └─ datasources/
     │          └─ lab29-prometheus.yml
     └─ lab27-web/
        ├─ Chart.yaml
        ├─ values.yaml
        └─ templates/
           ├─ deployment.yaml
           ├─ _helpers.tpl
           ├─ ingress.yaml
           └─ service.yaml

.yamllint.yml
.github/workflows/k8s-ci.yml

```

> Base YAML content can reuse existing lesson_27or28or29 manifests (copy or symlink).
> 

---

## 1) yamllint config

Create `.yamllint.yml` in repo root:

```yaml
extends: default

rules:
  line-length:
    max: 120
    level: warning
  truthy: disable
  document-start: disable

ignore: |
  .git/
  .venv/
  **/__pycache__/
  labs/prep_evening/k8s_helm/helm/lab27-web/templates/

```

Usage:

```bash
yamllint labs/ .github/workflows/*.yml
```

---

## 2) Kustomize: base for lab27

Create directory structure:

```bash
mkdir -p labs/prep_evening/k8s_kustomize/kustomize/base

kind create cluster --name lab27 --config kind-config.yaml
```

Copy existing lab27/lab28 manifests into base (or adjust paths):

- `kind-config.yaml`
- `namespace.yaml`
- `redis-deployment.yaml`
- `redis-service.yaml`
- `web-deployment.yaml`
- `web-service.yaml` & etc.

Now create `labs/prep_evening/k8s_kustomize/kustomize/base/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
 - namespace.yaml
 - redis-deployment.yaml
 - redis-service.yaml
 - web-deployment.yaml
 - web-service.yaml
 - web-config.yaml
 - monitoring/kube-state-metrics-deployment.yaml
 - monitoring/kube-state-metrics-rbac.yaml
 - monitoring/monitoring-namespace.yaml
 - monitoring/prometheus-config.yaml
 - monitoring/prometheus-deployment.yaml
 - monitoring/prometheus-service.yaml

labels:
 - includeSelectors: true
   pairs:
    env: lab
    managed-by: kustomize

```

Test locally:

```bash
cd labs/prep_evening/k8s_ci/kustomize/base
kubectl kustomize .
# or:
# kustomize build .

# build and apply
kubectl apply -k .
```

You should see all lab27 objects, with `namespace: lab27` and `managed-by: kustomize` labels applied.

---

## 3) Kustomize overlay: dev

Create overlay folder:

```bash
mkdir -p labs/prep_evening/k8s_kustomize/kustomize/overlays/dev
```

Patch file to change web replicas in dev:

`labs/prep_evening/k8s_kustomize/kustomize/overlays/dev/patch-web-replicas.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lab27-web
spec:
  replicas: 2

```

Overlay kustomization, we can add namePrefix:

`labs/prep_evening/k8s_kustomize/kustomize/overlays/dev/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# namePrefix: dev-
# namespace: lab27

resources:
  - ../../base

patches:
  - path: patch-web-replicas.yaml
    target:
      kind: Deployment
      name: lab27-web

```

Test render:

```bash
cd labs/prep_evening/k8s_kustomize/kustomize/overlays/dev
kubectl kustomize .
```

Check that:

- Deployment name is `dev-lab27-web` (due to `namePrefix`).
- `spec.replicas` for that Deployment is `2`.

Can even apply it to your cluster:

```bash
kubectl apply -k .
# kubectl apply -k kustomize/overlays/dev

kubectl get svc -n lab27
kubectl get pods -n lab27 # We can see 2 replicas & deployment name with prefix -dev "if we need to change"

# kind delete cluster --name lab27
```

---

## 4) Helm chart: lab27-web

Create chart skeleton:

```bash
mkdir -p labs/prep_evening/k8s_helm/helm

helm create lab27-web
# OR if you don't want the full default skeleton, create minimal structure manually
```

We’ll use a minimal chart. Replace the contents with:

### 4.1 Chart metadata

`labs/prep_evening/k8s_helm/helm/lab27-web/Chart.yaml`:

```yaml
apiVersion: v2
name: lab27-web
description: A simple web+redis frontend (lab27) deployment
type: application
version: 0.1.0
appVersion: "1.1.0"

```

### 4.2 Values

`labs/prep_evening/k8s_helm/helm/lab27-web/values.yaml`:

```yaml
image:
  repository: ghcr.io/vlrrbn/lab25-web-workflows
  tag: sha-8bfd05b
  pullPolicy: IfNotPresent

replicaCount: 1

env:
  LAB_ENV: "lab"
  PORT: "8080"
  REDIS_HOST: "lab27-redis"
  REDIS_PORT: "6379"
  REDIS_DB: "0"

service:
  type: ClusterIP
  port: 8080

ingress:
  enabled: true
  className: nginx
  host: lab27.local
  path: /

labels:
  tier: frontend
  service: labweb
  env: lab

namespaceOverride: ""

resources: {}

```

### 4.3 Deployment template

`labs/prep_evening/k8s_helm/helm/lab27-web/templates/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{include "lab27-web.fullname" .}}
  labels:
    {{include "lab27-web.labels" . | nindent 4}}
spec:
  replicas: {{.Values.replicaCount}}
  selector:
    matchLabels:
      app.kubernetes.io/name: {{include "lab27-web.name" .}}
      app.kubernetes.io/instance: {{.Release.Name}}
  template:
    metadata:
      labels:
        {{include "lab27-web.labels" . | nindent 8}}
    spec:
      containers:
        - name: web
          image: "{{.Values.image.repository}}:{{.Values.image.tag}}"
          imagePullPolicy: {{.Values.image.pullPolicy}}
          env:
            - name: LAB_ENV
              value: {{.Values.env.LAB_ENV | quote}}
            - name: PORT
              value: {{.Values.env.PORT | quote}}
            - name: REDIS_HOST
              value: {{.Values.env.REDIS_HOST | quote}}
            - name: REDIS_PORT
              value: {{.Values.env.REDIS_PORT | quote}}
            - name: REDIS_DB
              value: {{.Values.env.REDIS_DB | quote}}
          ports:
            - containerPort: 8080
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 10

```

### 4.4 Service template

`labs/prep_evening/k8s_helm/helm/lab27-web/templates/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{include "lab27-web.fullname" .}}
  labels:
    {{include "lab27-web.labels" . | nindent 4}}
spec:
  type: {{.Values.service.type}}
  ports:
    - port: {{.Values.service.port}}
      targetPort: 8080
      protocol: TCP
      name: http
  selector:
    app.kubernetes.io/name: {{include "lab27-web.name" .}}
    app.kubernetes.io/instance: {{.Release.Name}}

```

Reuse the helper template file `templates/_helpers.tpl` from the default helm skeleton to get `fullname`, `name`, `labels` helpers.

`labs/prep_evening/k8s_helm/helm/lab27-web/templates/ingress.yaml`:

```bash
{{if .Values.ingress.enabled}}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{include "lab27-web.fullname" .}}
  labels:
    {{include "lab27-web.labels" . | nindent 4}}
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: {{.Values.ingress.className}}
  rules:
    - host: {{.Values.ingress.host}}
      http:
        paths:
          - path: {{.Values.ingress.path}}
            pathType: Prefix
            backend:
              service:
                name: {{include "lab27-web.fullname" .}}
                port:
                  number: {{.Values.service.port}}
{{end}}

```

Test Helm locally:

```bash
cd labs/prep_evening/k8s_helm/helm/lab27-web

helm lint .
helm template lab27-web . | head
```

Deploy into kind:

```bash
helm install lab27-web ./ --namespace lab27 --create-namespace
helm list -n lab27
kubectl get deploy,svc -n lab27
```

---

## 5) k8s CI workflow (GitHub Actions)

Create `.github/workflows/k8s-ci.yml`:

```yaml
name: k8s-ci

on:
  push:
    branches: ["main"]
  pull_request:
    branches: ["main"]
  workflow_dispatch: {}

jobs:
  k8s-lint-validate:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repo
        uses: actions/checkout@v4

      - name: Set up Python for yamllint
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - name: Install yamllint
        run: pip install yamllint

      - name: Run yamllint on k8s and workflows
        run: |
          yamllint labs/lesson_27 labs/lesson_28 labs/lesson_29 labs/prep_evening .github/workflows

      - name: Install kubeconform
        run: |
          curl -L https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-amd64.tar.gz \
            | tar xz
          sudo mv kubeconform /usr/local/bin/

      - name: Validate raw k8s manifests with kubeconform
        run: |
          kubeconform -summary -ignore-missing-schemas -strict \
            labs/lesson_27/k8s/*.yaml \
            labs/lesson_28/k8s/*.yaml \
            labs/lesson_29/k8s/monitoring/*.yaml

      - name: Validate kustomize dev overlay
        run: |
          cd labs/prep_evening/k8s_kustomize/kustomize/overlays/dev
          kubectl kustomize . | kubeconform -summary -ignore-missing-schemas -strict -

      - name: Set up Helm
        uses: azure/setup-helm@v4
        with:
          version: v3.15.0

      - name: Helm lint lab27-web chart
        run: |
          cd labs/prep_evening/k8s_helm/helm/lab27-web
          helm lint .

      - name: Validate Helm rendered manifests
        run: |
          cd labs/prep_evening/k8s_helm/helm/lab27-web
          helm template lab27-web . | kubeconform -summary -ignore-missing-schemas -strict -

```

> This workflow:
> 
> - Lints all relevant YAML.
> - Validates raw manifests for lesson_27–29.
> - Validates Kustomize overlay output.
> - Lints Helm chart and validates its rendered manifests.

---

## Core

- [ ]  `.yamllint.yml` in repo root, `yamllint` runs clean on k8s dirs.
- [ ]  `kustomize/base` renders successfully with `kubectl kustomize`.
- [ ]  `kustomize/overlays/dev` renders with `replicas: 2` for web.
- [ ]  Helm chart `lab27-web` passes `helm lint` and `helm template`.
- [ ]  `k8s-ci` workflow runs green on GitHub for a test push.
- [ ]  Apply Kustomize dev overlay into kind cluster and verify `dev-lab27-web` behavior.
- [ ]  Install Helm release `lab27-web` into `lab27` namespace and test app via existing Ingress.
- [ ]  Tighten yamllint rules (e.g., require document-start for k8s files) and fix warnings.

---

## Acceptance Criteria

- [ ]  Repo has **basic YAML linting** and **k8s schema validation** automated in CI.
- [ ]  lab27 manifests can be rendered and patched via **Kustomize** (base + dev overlay).
- [ ]  `lab27-web` has a working **Helm chart**, validated by CI.
- [ ]  Know how to run all the same checks locally before pushing.

---

## Summary

- Moved k8s manifests from “lesson_27-29” to **CI-checked assets**.
- Introduced **Kustomize** to manage base + overlays for lab27.
- Created a minimal but real **Helm chart** for lab27-web that can be linted, templated, and deployed.
- Wired it all up in **GitHub Actions**, so broken YAML or invalid k8s manifests get caught before merging.

---

## Artifacts

- `prep_evening_k8s_ci_helm_EN.md`
- `.yamllint.yml`
- `.github/workflows/k8s-ci.yml`
- `labs/prep_evening/k8s_kustomize/kustomize/{base,overlays/dev}`
- `labs/prep_evening/k8s_helm/helm/lab27-web/{Chart.yaml,values.yaml,templates/*.yaml}`