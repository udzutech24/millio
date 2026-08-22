# Plan: Russia backend reachability

## Problem

The production app has one effective API origin, `api.iqdrop.ru`; the current RU/DE configuration resolves both regions to that origin. If a Russian network path cannot reach it, a VPN changes the egress path and succeeds, but the client has no alternate service to select.

## Required infrastructure work

- [ ] Provision a separately reachable HTTPS API endpoint for Russian networks, with TLS and the complete `/api/v1` service behind it.
- [ ] Validate DNS, certificate chain, authentication, uploads, CloudKit-dependent flows and `/runtime/server-info` from Russian mobile and Wi-Fi networks without VPN.
- [ ] Configure the production `RU_API_BASE_URL` to the proven endpoint and make `BackendEndpoints.live` resolve RU and DE independently.
- [ ] Add client tests for region selection and failover, then ship a build only after the endpoint health checks pass.

## Authorization boundary

Provisioning or changing a production endpoint/DNS/reverse proxy is an external infrastructure change and requires explicit authorization plus access to the hosting and DNS environment.
