TF  ?= terraform
DIR := terraform/envs/dev

.PHONY: help init fmt check plan apply output demo sleep destroy

help:      ## list targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

init:      ## terraform init (S3 backend)
	$(TF) -chdir=$(DIR) init

fmt:       ## format every .tf file
	$(TF) fmt -recursive terraform

check:     ## what CI runs: fmt check + validate (no AWS calls)
	$(TF) fmt -check -recursive terraform
	$(TF) -chdir=$(DIR) init -backend=false -input=false >/dev/null
	$(TF) -chdir=$(DIR) validate

plan:      ## plan with terraform.tfvars, saved to tf.plan
	$(TF) -chdir=$(DIR) plan -out tf.plan

apply:     ## apply the saved plan
	$(TF) -chdir=$(DIR) apply tf.plan

output:    ## print URLs, IDs and IPs
	$(TF) -chdir=$(DIR) output

demo:      ## run the demo tests (ARGS="--auto", "--only T1,T17", "--week 2", "--with-plan", "--slow")
	bash scripts/demo-tests.sh $(ARGS)

sleep:     ## end of session: one plan that switches off web tier, NAT, hybrid, VPN, IR (keeps hub, monitoring, edge)
	bash scripts/sleep.sh

destroy:   ## final day only: destroy everything
	$(TF) -chdir=$(DIR) destroy
