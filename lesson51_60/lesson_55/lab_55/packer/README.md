# Packer Layout

This folder is split into two independent templates:

- `web/` - web AMI with nginx and runtime index render
- `ssm_proxy/` - SSM proxy AMI

Build commands:

```bash
cd web
packer build -var 'build_id=55-01' -var 'ami_version=blue' .
packer build -var 'build_id=55-02' -var 'ami_version=green' .
```

```bash
cd ../ssm_proxy
packer build .
```
