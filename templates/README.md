# Templates Library

This folder contains reusable YAML templates for quick lab setup.
Copy a template, replace placeholders, then apply.

## Placeholders

- APP_NAME
- APP_NAMESPACE
- APP_IMAGE
- APP_PORT
- APP_HOST

## Usage

1) Copy a file into your lab folder.
2) Replace placeholders with real values.
3) Validate and apply:

```bash
kubectl apply --dry-run=client -f <file>
kubectl apply -f <file>
```

## Notes

- Keep Secrets out of git. Use `stringData` for local tests only.
- Match `metadata.labels` with `spec.selector.matchLabels`.
- Update `namespace` consistently across resources.
