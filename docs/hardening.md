# Hardening

What the `hardening` variable does, what Talos already does without it, and
what cannot be done from a machine config at all. Everything here was checked
against Talos machinery 1.13 - the version `terraform-provider-talos` 0.11.0
vendors - and against machine configs rendered by this module.

## Scope, and the thing to be honest about first

There is no DISA STIG for Talos Linux. Two documents could apply, and they
land very differently:

* The **Kubernetes STIG** is mostly API server, controller manager, scheduler,
  etcd and kubelet settings. That is the half a machine config carries well,
  and it is what `hardening` addresses.
* The **General Purpose Operating System SRG** assumes a shell, PAM, auditd,
  an SSH daemon, login banners and file ownership on `/etc/kubernetes`. Talos
  has none of those: no shell, no SSH, no package manager, an immutable
  read-only root filesystem, and an API rather than a login. Those checks are
  not failed so much as unimplementable as written. They become documented
  not-applicable and compensating-control entries, not configuration.

So `hardening` is the machine config half of a baseline, not a baseline. It
does not make the cluster STIG compliant, and nothing in this repository
produces evidence for an assessor.

## What Talos already does, unprompted

This is most of the technical content of the Kubernetes STIG, and it is on by
default. The delta below is small because this list is long.

| Setting | Value | Where it comes from |
|---|---|---|
| `anonymous-auth` | `false` | kube-apiserver defaults |
| `profiling` | `false` | apiserver, controller manager and scheduler defaults |
| `audit-log-path` | set | apiserver defaults |
| `audit-log-maxage` / `-maxbackup` / `-maxsize` | `30` / `10` / `100` | apiserver defaults |
| `tls-cipher-suites` | AEAD suites only | apiserver defaults |
| `use-service-account-credentials` | set | controller manager defaults |
| Secrets encrypted at rest in etcd | secretbox | `talos_machine_secrets` generates the key |
| etcd peer and client mTLS | on | Talos generates the PKI |
| Pod Security Admission | `baseline` enforced, `restricted` audited and warned, `kube-system` exempt | generated machine config |
| Kubelet anonymous auth | off | kubelet defaults, not overridable from config |
| Kubelet authn/authz | webhook | kubelet defaults |
| `rotateCertificates` | `true` | kubelet defaults |
| `protectKernelDefaults` | `true` | kubelet defaults |
| `streamingConnectionIdleTimeout` | `5m` | kubelet defaults |
| `defaultRuntimeSeccompProfileEnabled` | `true` | generated machine config |
| KSPP kernel parameters | `slab_nomerge`, `pti=on` | Talos kernel defaults |
| NTP | Amazon Time Sync, `169.254.169.123` and `fd00:ec2::123` | the Talos AWS platform sets this |

Two consequences worth stating plainly:

* Setting `machine.time.servers` would **override** the Amazon Time Sync
  addresses the AWS platform already installs. Leave it alone unless you have
  an approved time source that is not Amazon's.
* Patches for the kubelet settings above render byte-for-byte identical
  configs. That was measured, not assumed, and it is why `hardening` has no
  worker half.

## What `hardening` adds

Off by default, because both changes can stop workloads being admitted or
change what lands in the audit log.

**Pod Security Admission at `restricted`.** `pod_security_enforce` picks the
standard enforced cluster-wide and `pod_security_exempt_namespaces` the
namespaces exempted from it. `kube-system` must stay exempt and is validated
as such: Cilium runs a privileged pod there and the cluster cannot reach a
healthy state without a CNI. If you add controllers of your own in other
namespaces, expect to exempt them or fix their pod security contexts - the
Karpenter, EBS CSI and Flux controllers are all `restricted`-clean, but a
DaemonSet that wants `hostPath` or `NET_ADMIN` will not be.

**A real audit policy.** Talos's default is a single `level: Metadata`
catch-all, which satisfies "auditing is on" and little else. The replacement
drops the highest-volume reads, records full request and response bodies for
RBAC objects and for writes to pods, namespaces, nodes and service accounts,
and keeps `Metadata` as the floor for everything else. Secrets and ConfigMaps
stay at `Metadata` deliberately: `RequestResponse` on them would copy secret
values into the audit log, which turns the log into the thing you have to
protect most.

Enabling it costs about 1.1 KB of control plane user data (11336 → 12463
bytes of the 16384 available).

## What it deliberately does not do

| Item | Why not |
|---|---|
| `serverTLSBootstrap` | Needs something in the cluster approving kubelet serving CSRs. Without an approver the serving certificate never issues and the node is broken. |
| Node disk encryption | The root EBS volume is already encrypted by the launch template. Talos can do LUKS2 on `EPHEMERAL`/`STATE` via `VolumeConfig`, but every key kind is awkward here: a `static` passphrase would sit in the machine config, `tpm` needs a TPM the instance types used here do not present, and `nodeID` ties the volume to the node. |
| FIPS 140-3 | An image choice, not a config field. It needs an Image Factory schematic and a different AMI; `modules/cluster/cloud-infra/compute` pins the stock Sidero AMI by owner and name. |
| Shipping the audit log off the node | `machine.logging.destinations` carries Talos service logs only, as `json_lines` over TCP or UDP. The kube-apiserver audit log is a file on the control plane node and needs a collector running in the cluster. |
| Default-deny NetworkPolicies, per-namespace PSA labels, RBAC review, image signature policy, quotas | Cluster policy. It belongs in the Flux bootstrap repository, where it can be reconciled and drift-corrected. |
| Narrowing the API exposure | `talos_api_allowed_cidr` and `kubernetes_api_allowed_cidr` both default to `0.0.0.0/0`. No baseline passes with the machine management API open to the internet, and no machine config setting can compensate for it. Set them. |

## How the patches are built

`modules/cluster/talos/config/main.tf` builds one patch per concern and lets
Talos compose them, rather than merging them in HCL. Talos applies each
element of `config_patches` in order as a strategic merge against the whole
configuration, under four rules:

1. **Maps merge key by key.** Two patches both touching
   `machine.kubelet.extraArgs` produce the union of their keys. The older
   version of this module merged patches in HCL to avoid a clobber that
   strategic merge does not actually do.
2. **Lists append.** Exactly three fields in v1alpha1 are tagged
   `merge:"replace"`: `cluster.network.podSubnets`,
   `cluster.network.serviceSubnets` and `cluster.apiServer.auditPolicy`.
   Everything else list-valued appends to what the generator already wrote.
3. **To replace a populated list, delete it first.** `talosctl gen config`
   writes a `PodSecurity` entry into `cluster.apiServer.admissionControl`, so
   setting that field appends a second one. The fix is `$patch: delete` in one
   patch and the replacement in the next, because a single patch may not
   modify the same document twice.
4. **Patches may add whole documents**, matched on `apiVersion`, `kind` and
   `name` - but only documents the provider's vendored machinery knows.

Patches are also scoped by role. `kube-apiserver` and `kube-controller-manager`
only run on control plane nodes, so their settings are not in the patch applied
to workers, where they would be inert configuration spending a worker's share
of a fixed 16 KB.

### Size

EC2 caps user data at 16 KB of raw, pre-base64 bytes, and on this platform the
machine config *is* the user data. As rendered today:

| Config | Bytes | Headroom |
|---|---|---|
| Control plane, `hardening` off | 11336 | 5048 |
| Control plane, `hardening` on | 12463 | 3921 |
| Worker | 2958 | 13426 |
| Karpenter worker | 3028 | 13356 |

Each `talos_machine_configuration` data source carries a postcondition
asserting the result fits. That is not decoration: exceeding the limit
otherwise fails at apply time with an AWS error that does not mention user
data, and Karpenter nodes would fail to launch at all rather than fail a plan.

## Version skew

`terraform-provider-talos` 0.11.0 vendors Talos machinery **1.13.0**, and that
is what generates the configuration and applies these patches - regardless of
what `talos_version` says the nodes will run (currently 1.14.1).

Talos 1.14 moves nearly every setting used here into dedicated configuration
documents and deprecates the v1alpha1 fields. Those documents are not usable
from this module yet: machinery 1.13 rejects document kinds it does not know.
The deprecated fields still work in 1.14, so nothing is broken; the migration
is simply not available. When the provider bumps its machinery:

| v1alpha1 field used here | 1.14 document |
|---|---|
| `cluster.apiServer.extraArgs` | `KubeAPIServerConfig` |
| `cluster.apiServer.admissionControl` | `KubeAdmissionControlConfig` |
| `cluster.apiServer.auditPolicy` | `KubeAuditPolicyConfig` |
| `cluster.controllerManager.extraArgs` | `KubeControllerManagerConfig` |
| `cluster.network.podSubnets` | `KubeNetworkConfig` |
| `cluster.proxy` | `KubeProxyConfig` |
| `machine.kubelet.extraArgs` | `KubeletConfig` |
| `machine.kubelet.registerWithFQDN` | `KubeNodeConfig` |

Migrating is not a like-for-like rename. `KubeNetworkConfig.podSubnets`
overwrites on merge where the v1alpha1 field is one of the three tagged
`merge:"replace"`, and `KubeAuditPolicyConfig.configuration` replaces rather
than merges, so the delete-then-set idiom above stops being necessary for
admission control only if `KubeAdmissionControlConfig` is unnamed and
singular. Re-derive the merge behaviour from the reference at that point
rather than assuming these patches port unchanged.

One observable consequence of the skew today: the generated config pins
`machine.install.image` to `ghcr.io/siderolabs/installer:v1.13.0`, the
machinery's own version, even though `talos_version` is `v1.14.1` and the AMI
is 1.14.1. It is inert while nodes boot from the AMI and are never upgraded
in place, and it would be the wrong installer the moment one is.

## Known limitation: machine config changes do not reach running nodes

**This needs a solution that does not exist in this repository yet.** Changing
any patch here - enabling `hardening` on a live cluster, for instance - does
not reconfigure anything. It replaces everything.

The machine config is user data. Talos reads user data once, at first boot,
and thereafter its configuration lives in the `STATE` partition. A running
node will never notice that Terraform rendered a different config. What
Terraform does instead is:

* write a new launch template version, which
* triggers a rolling instance refresh on both autoscaling groups, because an
  `instance_refresh` block is configured and a launch template change starts
  one, so
* every control plane and baseline worker node is replaced, and separately
* `node-user-data` in the `karpenter-config` secret changes, which Karpenter
  sees as drift and acts on by replacing its nodes too.

With `control_plane_nodes = 1` that is an API server outage, not a rolling
update. Even at three it is a full control plane replacement and an etcd
membership change per node, to deliver what may be a one-line config edit.

The out-of-band alternative is `talosctl apply-config` against the live nodes,
which works and is what Talos expects, but Terraform neither performs nor
tracks it - so the cluster ends up configured differently from what the state
file describes, and the next instance refresh silently reverts it. The
provider's `talos_machine_configuration_apply` resource does not fit either:
it addresses nodes by endpoint, and these nodes are launched by an autoscaling
group with addresses Terraform does not know ahead of time.

Approaches worth weighing when this is picked up, none of them free:

* Keep user data to a minimal bootstrap config and apply the rest through the
  Talos API from a controller in the cluster, which also relieves the 16 KB
  ceiling.
* Accept the replacement but make it survivable: three control plane nodes
  minimum, and gate config changes behind a maintenance window.
* Drive `talosctl apply-config` from Terraform against discovered node
  addresses, accepting that the state model stays approximate.
