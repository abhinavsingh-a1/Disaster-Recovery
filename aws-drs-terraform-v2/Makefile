VAR_FILE ?= envs/lab.tfvars

.PHONY: init init-local fmt validate lint test security plan apply status drill failover failback destroy

init:          ## init with remote state (backend.hcl)
	terraform init -backend-config=backend.hcl

init-local:    ## init without backend (offline checks)
	terraform init -backend=false

fmt:
	terraform fmt -recursive

validate: init-local
	terraform validate

lint:
	tflint --init && tflint --recursive --config "$(CURDIR)/.tflint.hcl"
	shellcheck -x scripts/*.sh

test: init-local
	terraform test

security:
	checkov -d . --config-file .checkov.yaml

plan:
	terraform plan -var-file=$(VAR_FILE) -out=tfplan

apply:
	terraform apply tfplan

status:
	./scripts/status.sh

drill:
	./scripts/drill-test.sh

failover:
	./scripts/failover.sh latest --with-database

failback:
	./scripts/failback.sh

destroy:
	./scripts/cleanup-drs.sh && terraform destroy -var-file=$(VAR_FILE)
