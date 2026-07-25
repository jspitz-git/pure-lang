# TODO-46 - Windows pure-fastcgi Package

Status: Open
Branch: todo/46-windows-pure-fastcgi

## Purpose

Determine whether `pure-fastcgi` can be built and supported with a maintained
Windows FastCGI library.

## Scope

- Identify a compatible and redistributable FastCGI implementation.
- Build the native bridge and validate request, response, environment, and cleanup.
- Keep web-server-specific deployment outside the core installer.

## Task List

1. [ ] Select and reproduce a Windows FastCGI dependency.
2. [ ] Build the module and audit its runtime requirements.
3. [ ] Add a self-contained protocol smoke test.
4. [ ] Decide whether to ship or defer the package.

## Guardrails

- Do not require IIS or another full web server for basic automated tests.
- Avoid exposing a network listener beyond loopback during validation.

## Validation Plan

- Exchange one controlled FastCGI request and response with bounded timeouts.
- Run on a clean VM and inspect all native dependencies.

## Open Questions

- Which maintained FastCGI library should replace or supply the current dependency.

## Progress Log

- 2026-07-25: Created as an optional server Windows package investigation.
