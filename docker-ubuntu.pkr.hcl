//packer {
//  required_plugins {
//    docker = {
//      version = ">= 1.0.9"
//      source  = "github.com/huyz/docker"
//    }
//  }
//}

variable "docker_repo_base" {
  type = string
}
variable "docker_username" {
  type = string
}
variable "docker_password" {
  type      = string
  sensitive = true
}


# Common config to be shared among multiple sources
source "docker" "ubuntu" {
  commit = true
  changes = [
    "LABEL maintainer=\"huyz\"",
    # Required by systemd; see:
    #   https://developers.redhat.com/blog/2016/09/13/running-systemd-in-a-non-privileged-container
    # To run unprivileged containers with Debian-based distro, /run/lock needs
    #   to be mounted separately; see:
    #   https://github.com/containers/podman/issues/3295#issuecomment-500988204
    # TODO: mount cgroup read-only and then remount /sys/fs/cgroup/systemd read-write?
    #   Actually, this may only apply to cgroupv1 and things are different for cgroupv2:
    #   https://systemd.io/CONTAINER_INTERFACE/
    #   https://serverfault.com/questions/1053187/systemd-fails-to-run-in-a-docker-container-when-using-cgroupv2-cgroupns-priva/1054414#1054414
    #"VOLUME [\"/sys/fs/cgroup:/sys/fs/cgroup\", \"/tmp\", \"/run\", \"/run/lock\"]",
    "VOLUME [\"/tmp\", \"/run\", \"/run/lock\"]",
    # Workaround for Packer design bug that clobbers ENTRYPOINT if empty
    # https://github.com/hashicorp/packer-plugin-docker/issues/9
    "ENTRYPOINT [\"/bin/sh\", \"-c\", \"exec \\\"$0\\\" \\\"$@\\\"\"]",
    "CMD [\"/lib/systemd/systemd\"]",
  ]
}

build {
  name = "ansible-molecule"

  dynamic "source" {
    for_each = ["ubuntu:22.04", "ubuntu:20.04", "ubuntu:18.04", "debian:11"]
    labels   = ["docker.ubuntu"]
    content {
      name  = source.value
      image = source.value
    }
  }

  provisioner "file" {
    source      = "initctl_faker"
    destination = "/tmp/initctl_faker"
  }

  provisioner "shell" {
    script = "scripts/install.sh"
  }

  # NOTE: using a `post-processors` block chains the `post-processor` blocks insied.
  post-processors {
    post-processor "shell-local" {
      inline = [
        "echo 'Your build {{build_name}} for source ${source.name} is complete!'"
      ]
    }

    post-processor "docker-tag" {
      repository = format("%s-%s", var.docker_repo_base, split(":", source.name)[0])
      tags = [split(":", source.name)[1]]
    }
    post-processor "docker-push" {
      //login          = true
      login_username = var.docker_username
      login_password = var.docker_password
      # Don't logout because we have multiple pushes in parallel.
      # https://github.com/hashicorp/packer-plugin-docker/issues/141
    }
  }
}
