# TODO-45 - Windows pure-bonjour Package

Status: Open
Branch: todo/45-windows-pure-bonjour

## Purpose

Determine whether `pure-bonjour` can be legally and technically supported with
an available Windows Bonjour implementation.

## Scope

- Identify a redistributable `dns_sd` SDK/runtime and its supported architectures.
- Build the bridge and validate service registration and discovery.
- Document any external Bonjour installation requirement.

## Task List

1. [ ] Resolve SDK availability, licensing, and redistribution terms.
2. [ ] Build the module against the selected Windows implementation.
3. [ ] Add bounded loopback registration and discovery tests.
4. [ ] Decide whether to bundle, externally detect, or defer the package.

## Guardrails

- Do not copy Bonjour binaries without confirmed redistribution permission.
- Tests must not publish persistent services or rely on public networks.

## Validation Plan

- Register, discover, resolve, and remove a temporary local service.
- Verify clean behavior when the Bonjour service is absent.

## Open Questions

- Which maintained and redistributable Windows Bonjour runtime is suitable.

## Progress Log

- 2026-07-25: Created as an optional networking Windows package investigation.
