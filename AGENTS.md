# Agent instructions: talos-aws-terraform

A public, reusable Terraform/OpenTofu module that builds a Talos Linux
Kubernetes cluster in AWS and bootstraps it into Flux in one apply. README.md
explains the design (bootstrap order, machine config size, identity, cost), and
CONTRIBUTING.md sets the conventions. Read both before changing modules.

## Workspace

This repo is part of `~/code/infra`. See `~/code/infra/CLAUDE.md` for the
other repos and how changes propagate between them.

- **talos-aws-gitops** (`pfenerty/talos-aws-gitops`) is the Flux repository
  these clusters sync. `modules/bootstrap` publishes the Secrets and ConfigMaps
  it reads (`cilium-config`, `karpenter-config`, `cluster-versions`, …). A
  change to their names or shapes lands here first, then in talos-aws-gitops.

## Layout

| Path | What |
|------|------|
| `main.tf`, `variables.tf`, `outputs.tf` | Root convenience wrapper over the two modules |
| `modules/cluster` | VPC, LB, ASGs, Talos machine config + bootstrap (`aws`, `talos`, `local`) |
| `modules/bootstrap` | Cilium, health gate, Flux, OIDC/IRSA, Karpenter AWS side (`kubernetes`, `helm`, `flux`) |
| `examples/full` | Provider configuration and a working call. Its state and tfvars are local and gitignored |
| `docs/hardening.md` | STIG/CIS accounting |

## Quality gates

`flox activate` provides `tofu`, `talosctl`, `awscli2` and `kubescape`, plus
`bd` from `~/code/common`. Before pushing:

```sh
tofu fmt -recursive -check
tofu init -backend=false && tofu validate
pre-commit run --all-files   # tflint, terraform-docs, checkov (see CONTRIBUTING.md)
```

Generated `BEGIN_TF_DOCS` tables are regenerated with terraform-docs, never
edited by hand.

## Issue tracking

Beads (`bd`, prefix `talos`) syncs through Dolt over git (`refs/dolt/data`).
This repo is public, so its beads DB is too: don't use `bd remember`. Durable
knowledge goes in this file. Cross-repo epics live in the infra hub
(`~/code/infra/planning`, prefix `infraplan`). When an issue belongs to one,
note `Parent epic: infraplan-xyz`.

```bash
bd ready / bd show <id> / bd update <id> --claim / bd close <id>
```

Work on a branch and open a PR. Don't push to `main`.
