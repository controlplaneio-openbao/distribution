# Enterprise Distribution for OpenBao

[![Vulnerability scan - UBI](https://github.com/controlplaneio-openbao/distribution/actions/workflows/scan-ubi.yaml/badge.svg)](https://github.com/controlplaneio-openbao/distribution/actions/workflows/scan-ubi.yaml)
[![Vulnerability scan - Distroless](https://github.com/controlplaneio-openbao/distribution/actions/workflows/scan-distroless.yaml/badge.svg)](https://github.com/controlplaneio-openbao/distribution/actions/workflows/scan-distroless.yaml)
[![SLSA 3](https://slsa.dev/images/gh-badge-level3.svg)](https://control-plane.io/enterprise-for-openbao)

[ControlPlane Enterprise for OpenBao](https://control-plane.io/enterprise-for-openbao)
is a comprehensive solution for organizations seeking
to adopt open source secrets management with enterprise-grade assurance.

Built on top of the [OpenSSF](https://openssf.org) OpenBao project,
the ControlPlane distribution provides a secure, scalable, and enterprise-ready platform
for managing secrets, machine identities, and encryption keys across
multi-tenant Kubernetes clusters and beyond.

The ControlPlane distribution is offered on a
[yearly subscription basis](https://control-plane.io/enterprise-for-openbao) and includes
enterprise-grade support services for running OpenBao in production.

> [!TIP]
> [Connect with us](https://control-plane.io/contact/) to explore how the enterprise
> distribution aligns with your unique requirements. Together, we'll develop and review a plan
> tailored to your challenges, goals, and budget.

## Documentation

ControlPlane offers a seamless migration path from HashiCorp Vault to the enterprise
distribution with minimal disruption to secrets availability. The hardened container
images provided by ControlPlane are fully API compatible with upstream OpenBao.

For more information, see the following documentation:

- [Enterprise Distribution Overview](https://control-plane.io/enterprise-for-openbao)
- [Why We Support OpenBao](https://control-plane.io/posts/why-we-support-openbao)
- [HashiCorp Vault Exit Guide](https://control-plane.io/posts/vault-exit-guide)
- [Upstream OpenBao Documentation](https://openbao.org/docs/)

## Repository contents

This repository is the downstream source of truth for the hardened container
images built and published by ControlPlane from the upstream OpenBao project.

```
images/VERSION                              # current OpenBao version
images/<version>/enterprise-<variant>.yaml  # per-variant digest pins
.trivyignore                                # baseline CVE triage
releases/release-<minor>.trivyignore        # per-minor suppressions
vex/<minor>.json                            # baseline OpenVEX statements
.github/workflows/update-images.yaml        # refresh image pins
.github/workflows/scan-ubi.yaml             # trivy scan, ubi flavor
.github/workflows/scan-distroless.yaml      # trivy scan, distroless flavor
```

Variants: `ubi`, `ubi-fips`, `distroless`, `distroless-fips`.

## Scanning

Two scheduled/manual trivy scans cover the two distinct image bases:
**Vulnerability scan - UBI** and **Vulnerability scan - Distroless**. They
scan `ghcr.io/controlplaneio/<variant>/openbao:<images/VERSION>` using
`.trivyignore` plus `releases/release-<minor>.trivyignore`.

The `-fips` variants are intentionally not scanned separately: they differ
from their non-fips counterpart only by the embedded Go FIPS module and
share the same OS and library packages (the same reason flux does not scan
`distroless-fips`).

Both the scans and **Update images** need the `GHCR_READONLY` repository
secret set to a token that can read `ghcr.io/controlplaneio`. The scan
workflows post CVE alerts to Zulip on failure (stream `Distribution`,
topic `cve-alerts`) using the `ZULIP_EMAIL`, `ZULIP_API_KEY` and
`ZULIP_ORGANIZATION_URL` repository secrets.

## Updating image pins

After a build round publishes new digests in
`ghcr.io/controlplaneio/<variant>/openbao:<version>`, dispatch the
**Update images** workflow with the target `version` (defaults to the
current version in `images/VERSION`). It resolves the multi-arch index
digest for every variant, writes `images/<version>/enterprise-<variant>.yaml`,
and opens a pull request.

This workflow needs read access to the OpenBao packages. Set the
`GHCR_READONLY` repository secret to a token that can read
`ghcr.io/controlplaneio`.
