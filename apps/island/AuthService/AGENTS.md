# Company authorization service
- Node built-ins only; test with `node --test *.test.cjs`.
- Company gateway owns login. Require X-Auth-User-Id on every API; no device/public bypass.
- Separate receive/archive/calendar grants, scopes fixed in source. App secrets only environment variables.
- Encrypt per-user credentials with AES-256-GCM under /data; no tokens, authorization URLs, device codes or response bodies in logs.
- Browser writes require exact Origin and X-Island-Auth. Device grants expire and bind to one user and purpose. Poll only after explicit authorization initiation.
- Do not add broad API proxy or send/delete permissions. Readiness must distinguish configured, authorized and desktop connected.
- The desktop's own authenticated company WebView may request `/api/auth/access` with the same-origin CSRF checks. Return only short-lived access token and verified identity for the selected purpose, never refresh token or application secret. Do not copy another browser's cookies. No public, shared-device-key or unauthenticated desktop handoff.
- Only synthetic tests by default. Real OAuth consent belongs to each person; developer success is not colleague verification.

- 2026-10-29：`schedule` 是新版仅查看日程的独立授权，只有 read 权限；旧 `calendar` 保留原合同以兼容已安装版本。两者分别存储、精确校验与收窄，不迁移或伪装旧读写令牌。不更换已有密钥、不改访问范围；服务变更仍需核对发布授权。

- 2026-10-27: User requested two-way todo/calendar sync. Calendar grant uses read/create/update scopes only, isolated from message tokens. No calendar delete or attendee invitation. Permission publishing and user consent must be verified separately.

- Calendar tokens may inherit previously approved application scopes. Use the official OAuth v2 refresh scope parameter to downscope before desktop handoff; retain strict exact-scope validation. Reference: https://open.feishu.cn/document/authentication-management/access-token/refresh-user-access-token . Never relabel a broad token as narrow.

- Published download links can remain in long-lived Feishu tabs. package-download-site.py generates private download-aliases.json from Distribution/released-packages.json. Missing known old files resolve to the current package, with its actual filename and a full 200 response even for Range; never append current bytes to an old partial file. Do not remove compatibility when publishing the next build.
- Website-only releases (`--web-only`) omit the DMG at the user's request. The main button opens the configured GitHub release page; private download-fallback.json lets current and known historical package URLs redirect there. Only fixed HTTPS github.com release-page URLs are accepted. Range requests in this mode return 409 with a restart instruction, never append HTML or different installer bytes to an old partial file. Full-package releases retain the existing 200/range behavior. This does not change repository visibility or prove anonymous GitHub access.
