# Company authorization service
- Node built-ins only; test with `node --test *.test.cjs`.
- Company gateway owns login. Require X-Auth-User-Id on every API; no device/public bypass.
- Separate receive/archive/calendar grants, scopes fixed in source. App secrets only environment variables.
- Encrypt per-user credentials with AES-256-GCM under /data; no tokens, authorization URLs, device codes or response bodies in logs.
- Browser writes require exact Origin and X-Island-Auth. Device grants expire and bind to one user and purpose. Poll only after explicit authorization initiation.
- Do not add broad API proxy or send/delete permissions. Readiness must distinguish configured, authorized and desktop connected.
- The desktop's own authenticated company WebView may request `/api/auth/access` with the same-origin CSRF checks. Return only short-lived access token and verified identity for the selected purpose, never refresh token or application secret. Do not copy another browser's cookies. No public, shared-device-key or unauthenticated desktop handoff.
- Only synthetic tests by default. Real OAuth consent belongs to each person; developer success is not colleague verification.

- 2026-10-27: User requested two-way todo/calendar sync. Calendar grant uses read/create/update scopes only, isolated from message tokens. No calendar delete or attendee invitation. Permission publishing and user consent must be verified separately.

- Calendar tokens may inherit previously approved application scopes. Use the official OAuth v2 refresh scope parameter to downscope before desktop handoff; retain strict exact-scope validation. Reference: https://open.feishu.cn/document/authentication-management/access-token/refresh-user-access-token . Never relabel a broad token as narrow.
