# Packer Layout

This folder is split into two independent templates:

- `web/` - web AMI with nginx and runtime index render
- `ssm_proxy/` - SSM proxy AMI

Build commands:

```bash
cd web
packer build -var 'build_id=56-01' .
packer build -var 'build_id=56-02' .
```

```bash
cd ../ssm_proxy
packer build .
```
