# Notices

OpenNook is open-source software. The project as a whole is licensed under the
Apache License 2.0. One subtree - the `NookSurface` notch-chrome target -
carries the MIT License instead, to preserve the license lineage of the
upstream project it is derived from. Both licenses are permissive and
compatible; this split simply keeps upstream attribution intact.

## License map

| Path | License | Coverage |
|---|---|---|
| `LICENSE` | Apache-2.0 | The whole repository, except the paths listed below |
| `LICENSE-MIT-NOOKSURFACE` | MIT | `Sources/NookSurface/` - OpenNook's modifications to the chrome |
| `ThirdPartyLicenses/DynamicNotchKit.txt` | MIT (Kai Azim) | The DynamicNotchKit upstream `NookSurface` is derived from |

## NookSurface (`Sources/NookSurface/`)

The notch chrome surface (`Nook`, `NookView`, `NookShape`, `NookPanel`,
related screen / visual-effect helpers, the supporting style / state /
transition / backdrop types, and the `NookFeedbackOverlay` peripheral-cue
layer) is derived from
[DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) by Kai Azim.

DynamicNotchKit is distributed under the MIT License (see
`ThirdPartyLicenses/DynamicNotchKit.txt`). The original kit has been
substantially trimmed and renamed: the `DynamicNotchInfo` preset family and
the `NotchlessView` floating-window renderer were removed, and the remaining
types live under the `Nook*` namespace. OpenNook then re-introduced a
non-notch floating fallback via a redesigned `NookPresentation`
(`.auto`/`.notch`/`.floating`) - a new code path with the same intent as the
upstream's removed modes, MIT-licensed under this subtree, and unrelated to
the upstream's original implementation.

OpenNook's modifications to the kit are licensed under the MIT License - see
`LICENSE-MIT-NOOKSURFACE` - preserving compatibility with the original
DynamicNotchKit license and keeping the chrome freely usable for any purpose,
including downstream forks.

## Local Feishu Island host patch (2026-10-21)

`NookSurface/Internal/NookPanel.swift`: while a native file drag is accepted over
this island, suppress the source's drag-image components so the host's waiting
portal is visible. AppKit automatically restores the source drag images when the drag leaves or
is cancelled; the host does not cache thumbnails. No file data is changed,
no thumbnail is persisted, and normal mouse hit testing stays transparent.
The existing MIT notice and upstream license remain in effect.

`NookSurface/Nook.swift`: an edge-docked compact surface now honors the host's
explicit `.expand` hover intent. Leaving cancels the pending delay; existing
hover-exit compaction and explicit presentation pins remain unchanged. This
removes the forced click between edge reveal and the host's expanded content.

2026-10-23: Delay hover-exit collapse by 650ms, recheck real panel bounds, retain keyboard-focus interaction, and replay deferred exit after focus ends. No changes to message access or authentication.

2026-10-23 build33: Keyboard focus no longer pins the island after pointer exit. Preserve the 650ms exit grace, measure visible chrome bounds rather than the half-screen transparent host panel, and poll pointer exits while the text editor retains keyboard focus. Explicit presentation pins and drag protection remain.

2026-10-24 build34: Include visible child windows in hover interaction bounds; native menu tracking temporarily defers hover exit until the menu closes. Reminder editing in the host island uses inline content instead of a detached popover. No change to message access or authentication.

2026-10-25 build38: NookLiveActivity gains an opt-in keepsCompactVisible flag (default false). Activity changes and arbiter claims both preserve compact-slot visibility while that activity exists, without expanding or pinning the panel. The host uses it only for the independently enabled Codex quota badge; camera clearance and hover-exit behavior are unchanged.

2026-10-25 build39: Replay the resident activities' compact-visibility flag when the activity subscription is first bound, so restarting with an existing quota preference restores side slots. No new presentation pin, authentication or message access.

## 2026-10-27 统一产品融合
- 从佑哥0.9.2移植 ModuleHost.setNavigationOrder，隐藏中台导航不卸载配置。
- edgeDocked支持系统已有peekFirst偏好；移出结束hover拥有的peek，点击继续完整展开。
- 收纳白色提示边缘限主体宽度65%且最多160pt，展开不套用窄遮罩。
- `NookSurface/Nook+Peek.swift`：悬浮排队开始与 compact 转换返回后检查 transition generation、任务取消及鼠标仍在区域；收回悬浮也检查当前 generation，避免快速移入移出或新操作被旧任务覆盖。程序主动触发的 peek 不要求鼠标悬停。`Tests/UnifiedProductChecks/PeekTransitionChecks.swift` 提供不创建窗口的排队取消回归检查。
