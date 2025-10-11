# tests/test_default.py
import os
import testinfra.utils.ansible_runner as ar

inventory = os.environ.get("MOLECULE_INVENTORY_FILE")
if not inventory:
    raise RuntimeError("MOLECULE_INVENTORY_FILE is not set — run via `molecule verify`.")

testinfra_hosts = ar.AnsibleRunner(inventory).get_hosts("instance")

def test_nginx_binary_present(host):
    assert host.exists("nginx")

def test_nginx_master_running(host):
    procs = host.process.filter(comm="nginx")
    assert len(procs) > 0

def test_default_site_file_exists_and_nonempty(host):
    f = host.file("/etc/nginx/sites-available/default")
    assert f.exists
    assert f.size > 0

def test_nginx_config_syntax_ok(host):
    cmd = host.run("nginx -t")
    assert cmd.rc == 0
