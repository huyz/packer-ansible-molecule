#!/bin/bash
# Script executed by Packer inside the container to install Ansible and other
# dependencies.

#### Preamble (v2023-01-19)

set -x
set -euo pipefail
#shopt -s failglob
# shellcheck disable=SC2317
function trap_err { echo "ERR signal on line $(caller)" >&2; }
trap trap_err ERR
trap exit INT
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

#### Config

# `sudo` for Debian-based images, `wheel` for others.
SUDO_GROUP=sudo
# For regular user
ANSIBLE_USER=ansible
DEPLOY_GROUP=deployer
# For pip as root
# NOTE: this only works for pip 22.1+. So the first `pip install --upgrade pip` will still warn.
export PIP_ROOT_USER_ACTION=ignore
# For apt
export DEBIAN_FRONTEND=noninteractive
APT_OPTIONS=(-y -q --no-install-recommends)

#### Packages

# NOET: the ubuntu:22.04 image contains the following packages already:
# https://github.com/docker-library/repo-info/blob/master/repos/ubuntu/local/22.04.md
# `curl -LsC - https://raw.githubusercontent.com/docker-library/repo-info/master/repos/ubuntu/local/22.04.md | sed -n  's/^###.*`\(.*\)`/\1/p'`


apt-get update


# apt-utils must be installed first to avoid this warning:
# `debconf: delaying package configuration, since apt-utils is not installed`
# per https://github.com/phusion/baseimage-docker/issues/319#issuecomment-899111570
DEBCONF_NOWARNINGS=yes apt-get install "${APT_OPTIONS[@]}" apt-utils

# Install Python dependencies
# https://github.com/geerlingguy/docker-ubuntu2204-ansible/blob/33e2cd83f55b88b0ad85dce17171ef13de3f2912/Dockerfile
apt-get install "${APT_OPTIONS[@]}" \
    build-essential \
    locales \
    libffi-dev \
    libssl-dev \
    libyaml-dev \
    python3-dev \
    python3-setuptools \
    python3-pip \
    python3-yaml \
    software-properties-common

# Install systemd and other system tools
# https://github.com/geerlingguy/docker-ubuntu2204-ansible/blob/33e2cd83f55b88b0ad85dce17171ef13de3f2912/Dockerfile
apt-get install "${APT_OPTIONS[@]}" \
    rsyslog systemd systemd-cron sudo iproute2

# Install for a rootless container
# > Running a rootless container with systemd cgroup driver requires dbus to be running as a user session service.
apt-get install "${APT_OPTIONS[@]}" dbus-user-session

# https://github.com/containerd/nerdctl/blob/main/docs/faq.md#containers-do-not-automatically-start-after-rebooting-the-host

# Install Ansible dependencies
# https://github.com/mesaguy/ansible-molecule/blob/9cc3d465ede61796db3e5af193afe8fa802fa95c/docker/Dockerfile-ubuntu-20.10
apt-get install "${APT_OPTIONS[@]}" \
    curl \
    net-tools \
    openssl \
    python3 \
    python3-apt \
    unzip \
    zip

# Install other Ansible molecule recommendations
# https://github.com/ansible-community/molecule-plugins/blob/bbaf82ee84bebfc41323066ca5eecb2449b975fe/src/molecule_plugins/docker/playbooks/Dockerfile.j2
apt-get install "${APT_OPTIONS[@]}" \
    ca-certificates

#### Users

groupadd -r "$ANSIBLE_USER"
groupadd -r "$DEPLOY_GROUP"
useradd -m -g "$ANSIBLE_USER" "$ANSIBLE_USER"
usermod -aG "$SUDO_GROUP" "$ANSIBLE_USER"
usermod -aG "$DEPLOY_GROUP" "$ANSIBLE_USER"
sed -i "/^%$SUDO_GROUP/s/ALL\$/NOPASSWD:ALL/g" /etc/sudoers

#### Ansible

# Fix potential UTF-8 errors with ansible-test.
locale-gen en_US.UTF-8
# For Ubuntu 18, which uses an older Python 3.6, we need to be explicit about locale
# https://github.com/pypa/pip/issues/10219#issuecomment-887699135
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# Install Ansible via Pip.
# NOTE: as of 2023-01-30, the older pip doesn't have `--root-user-action`
#   (or support for the envvar PIP_ROOT_USER_ACTION)
#   (Upgrading pip doesn't give you the latest; There is an older
#   `--no-warn-when-using-as-a-root-user` but too complicated to figure out
#   which pip version supports that.)
python3 -m pip install --upgrade pip
python3 -m pip install ansible

# Install Ansible inventory file.
mkdir -p /etc/ansible
printf "[local]\nlocalhost ansible_connection=local\n" > /etc/ansible/hosts

#### initctl

chmod +x /tmp/initctl_faker
rm -rf /sbin/initctl
ln -s /tmp/initctl_faker /sbin/initctl

#### systemd

# Tell any systemd units that care about checking if they're running in a container
# (using `ConditionVirtualization=`)
# Per https://systemd.io/CONTAINER_INTERFACE/
export container=docker

sed -i 's/^\($ModLoad imklog\)/#\1/' /etc/rsyslog.conf

# Remove unnecessary getty and udev targets that result in high CPU usage when using
# multiple containers with Molecule (https://github.com/ansible/molecule/issues/1104)
shopt -s nullglob
rm -f /lib/systemd/system/systemd*udev* \
    /lib/systemd/system/getty.target

#### Clean

apt-get clean

shopt -s nullglob
rm -rf /var/lib/apt/lists/* \
    /usr/share/doc \
    /usr/share/man

# https://serverfault.com/q/1053187/82677
rm -f /lib/systemd/system/multi-user.target.wants/* \
    /etc/systemd/system/*.wants/* \
    /lib/systemd/system/local-fs.target.wants/* \
    /lib/systemd/system/sockets.target.wants/*udev* \
    /lib/systemd/system/sockets.target.wants/*initctl* \
    /lib/systemd/system/sysinit.target.wants/systemd-tmpfiles-setup* \
    /lib/systemd/system/systemd-update-utmp*

exit 0
