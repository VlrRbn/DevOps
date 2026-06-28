# Packer Layout

This folder is split into two independent templates:

- `web/` - web AMI with nginx and runtime index render
- `ssm_proxy/` - SSM proxy AMI

Build commands:

```bash
cd web
packer build -var 'build_id=75-01' .
packer build -var 'build_id=75-02' .
packer build -var 'build_id=75-bad' .
```

```bash
cd ../ssm_proxy
packer build -var 'build_id=75-proxy' .
packer build -var 'build_id=75-wrk' .
```
