# Migration notes

Changes that existing state cannot absorb on its own. Anything not listed here
applies cleanly with `terraform apply`.

If the cluster is disposable, destroying and recreating it is both faster and
safer than every procedure below. These notes are for a cluster you want to
keep.

## Subnets moved from `count` to `for_each`

Subnets are now addressed by Availability Zone (`aws_subnet.this["us-east-2a"]`)
instead of by list position (`aws_subnet.this[0]`). The resources themselves are
unchanged, so this is purely a state move - but without it Terraform reads the
old addresses as gone and plans to destroy every subnet, which takes the
cluster with them.

`moved` blocks cannot express this: they require static addresses, and the zone
names depend on `var.region`.

Check what the plan intends before running anything:

```sh
terraform plan | grep -E 'aws_subnet.this'
```

If it shows destroys, move each subnet to its zone-keyed address. The zone for
index `i` is the `i`th entry of the region's zone list:

```sh
terraform state list | grep 'aws_subnet.this\['
aws ec2 describe-availability-zones --region "$REGION" \
  --query 'AvailabilityZones[].ZoneName' --output text
```

Then, per subnet:

```sh
terraform state mv \
  'module.networking.aws_subnet.this[0]' \
  'module.networking.aws_subnet.this["us-east-2a"]'
```

Re-run `terraform plan` afterwards. A correct move leaves the subnets showing
an in-place tag update (the new `Name` tag) and nothing else.

Pin `availability_zones` to the zone list you just moved to. Left null, the
layout still follows whatever AWS reports for the region, which is the problem
this change set out to fix.

## Security groups are replaced, not updated

Both security groups gain a `description`. AWS does not allow that field to be
changed, so Terraform replaces the group - and a replacement cannot be deleted
while instances still reference it. On a running cluster the apply fails part
way with `DependencyViolation`.

There is no in-place path. Either recreate the cluster, or swap the groups by
hand: create the replacements, move every instance and network interface onto
them, then let Terraform adopt the result.

Dropping the two `description` lines avoids this entirely, at the cost of the
`CKV_AWS_23` finding coming back. That is a reasonable trade if the cluster has
to stay up.

## Security group rules became separate resources

Inline `ingress`/`egress` blocks are now
`aws_vpc_security_group_{ingress,egress}_rule` resources. Terraform revokes the
inline rules and creates the standalone ones in the same apply, so the API
ingress briefly disappears. Established connections may be dropped; new ones
work as soon as the rules land.

Importing the existing rules instead avoids the window:

```sh
aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=<sg-id>" \
  --query 'SecurityGroupRules[].[SecurityGroupRuleId,IsEgress,IpProtocol,CidrIpv4]' \
  --output table

terraform import \
  'module.networking.aws_vpc_security_group_ingress_rule.kubernetes_api' sgr-0123456789abcdef0
```

## IMDSv2 is now required

`http_tokens = "required"` changes both launch templates, which triggers a
rolling instance refresh - every node is replaced.

Talos supports IMDSv2, but verify on a throwaway cluster before applying this
to one that matters: a node that cannot reach the metadata service does not
join, and the refresh will keep cycling nodes while it fails.

## Instance refresh launches before terminating

The control plane group's `max_size` is now `control_plane_nodes + 1` so a
refresh has room to launch a replacement first. Previously
`min_healthy_percentage = 50` on a group of one rounded down to zero healthy
instances, so the only control plane node was terminated before its replacement
existed.

Applies cleanly. Worth knowing because the group can now briefly run one more
node than `control_plane_nodes`.
