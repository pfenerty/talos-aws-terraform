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
produces evidence for an assessor. The rule-by-rule accounting is in the
coverage matrix below: of the 92 Kubernetes STIG rules, 51 are satisfied by
Talos defaults, 6 by `hardening`, 11 belong wholly to the Flux bootstrap
repository and are not written yet, 22 cannot be checked as written on an
immutable node, and 2 are not covered anywhere. Those counts total 92;
V-242437 is counted among the six and appears in the Flux table as well,
because it is the one rule split across both. The 22 get a written
disposition of their own, after the matrix.

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
  configs. That was measured, not assumed. The kubelet's serving certificate
  is the one exception, and the only reason `hardening` has a worker half at
  all.

## Cluster identity, which is not behind the variable

Two things are always on, because both would be pointless as options and
neither can be turned on later without replacing every node.

**Nothing in the cluster holds an AWS key pair.** The cloud controller
manager, the EBS CSI driver and Karpenter each assume an IAM role by
presenting a service account token the cluster signed, against an OpenID
Connect provider registered from the cluster's own discovery documents.
Each role's trust policy pins `sub` to a single service account and `aud` to
`sts.amazonaws.com`, both with `StringEquals`. The API server flags that make
this possible - `service-account-issuer` and `api-audiences` - are in the
machine config, which is why this is not a switch: changing the issuer on a
running cluster invalidates every token in flight.

**A pod cannot reach the instance metadata service.** Both launch templates
set an IMDS hop limit of 1, so a packet from a pod's network namespace is
dropped before `169.254.169.254`. This is what makes the roles above worth
scoping: a role restricted to one service account is no restriction at all
while any pod can ask metadata for the node's credentials instead. The
control plane role is empty in consequence - the cloud controller manager was
its only consumer - and the worker role carries nothing but ECR pull and
`ec2:Describe*`, both used by the kubelet on the host.

The cost is a constraint on what can be deployed: nothing in a pod may read
instance metadata. The two components that used to are configured not to, in
the Flux bootstrap repository. A workload added later that expects IMDS will
not work, and the failure will look like a credential problem rather than a
network one.

STIG has no rule for either. They are here because the alternative - long-lived
keys in Terraform state and in Kubernetes secrets, and a metadata endpoint any
pod can read - is the more likely way this cluster would actually be lost.

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

**A CA-signed kubelet serving certificate**, behind its own
`kubelet_serving_certificates` flag rather than `enabled`, because it has a
prerequisite outside this repository. Left alone, the kubelet self-signs the
certificate it serves on port 10250 and the API server never checks it. The
flag sets two things that are each pointless without the other:

* `serverTLSBootstrap: true` on the kubelet, so it requests a certificate from
  the cluster CA and rotates it, instead of self-signing.
* `kubelet-certificate-authority` on the API server, so it verifies what the
  kubelet presents. Talos sets no such flag by default, which is why issuing a
  properly signed certificate changes nothing observable until this is set too.

Enabling `hardening` costs about 1.1 KB of control plane user data (11336 →
12463 bytes of the 16384 available); adding the serving certificates costs
another 150 bytes on the control plane and 58 on each worker.

## What it deliberately does not do

| Item | Why not |
|---|---|
| Enabling `kubelet_serving_certificates` by default | It depends on a CSR approver that has to be deployed by Flux, and turning it on without one breaks `kubectl logs` and `exec`. It is opt-in for that reason, not because the setting is wrong. |
| Node disk encryption | The root EBS volume is already encrypted by the launch template. Talos can do LUKS2 on `EPHEMERAL`/`STATE` via `VolumeConfig`, but every key kind is awkward here: a `static` passphrase would sit in the machine config, `tpm` needs a TPM the instance types used here do not present, and `nodeID` ties the volume to the node. |
| FIPS 140-3 | An image choice, not a config field. It needs an Image Factory schematic and a different AMI; `modules/cluster/cloud-infra/compute` pins the stock Sidero AMI by owner and name. |
| Shipping the audit log off the node | `machine.logging.destinations` carries Talos service logs only, as `json_lines` over TCP or UDP. The kube-apiserver audit log is a file on the control plane node and needs a collector running in the cluster. |
| Default-deny NetworkPolicies, per-namespace PSA labels, RBAC review, image signature policy, quotas | Cluster policy. It belongs in the Flux bootstrap repository, where it can be reconciled and drift-corrected. |
| Narrowing the API exposure | `talos_api_allowed_cidr` and `kubernetes_api_allowed_cidr` both default to `0.0.0.0/0`. No baseline passes with the machine management API open to the internet, and no machine config setting can compensate for it. Set them. |

## Kubernetes STIG coverage matrix

Rule IDs are from the DISA Kubernetes STIG as published on 2026-02-12, which
carries 92 rules. All 92 appear in the matrix below, each once, except
V-242437, which is split: its cluster-wide half is configuration here and its per-namespace half
is Flux's. Severities are deliberately omitted rather than transcribed from a
secondary source; take CAT levels from the official XCCDF when you need them.

Read this as an engineering account of where each control lives, not as an
assessment. Nothing here has been checked by a scanner against a running
cluster, and several rules pass in substance while failing the check
procedure as written - those are called out.

### Covered here, by Talos defaults

No configuration in this repository is required for these. They are how Talos
generates and runs the cluster, verified against machinery 1.13 and against
configs rendered by this module.

| Rule | Control | How |
|---|---|---|
| V-242376, V-242377, V-242378, V-242418 | TLS 1.2 minimum, approved ciphers | `tls-min-version=VersionTLS12` on the API server and `VersionTLS13` on the controller manager and scheduler; AEAD-only cipher list |
| V-242379, V-242380, V-242423, V-242426, V-242427, V-242428, V-242429, V-242430, V-242431, V-242432, V-242433 | etcd TLS, client and peer certificate authentication | `client-cert-auth=true`, `peer-client-cert-auth=true`, `trusted-ca-file` and `peer-trusted-ca-file`, against a PKI Talos generates |
| V-242382 | `Node,RBAC` authorization | set by Talos, and not removable by config |
| V-242384, V-242385 | Scheduler and controller manager secure binding | `bind-address=127.0.0.1` on both |
| V-242387 | Kubelet `readOnlyPort` disabled | not set in the rendered config; the KubeletConfiguration default is 0. Worth confirming on a node - it is the one item here inferred from a Kubernetes default rather than read out of Talos |
| V-242389 | API server secure port | `secure-port` set; there is no insecure port to disable |
| V-242390 | API server anonymous authentication disabled | `anonymous-auth=false` |
| V-242391, V-242392 | Kubelet anonymous authentication disabled, explicit authorization | anonymous off, webhook authentication and authorization; not overridable from the machine config |
| V-242393, V-242394 | No sshd running or enabled on worker nodes | Talos ships no SSH daemon, and no shell to run one |
| V-242397 | Kubelet `staticPodPath` unset | `disableManifestsDirectory: true` in the generated config empties it |
| V-242398, V-242399 | DynamicAuditing and DynamicKubeletConfig disabled | both features were removed from Kubernetes well before 1.37 |
| V-242400 | Alpha APIs disabled | `runtime-config` is not set, so alpha APIs stay off |
| V-242402, V-242461, V-242462, V-242463, V-242464, V-242465 | Audit logging enabled, path, max size, max backup, retention | `audit-log-path`, `-maxsize=100`, `-maxbackup=10`, `-maxage=30` |
| V-242404 | Kubelet must deny hostname override | **deviation.** Talos sets `hostname-override` to the node's expected name, and this module adds `registerWithFQDN`. The value is platform-controlled rather than operator-supplied, but the check as written expects the flag absent and will flag it |
| V-242409 | Controller manager profiling disabled | `profiling=false` on the controller manager, scheduler and API server |
| V-242410, V-242411, V-242412, V-242413 | PPS conformance for API server, scheduler, controllers, etcd | components listen on their standard ports, and the security groups in `modules/cluster/cloud-infra/networking` bound what can reach them. Reconciling those against the PPSM CAL is paperwork, not configuration |
| V-242419, V-242420, V-242421, V-242422 | Certificate authorities and serving certificates wired for the API server, kubelet and controller manager | `client-ca-file`, `tls-cert-file`, kubelet `ClientCAFile`, controller manager `root-ca-file` |
| V-242434 | Kubelet kernel protection | `protectKernelDefaults=true` |
| V-242436 | ValidatingAdmissionWebhook enabled | enabled by Kubernetes default; Talos additionally enables `NodeRestriction` |
| V-245541 | Kubelet must not disable timeouts | `streamingConnectionIdleTimeout` defaults to 5m |
| V-245542, V-245543 | Basic and token authentication disabled | neither `basic-auth-file` nor `token-auth-file` is set, and both mechanisms are gone from Kubernetes |
| V-274882 | Secrets encrypted at rest | `encryption-provider-config` is always passed, keyed by the secretbox secret `talos_machine_secrets` generates |

### Covered here, by `hardening`

| Rule | Control | How |
|---|---|---|
| V-242403 | Audit records must identify event type, source, result, user and container | the audit policy this variable installs. Talos's default `level: Metadata` catch-all does not carry enough to satisfy this |
| V-242437 | Pod security policy set | PSA replaces PSP. `hardening` sets the cluster-wide default; per-namespace labels are Flux's half, below |
| V-254800 | Pod Security Admission control file configured | `cluster.apiServer.admissionControl`. Talos configures one by default at `baseline`; `hardening` raises it to `restricted` |
| V-254801 | PodSecurity admission controller enabled | same file, applied to every namespace outside the exemption list |
| V-242424, V-242425 | Kubelet `tlsPrivateKeyFile` and `tlsCertFile` | `kubelet_serving_certificates`. **Deviation in the check, not the control.** The kubelet bootstraps a CA-signed certificate and rotates it, and the API server verifies it. The config fields the check reads stay empty, because the certificate is issued and renewed rather than placed - it lives at `/var/lib/kubelet/pki/kubelet-server-current.pem`. Setting the fields literally would mean baking a certificate and private key into user data that every node in the autoscaling group shares, with SANs for addresses that do not exist at render time. Rotation is the compensating control. **Requires the Flux dependency below.** |

### Belongs in the Flux bootstrap repository

Cluster policy. None of it can be expressed in a machine config, and all of it
needs continuous reconciliation rather than a one-time apply. **None of this
exists yet** - it is a list of what the bootstrap repository owes, not a
description of what it does.

| Rule | Control |
|---|---|
| V-242381 | Unique service accounts per workload |
| V-242383 | User-managed resources in dedicated namespaces |
| V-242395 | Kubernetes dashboard not deployed |
| V-242396 | `kubectl cp` and exec access constrained by RBAC |
| V-242414 | No privileged host ports for user pods |
| V-242415 | Secrets not passed as environment variables |
| V-242417 | User workloads separated from control plane functions |
| V-242437 (part) | Per-namespace Pod Security Admission labels |
| V-242442 | Old components removed after upgrades |
| V-242443 | Components patched per IAVM. Renovate covers the version bumps in this repository; landing them on a cluster is Flux's |
| V-274883 | Sensitive data held in Secrets or an external store. The AWS half is covered: the components that talk to AWS assume roles and hold no keys |
| V-274884 | Secret access restricted to need-to-know via RBAC |

**Named dependency: a kubelet-serving CSR approver.** This one is not a rule of
its own - it is what V-242424 and V-242425 above depend on, and the reason
`kubelet_serving_certificates` is opt-in. kube-controller-manager refuses to
auto-approve `kubernetes.io/kubelet-serving` CSRs by design: it cannot verify
that the SANs a node requests belong to that node. Something has to make that
judgement, and in practice that is
[`kubelet-csr-approver`](https://github.com/postfinance/kubelet-csr-approver)
as a HelmRelease.

Two things about configuring it here. Nodes register with their FQDN, so names
look like `ip-172-31-4-17.eu-west-2.compute.internal` and the provider regex
has to match that shape. And the approver confirms the name resolves to the
requesting address: the VPC sets neither DNS attribute explicitly
(`modules/cluster/cloud-infra/networking/main.tf`), so `enable_dns_support`
is on by default and private internal names resolve, while
`enable_dns_hostnames` stays off and governs public hostnames only. If that
turns out not to hold, the approver has `bypassDnsResolution` with a tighter
regex as the fallback.

Order of operations: install the approver first. With
`kubelet_serving_certificates` on and no approver, CSRs sit pending - nodes
still register and still run pods, because that path uses the client
certificate, but `kubectl logs`, `exec`, `port-forward` and metrics-server
fail until the CSRs are approved. On a new cluster that window is harmless,
since bootstrap does not need kubelet serving certificates; on a running one
it is a visible outage of exactly those operations.

### Not applicable as written

Every rule in this group checks the ownership or permissions of a file on a
node: `stat` a manifest, a kubeconfig, a PKI file. Talos has no shell to run
the check, an immutable read-only root filesystem, and does not keep these
files where the procedure looks - several do not exist at all. `kubeadm.conf`
has no analogue on Talos, and this cluster runs no kube-proxy, so its
kubeconfig is absent too.

These are not passes. They are rules whose check procedure cannot be executed,
and an assessor will want each one dispositioned as not-applicable with the
immutability argument attached. That disposition is written out in full in the
section immediately after this matrix, including the evidence that can be
produced in place of a `stat`.

| Rule | Control |
|---|---|
| V-242405, V-242406, V-242407, V-242408 | Manifest and KubeletConfiguration ownership and permissions |
| V-242444, V-242445, V-242446 | Component manifest, etcd and conf file ownership |
| V-242447, V-242448 | kube-proxy kubeconfig permissions and ownership |
| V-242449, V-242450 | Kubelet certificate authority file permissions and ownership |
| V-242451, V-242466, V-242467 | PKI directory, certificate and key permissions and ownership |
| V-242452, V-242453, V-242456, V-242457 | Kubelet kubeconfig and config permissions and ownership |
| V-242454, V-242455 | `kubeadm.conf` ownership and permissions |
| V-242459, V-242460 | etcd data and admin kubeconfig permissions |

### Not covered anywhere

| Rule | Control | Why not, and what it would take |
|---|---|---|
| V-242438 | API server request timeouts configured | `request-timeout` is left at the Kubernetes default of 60s rather than set explicitly. One entry in `cluster.apiServer.extraArgs` closes it, and the check wants it stated |
| V-245544 | Approved organizational certificate and key pair | The cluster PKI is self-signed by Talos. Using an organizational CA means generating the machine secrets outside this module and feeding them in, which `talos_machine_secrets` does not currently do here |

## Disposition for the 22 uncheckable rules

Written to be handed to an assessor. Each of these rules checks the ownership
or permissions of a file on a node, by logging in and running `stat`. The
argument below is why that procedure cannot be executed on Talos, what evidence
replaces it, and why the risk the control exists to manage is structurally
absent rather than merely unverified.

Do not paste this into a checklist unread. It is the shape of the argument and
the facts behind it; the wording that satisfies a particular assessor is
theirs to accept.

### Applicability statement

Talos Linux is an API-managed, immutable operating system. It ships no shell,
no SSH daemon, no package manager, and no interactive login of any kind. There
are no operating system user accounts, so there is no `root` user to own a
file in the sense the check means, and no `etcd` user either. The root
filesystem is mounted read-only. All configuration arrives as a single machine
configuration document, applied over an mTLS-authenticated API.

The consequence for this rule family is twofold:

1. **The check procedure cannot be executed.** It directs the assessor to log
   in to the node and inspect a path. There is no login. No amount of
   configuration makes one available.
2. **Several of the files do not exist.** `kubeadm.conf` has no analogue -
   Talos does not use kubeadm and never writes that file. The kube-proxy
   kubeconfig is absent because this cluster runs no kube-proxy at all
   (`cluster.proxy.disabled`, with Cilium providing the replacement). The
   administrative kubeconfig is not stored on any node: it is generated on
   demand through the Talos API.

Where the files do exist, they are at Talos's own paths rather than the ones
the check names - Kubernetes PKI and component secrets under
`/system/secrets/kubernetes/`, etcd PKI under `/system/secrets/etcd`, etcd
data under `/var/lib/etcd`, kubelet material under `/var/lib/kubelet/pki` and
`/system/secrets/kubelet`, static pod manifests under `/etc/kubernetes/manifests`.

### Why the underlying risk is absent

These controls exist because on a conventional node an operator, a package
postinstall script, or a compromised process can loosen a file's mode or
change its owner, and nothing would notice. The control is a periodic check
for that drift.

On Talos every one of those files is created by the operating system itself,
at a fixed mode, during boot or during a configuration apply. There is no
interactive session, no user to act as, no package manager to run a script,
and a read-only root filesystem underneath. Drift of the kind the control
detects has no mechanism by which to occur. The file permissions are a
property of the Talos release, not of how the node was administered - and the
Talos release is pinned in version control (`talos_version`) and applied by
Terraform.

This is a stronger position than a passing `stat`, not a weaker one: a passing
check tells you the permissions were correct at the moment of the check, and
says nothing about the next hour.

### Evidence that can be produced

The absence of a shell does not mean the absence of evidence. Talos exposes
the filesystem over its API, and an assessor with a `talosconfig` can obtain
the same facts the check wants:

* `talosctl -n <node> list -l <path>` returns a directory listing with mode,
  owner and group - the content of a `stat`, by a different route.
* `talosctl -n <node> read <path>` returns a file's contents.
* `talosctl -n <node> get <resource>` returns the running configuration Talos
  derived, including the rendered admission control and kubelet configuration.

Both are authenticated with mutual TLS against the cluster's Talos PKI and are
subject to Talos's own RBAC, so the evidence-gathering path is itself
access-controlled and auditable - unlike an SSH session with a root shell,
which is what the original procedure assumes.

### Per-family disposition

| Rules | Files | Disposition |
|---|---|---|
| V-242405, V-242406, V-242407, V-242408, V-242444, V-242446 | Static pod manifests, KubeletConfiguration, component conf files | Written by Talos at fixed modes under `/etc/kubernetes`; no operator path exists to modify them. Evidence via `talosctl list -l`. |
| V-242445 | etcd data directory ownership by an `etcd` user | Not applicable: Talos has no OS user accounts. etcd runs as a container managed by Talos, with data under `/var/lib/etcd`. |
| V-242447, V-242448 | kube-proxy kubeconfig | Not applicable on absence: this cluster runs no kube-proxy. The file is never created. |
| V-242449, V-242450, V-242452, V-242453, V-242456, V-242457 | Kubelet CA, kubeconfig and config file ownership and permissions | Created by Talos under `/var/lib/kubelet` and `/system/secrets/kubelet` at fixed modes. Evidence via `talosctl list -l`. |
| V-242451, V-242466, V-242467 | Kubernetes PKI directory, certificates and keys | Held under `/system/secrets/kubernetes/`, written by Talos from the machine configuration. Evidence via `talosctl list -l`. |
| V-242454, V-242455 | `kubeadm.conf` | Not applicable on absence: Talos does not use kubeadm and never writes this file. |
| V-242459 | etcd data file permissions | `/var/lib/etcd`, written by Talos-managed etcd at fixed modes. |
| V-242460 | Administrative kubeconfig permissions | Not applicable on absence: no administrative kubeconfig is stored on the node. It is issued on demand over the Talos API, and in this repository by `talos_cluster_kubeconfig`. |

### Residual risk, stated plainly

The argument above moves the trust boundary rather than removing it. On a
conventional node, file permissions are the control protecting these secrets;
on Talos, the control is access to the Talos API, because a credential with
the `os:admin` role can read any of these files and replace the machine
configuration outright.

That makes two things elsewhere in this repository more important than any of
the 22 rules above, and an assessor is entitled to ask about both:

* `talos_api_allowed_cidr` defaults to `0.0.0.0/0`. Port 50000 administers the
  machines. It should be narrowed to an administrative range.
* The `talosconfig` this module outputs is the administrative credential for
  every node. Its handling - where Terraform state lives, who can read it, how
  it is rotated - is the compensating control that carries the weight the file
  permission rules were carrying.

### A third, if `kubernetes_talos_api_access` is enabled

`kubernetes_talos_api_access` sets `machine.features.kubernetesTalosAPIAccess`,
which lets Talos issue a Talos API client certificate to a service account in
a named namespace, carrying named roles. The default shape is `os:admin` for
`system-upgrade`, because that is what an in-cluster upgrade controller needs
in order to call the upgrade API on each node.

Read against the paragraph above, that is the whole of it: **a pod in that
namespace holds the credential the residual-risk argument is built on.** It
can read every file the 22 uncheckable rules are about, the cluster CA key
included, and it can replace the machine configuration on any node. An
assessor who accepts "the control is access to the Talos API" will ask what is
running in `system-upgrade`, and the honest answer has to cover the
controller's image provenance, who can create workloads in that namespace, and
who can write to the Flux repository that populates it - because that is now a
path to `os:admin` on every machine.

It is off by default and it is not part of `hardening`. Turning it on is a
deliberate widening, and the reason to accept it is that the alternatives are
worse rather than that it is cheap:

* Without it, a Talos version upgrade reaches running nodes only by replacing
  them - an etcd membership change per control plane node to change an OS
  image - or by a human running `talosctl upgrade` against each node with the
  administrative `talosconfig`, which is the same `os:admin` credential
  handled less carefully and with no audit trail beyond someone's shell
  history.
* With it, the credential is scoped to one namespace and one set of roles,
  issued by Talos rather than copied around, and the thing using it is
  reconciling a manifest that went through review.

Narrow it where the deployment allows. `roles` and `namespaces` are both
configurable: a controller that only ever calls the upgrade API does not
necessarily need `os:admin` on a cluster where a narrower role covers it, and
the namespace should be one nothing else is deployed into.

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
| Control plane, plus `kubelet_serving_certificates` | 12613 | 3771 |
| Worker | 2958 | 13426 |
| Worker, plus `kubelet_serving_certificates` | 3016 | 13368 |
| Karpenter worker | 3028 | 13356 |
| Karpenter worker, plus `kubelet_serving_certificates` | 3086 | 13298 |

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

One observable consequence of the skew showed up in `machine.install.image`:
the generated config pinned `ghcr.io/siderolabs/installer:v1.13.0`, the
machinery's own version, even though `talos_version` is `v1.14.1` and the AMI
is 1.14.1. Inert while nodes only ever boot from the AMI, and the wrong
installer the moment anything upgrades one in place - which is exactly what an
in-place Talos upgrade does. `cluster_patch` now overrides it with
`var.talos_version`, at no cost against the 16 KB ceiling: the two strings are
the same length.

## How a machine config change reaches running nodes

Changing a patch here - enabling `hardening` on a live cluster, for instance -
reconfigures the nodes rather than replacing them. That is not what user data
alone would do, and it is worth knowing which half does what before relying on
it for a change you care about.

The machine config is user data. Talos reads user data once, at first boot,
and thereafter its configuration lives in the `STATE` partition: a running
node will never notice that Terraform rendered a different config. So the
config is delivered over two channels, and each covers what the other cannot.

**User data covers nodes that do not exist yet.** The launch templates carry
the rendered config, so a node the autoscaling group brings up on its own - a
scale-out, a replacement after a failed health check - boots already
configured, with nothing to run by hand. It is the only channel such a node
ever sees.

**`talos_machine_configuration_apply` covers the nodes already running.**
`modules/cluster/talos/apply` applies the same rendered string to the control
plane and baseline worker nodes over the Talos API, which is what `talosctl
apply-config` does and what Talos expects. Terraform performs it and records
it, so the cluster and the state file agree - which an out-of-band
`talosctl apply-config` would not, and which the next instance refresh would
silently revert.

Two things made this awkward enough to be worth writing down:

* The resource addresses nodes by endpoint, and these nodes are launched by an
  autoscaling group with addresses Terraform does not know ahead of time. They
  are read back with `aws_instances` data sources, ordered by instance ID so
  that an index names the same machine between plans, and the resources are
  sized by the group's configured node count rather than by what the data
  source returns - because Terraform resolves `count` and `for_each` at plan
  time, and on a first apply the addresses are not known then.
* Worker nodes carry only the internal security group, so their Talos API is
  not reachable from outside the VPC. They are addressed through a control
  plane node's public address instead, which routes to them over the
  node-to-node rule.

`instance_refresh` on both autoscaling groups is consequently off by default.
Left on, a launch template change starts a rolling refresh, and the machine
config is in the launch template - so a one-line config edit replaced every
control plane and baseline worker node. With `control_plane_nodes = 1` that
is an API server outage rather than a rolling update; even at three it is a
full control plane replacement and an etcd membership change per node.
`machine_config_updates.instance_refresh` restores it for anyone who wants
strictly immutable nodes and will pay that.

### What still replaces or reboots a node

* **Changes Talos cannot apply live.** `machine_config_updates.apply_mode`
  defaults to `staged_if_needing_reboot`, which dry-runs the change and stages
  it for the next boot rather than rebooting the node. Nothing in the patches
  above needs a reboot today - API server arguments, admission control, the
  audit policy and the kubelet settings all land live, restarting only the
  affected service - but a patch that touched `machine.install`, the kernel
  command line or the disk layout would. A staged change is on the node and
  not in effect; `resolved_apply_mode` on the apply resource says which nodes
  staged, and picking it up means rebooting them one at a time. The default is
  what it is because Terraform creates the apply resources in parallel and has
  no way to serialise them, so `auto` on a reboot-requiring change would
  reboot the whole control plane at once.
* **AMI changes.** A `talos_version` bump writes a new launch template, and
  there is no in-place Talos upgrade path here - the provider has no resource
  for it. New nodes boot the new image; existing ones stay on the old one
  until they are rolled deliberately, with `aws autoscaling
  start-instance-refresh` or `instance_refresh = true`.
* **Karpenter nodes.** They are in neither autoscaling group and Terraform
  does not know their addresses, so they get the config only at boot, from
  `node-user-data` in the `karpenter-config` secret. Changing it is drift as
  far as Karpenter is concerned and it replaces the nodes - which is the right
  answer for capacity that is elastic by design, and is paced by the
  `NodePool`'s disruption budget rather than by Terraform.
* **Anything that changes the cluster's identity.** Rotating
  `talos_machine_secrets`, or changing `service-account-issuer`, is not a
  reconfiguration an apply can carry safely; the second invalidates every
  service account token until the kubelets refresh them, as the README's
  cluster identity section notes.
