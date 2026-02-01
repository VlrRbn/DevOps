# Helm Chart (Single Preset)

Minimal Helm chart for labs with optional templates included.

## Included (core)
- Deployment
- Service
- Helpers

## Optional templates (already in `templates/`)
- `ingress.yaml`
- `configmap.yaml`
- `serviceaccount.yaml`

Enable optional templates by setting values in `values.yaml` or merging
`values-snippets.yaml`.

## Usage
```bash
cp -r templates/helm my-app
cd my-app
helm lint .
helm template my-app .
helm install my-app .
```

## Notes
- Keep secrets out of git; use `values.yaml` only for non-sensitive data.
- Optional templates are guarded by `enabled` flags in values.
