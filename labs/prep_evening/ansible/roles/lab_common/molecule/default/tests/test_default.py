import pytest


def test_packages_installed(host):
    pkgs = ["curl", "vim", "htop"]
    for name in pkgs:
        pkg = host.package(name)
        assert pkg.is_installed, f"Package {name} should be installed"


def test_lab_user_exists(host):
    user = host.user("labops_user")
    assert user.exists
    assert user.group == "labops_group"
    assert "/home/labops_user" in user.home


def test_motd_content(host):
    motd = host.file("/etc/motd")
    assert motd.exists
    assert motd.user == "root"
    assert motd.group == "root"
    assert motd.mode & 0o644 == 0o644

    content = motd.content_string
    assert "Welcome to Molecule lab host" in content
    assert "lab_common" in content
    assert "labops_user" in content

def test_sudoers_for_labops_group(host):
    sudoers = host.file("/etc/sudoers.d/labops_group")
    assert sudoers.exists
    assert sudoers.user == "root"
    assert sudoers.group == "root"
    assert sudoers.mode & 0o440 == 0o440

    content = sudoers.content_string
    assert "%labops_group ALL=(ALL) NOPASSWD: ALL" in content