# Contributing

## Before you push

`pre-commit install` runs `terraform fmt`, `terraform validate`, `tflint` and
`checkov` on commit, plus the `terraform-docs` regeneration.

Without pre-commit:

```sh
terraform fmt -recursive
terraform init -backend=false
terraform validate
tflint --recursive --minimum-failure-severity=warning
checkov -d . --config-file .checkov.yaml --framework terraform
```

## Module documentation

Each module's README carries a generated reference table between
`BEGIN_TF_DOCS` and `END_TF_DOCS`. Do not edit inside the markers; add a
description above them and regenerate:

```sh
terraform-docs -c .terraform-docs.yml modules/cluster/cloud-infra/networking
```

Every variable needs a `description`. The generated tables are only as useful
as those are.

## Conventions

* Directories are kebab-case (`cloud-infra`, `flux-bootstrap`); outputs live in
  `outputs.tf`, and provider requirements in `versions.tf`.
* No module declares a `provider` block. Provider *requirements* go in every
  module that uses one; provider *configuration* belongs to the caller, and
  `examples/full` is where it lives. A module carrying a provider block cannot
  be used with `count`, `for_each` or `depends_on`.
* Provider versions are `~>` ranges, not exact pins. These constraints are
  intersected with every other module in a consumer's configuration, so an
  exact pin makes this one unusable next to anything that has moved on a patch
  release. Renovate bumps the range floor. Component versions held in variable
  defaults need a `# renovate:` comment above them to be picked up.
* Nothing is written to the caller's filesystem unless they ask for it.
  `local_file` and `local_sensitive_file` resources are gated on a path
  variable that defaults to null; fixed relative filenames collide when the
  module is instantiated twice.
* Resource tags come from a `tags` variable threaded down from the parent, not
  from provider `default_tags`. A module does not get to configure its
  caller's provider, and the `kubernetes.io/cluster/<name>` tag is load-bearing
  for the AWS cloud controller manager.
* Security group rules are standalone
  `aws_vpc_security_group_{ingress,egress}_rule` resources. Do not add inline
  `ingress`/`egress` blocks: mixing the two makes Terraform fight itself.
* A checkov finding is either fixed or added to `.checkov.yaml` with a comment
  saying why it does not apply. Do not leave it failing.
* AWS resource names are kebab-case and prefixed with `project_name`
  (`<project>-internal`, `<project>-control-plane`). Renaming one replaces the
  resource, so get it right the first time.
* `project_name` is used verbatim as the load balancer and target group name,
  which AWS limits to 32 characters of alphanumerics and hyphens. That is what
  the validations on it are enforcing; do not loosen them without checking what
  still consumes the name.
