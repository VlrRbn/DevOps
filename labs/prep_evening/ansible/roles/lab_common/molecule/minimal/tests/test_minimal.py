import pytest


def test_packages_installed_minimal(host):
    pkgs = ["curl", "vim", "htop"]
    for name in pkgs:
        pkg = host.package(name)
        assert pkg.is_installed, f"Package {name} should be installed in minimal"


def test_lab_user_not_exists_minimal(host):
    user = host.user("labops_user")
    assert not user.exists


def test_sudoers_not_exists_minimal(host):
    sudoers = host.file("/etc/sudoers.d/labops_group")
    assert not sudoers.exists


def test_motd_not_modified_by_role_minimal(host):
    motd = host.file("/etc/motd")
    if not motd.exists:
        return

    content = motd.content_string
    assert "Managed by role: lab_common" not in content
    assert "labops_user" not in content
