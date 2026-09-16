# Enterprise Distribution for OpenBao

Digest pins, CVE triage and supply-chain policy for the ControlPlane
Enterprise hardened OpenBao container images.

The images themselves are built and hardened by ControlPlane from the
upstream OpenBao project. This repository is the downstream source of
truth for what has actually shipped.

## Layout

```
images/VERSION                          # current OpenBao version
images/<version>/enterprise-<variant>.yaml  # per-variant digest pins
.trivyignore                            # baseline CVE triage
releases/release-<minor>.trivyignore    # per-minor suppressions
vex/<minor>.json                        # baseline OpenVEX statements
.github/workflows/update-images.yaml    # refresh image pins
.github/workflows/scan-ubi.yaml         # trivy scan, ubi flavor
.github/workflows/scan-distroless.yaml  # trivy scan, distroless flavor
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
latest GitHub release tag). It resolves the multi-arch index digest for
every variant, writes `images/<version>/enterprise-<variant>.yaml`, and
opens a pull request.

This workflow needs read access to the OpenBao packages. Set the
`GHCR_READONLY` repository secret to a token that can read
`ghcr.io/controlplaneio`.
