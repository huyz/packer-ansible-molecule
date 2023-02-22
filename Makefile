# For debugging output
export PACKER_LOG := 1

.DEFAULT_GOAL := build

PACKER_CONFIGS := $(wildcard *.pkr.hcl)
_FMT_PACKER_CONFIGS := $(addprefix fmt--,$(PACKER_CONFIGS))
_VALIDATE_PACKER_CONFIGS := $(addprefix validate--,$(PACKER_CONFIGS))
_BUILD_PACKER_CONFIGS := $(addprefix build--,$(PACKER_CONFIGS))


# Docker login before the docker-push post-processors are invoked.
# We don't let Packer do a login because of conflicts:
# https://github.com/hashicorp/packer-plugin-docker/issues/141
.PHONY: docker-login
docker-login:
	@echo "Logging into Docker Hub..."
	@if [[ -n "$$PKR_VAR_docker_username" && -n "$$PKR_VAR_docker_password" ]]; then \
		docker login -u "$$PKR_VAR_docker_username" --password-stdin <<< "$$PKR_VAR_docker_password"; \
	else \
		docker login; \
	fi

# Usage:
# - make fmt
# - make fmt--docker-ubuntu.pkr.hcl
.PHONY: fmt $(_FMT_PACKER_CONFIGS)
fmt: $(_FMT_PACKER_CONFIGS)
$(_FMT_PACKER_CONFIGS): export config=$(@:fmt--%=%)
$(_FMT_PACKER_CONFIGS):
	@echo "Formatting $(config)..."
	packer fmt "$(config)"

# Usage:
# - make validate
# - make validate--docker-ubuntu.pkr.hcl
.PHONY: validate $(_VALIDATE_PACKER_CONFIGS)
validate: $(_VALIDATE_PACKER_CONFIGS)
$(_VALIDATE_PACKER_CONFIGS): export config=$(@:validate--%=%)
$(_VALIDATE_PACKER_CONFIGS):
	@echo "Validating $(config)..."
	packer validate "$(config)"


# Usage:
# - make build
# - make build--docker-ubuntu.pkr.hcl
.PHONY: build $(_BUILD_PACKER_CONFIGS)
build: $(_BUILD_PACKER_CONFIGS)
$(_BUILD_PACKER_CONFIGS): export config=$(@:build--%=%)
$(_BUILD_PACKER_CONFIGS): docker-login
	@echo "Building $(config)..."
	packer build "$(config)"
