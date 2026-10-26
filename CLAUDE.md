# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A single-file SigNoz (v0.137.1) stack for **Portainer Standalone Docker → Stacks → Web editor**, plus the design/rollout docs for instrumenting Carmen services with OpenTelemetry. There is no application code — the deliverable is `docker-compose.signoz-portainer.yaml`, deployed by pasting it into Portainer's editor. The target host has no SSH and no Git access; the only shell on it is Portainer → Containers → Console.

All docs, comments and README are in Thai. Commit messages use conventional prefixes (`feat:`, `fix:`, `docs:`, `chore:`), English or Thai.

## Commands

```bash
# Validate the compose file (the only "build" step)
docker compose -f docker-compose.signoz-portainer.yaml config -q

# End-to-end smoke test: send one fake span over OTLP/HTTP, then check UI → Services for "smoke-test"
./smoke-test/send-trace.sh http://<host>:40318
```

No tests, linter or package manager. The smoke test only passes after a SigNoz admin account exists (see below).

## Architecture of the stack

Startup chain, which is also the order to read logs when debugging:
`keeper` → `user-scripts` → `clickhouse` → `migrator` → `signoz` → `ingester`

- `user-scripts` downloads the `histogramQuantile` UDF binary from GitHub on **every** stack update; `clickhouse` waits on `service_completed_successfully`, so no outbound access to `github.com` + `objects.githubusercontent.com` means the whole stack stays down.
- `signoz` uses SQLite (`signoz-metastore-sqlite-0-data` — the only volume worth backing up), not Postgres like upstream.
- `ingester` gets its effective config from the OpAMP server inside `signoz`. Until the first admin account/org is created, it runs a no-op pipeline and nothing listens on 4317/4318 (shows up as connection reset).
- Every config file is inlined via top-level `configs:` + `content:` (needs Compose ≥ 2.23.1) because Portainer's web editor cannot create bind-mounted host files. Do not add a top-level `name:` — Portainer names the stack.
- Host ports are env vars: `SIGNOZ_BIND_ADDR`, `SIGNOZ_UI_PORT` (48080), `SIGNOZ_OTLP_GRPC_PORT` (40317), `SIGNOZ_OTLP_HTTP_PORT` (40318). OTLP has no auth.

## Rules when editing the compose file

- `reference/upstream/` is a verbatim Foundry `foundryctl forge` output — **never edit it by hand**; it exists only to `git diff` on upgrades. `reference/upstream/PROVENANCE.md` lists the 9 intentional deviations from upstream (memory tuning, 10× smaller collector batches, `dimensions_cache_size` 10000, disabled ClickHouse system logs, pinned tags, etc.). On upgrade, port upstream changes in by hand and keep all 9 — copying upstream config wholesale silently reverts them and reappears later as OOM under real traffic.
- Memory budget is deliberate (`mem_limit` per service, ClickHouse `max_server_memory_usage` 1 GiB with 384 MiB already reserved by mark caches — don't go below ~768 MiB without shrinking the caches too). Exit 137 = OOM kill.
- `signoz/signoz` and `signoz/signoz-otel-collector` versions move together; bump both. Image tags are listed in README "อัปเกรด".
- Compose interpolation: `$` in inline scripts must be written `$$`; `${env:...}` collector syntax breaks Compose parsing, so such values are hardcoded.

## Docs map

- `README.md` — deploy runbook, post-deploy steps (create admin immediately, then set retention), troubleshooting table, backup, upgrade.
- `docs/otel-conventions.md` — **single source of truth** for OTLP endpoints, the 12 allowed `service.name` values, resource/log attributes (`carmen.` prefix). Other Carmen repos must reference it, not duplicate values.
- `docs/dev-host-facts.md` — measured facts about the real dev host (RAM/disk, ports, exposure). Trust live observations over this file and update it when they differ. Contains the retention traps: traces/metrics TTL live in API v1, logs in v2 custom retention; `GET /api/v1/settings/ttl?type=logs` returning `-1` does **not** mean no TTL; never trust the UI as evidence — query the API.
- `docs/otel-rollout-status.md` — per-repo instrumentation status across the Carmen repos, env vars required to turn telemetry on, and traps hit during rollout.
- `docs/superpowers/specs/` and `plans/` — design and implementation plans; the 2026-08-18 spec explains the stack's design rationale.
