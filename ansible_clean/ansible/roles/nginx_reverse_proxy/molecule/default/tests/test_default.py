def test_nginx_pkg(host):
    pkg = host.package("nginx")
    assert pkg.is_installed

def test_nginx_service(host):
    s = host.service("nginx")
    assert s.is_running
    assert s.is_enabled

def test_port_80_listening(host):
    sock = host.socket("tcp://0.0.0.0:80")
    assert sock.is_listening

def test_health_endpoint(host):
    cmd = host.run("curl -sI http://127.0.0.1/health")
    assert cmd.rc == 0
    assert "200" in cmd.stdout

def test_nginx_syntax_ok(host):
    cmd = host.run("nginx -t")
    assert cmd.rc == 0
