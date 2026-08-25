# Instructions for AI implementers

## Project intent

This repository is a sanitized handoff of a working Windows network design. Reproduce the architecture on the target machine; do not copy machine-specific values from another computer and do not invent missing campus facts.

## Required workflow

1. Read `README.md`, `docs/architecture.md`, and `docs/replication-guide.md`.
2. Run `scripts/Get-NetworkInventory.ps1` and `bootstrap.ps1 plan`. These commands are read-only.
3. Report discovered capabilities and missing field names without printing private addresses, GUIDs, usernames, profile paths, or subscription content.
4. Ask the user to put machine-local values in `local/topology.local.json` and credentials in the official client or a local protected credential store.
5. Run `bootstrap.ps1 build` and inspect `out/replication-plan.json` before changing applications.
6. Install missing public software from its official release source. Reuse installed FlClash, Clash Verge Rev, Mihomo, ZJU Connect, and Tailscale when available.
7. Attach the generated overlay through the supported client mechanism, restart only the affected component, then run `bootstrap.ps1 smoke` and the full manual verification matrix. Smoke success is not end-to-end success.

## Secret boundary

- Never ask the user to paste a ZJU password, subscription URL, proxy node, UUID, token, cookie, private key, client database, recovery bundle, log, or packet capture into chat.
- Never commit `local/`, `out/`, profiles, databases, generated effective configs, logs, captures, executables, or recovery files.
- Treat the existing subscription as opaque. The design needs only the local mixed listener, normally `127.0.0.1:7890`.

## Safety boundary

- Never replace, patch, roll back, or switch an existing proxy Core without explicit approval for that exact operation.
- Never install or replace a TUN driver, change dynamic port ranges, static routes, gateways, firewall rules, registry network policy, or an unrelated adapter without explicit approval.
- `doctor` is read-only.
- `doctor fix` may only restart allowlisted user-space processes from the local runtime file. It must not silently expand its authority.
- Core hash drift, UDP 4266 events, and protected system settings are report-only evidence.

## Success criteria

Do not claim success from a green process list alone. Verify each branch separately: physical bootstrap, mixed proxy, proxy DNS, conditional DNS over TCP and UDP, campus SOCKS, campus DNS, campus HTTP through SOCKS/mixed/TUN, LAN/Tailnet bypass, and a multi-resource public page.
