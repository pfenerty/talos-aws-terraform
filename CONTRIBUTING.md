# Contributing

## Before you push

CI runs `terraform fmt`, `terraform validate`, `tflint` and `checkov`, and all
four block. `pre-commit install` runs the same set locally, plus the
`terraform-docs` regeneration.

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
terraform-docs -c .terraform-docs.yml cloud-infra/networking
```

Every variable needs a `description`. The generated tables are only as useful
as those are.

## Conventions

* Directories are kebab-case (`cloud-infra`, `post-install`); outputs live in
  `outputs.tf`.
* Provider versions are pinned exactly, in every module that uses a provider,
  so Renovate can see and bump them. Component versions held in variable
  defaults need a `# renovate:` comment above them to be picked up.
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
