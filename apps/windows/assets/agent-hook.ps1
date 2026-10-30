# 一切在岛 · Claude Code passive status hook (Windows).
# Port of apps/island/scripts/agent-status-helper.swift --record / --statusline.
# Records only session state and quota windows. Never prompts, tool input, paths or output.
# Always exits 0 so it can never block or decide anything inside Claude Code.
param([string]$Mode = '', [string]$Provider = '')
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:APPDATA 'FeishuIsland\AgentStatus'

function Read-Stdin {
  $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)
  $text = $reader.ReadToEnd()
  if ($text.Length -gt 1048576) { return $null }
  return $text
}
function Get-Policy {
  $file = Join-Path $root 'policy.json'
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return $null }
  if ((Get-Item -LiteralPath $file).Length -gt 4096) { return $null }
  return (Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json)
}
function Write-Atomic([string]$path, [string]$text) {
  $dir = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $temp = $path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
  [System.IO.File]::WriteAllText($temp, $text, (New-Object System.Text.UTF8Encoding($false)))
  Move-Item -LiteralPath $temp -Destination $path -Force
}
function Get-Sha256([string]$value) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($value))
  return -join ($bytes | ForEach-Object { $_.ToString('x2') })
}
function Now { return [double]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) / 1000 }

try {
  if ($Provider -ne 'claude') { exit 0 }
  if ($Mode -eq 'record') {
    $policy = Get-Policy
    if ($null -eq $policy -or -not $policy.enabled -or -not ($policy.visibleIDs -contains 'claude')) { exit 0 }
    $raw = Read-Stdin; if ($null -eq $raw) { exit 0 }
    $data = $raw | ConvertFrom-Json
    $session = [string]$data.session_id
    if ([string]::IsNullOrEmpty($session) -or [System.Text.Encoding]::UTF8.GetByteCount($session) -gt 256) { exit 0 }
    $event = [string]$data.hook_event_name
    $id = Get-Sha256 $session
    $folder = Join-Path $root 'claude'
    $file = Join-Path $folder ($id + '.json')
    $previous = $null
    if (Test-Path -LiteralPath $file -PathType Leaf) { try { $previous = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $previous = $null } }
    $tool = ([string]$data.tool_name).ToLowerInvariant().Replace('_', '').Replace('-', '')
    $state = 'working'; $reason = $null
    switch ($event) {
      'UserPromptSubmit' { }
      'PreToolUse' {
        if (@('askuserquestion', 'askfollowupquestion', 'picklocation') -contains $tool) { $state = 'waiting'; $reason = 'input' }
        elseif ($tool -eq 'exitplanmode') { $state = 'waiting'; $reason = 'approval' }
      }
      'PermissionRequest' { $state = 'waiting'; if (@('askuserquestion', 'askfollowupquestion') -contains $tool) { $reason = 'input' } else { $reason = 'approval' } }
      'Notification' {
        $type = [string]$data.notification_type
        if ($type -eq 'permission_prompt') { $state = 'waiting'; if ($previous -and $previous.state -eq 'waiting' -and $previous.attentionReason) { $reason = $previous.attentionReason } else { $reason = 'approval' } }
        elseif (@('elicitation_dialog', 'agent_needs_input') -contains $type) { $state = 'waiting'; $reason = 'input' }
        elseif (@('elicitation_complete', 'elicitation_response') -contains $type) { }
        else { exit 0 }
      }
      'Elicitation' { $state = 'waiting'; $reason = 'input' }
      'PostToolUse' { } 'PostToolUseFailure' { } 'ElicitationResult' { }
      'Stop' { $state = 'completed' }
      'StopFailure' { $state = 'failed' }
      'SessionEnd' { if (-not ($previous -and ($previous.state -eq 'working' -or $previous.state -eq 'waiting'))) { exit 0 }; $state = 'failed' }
      default { exit 0 }
    }
    $attention = $null
    if ($state -eq 'waiting') {
      if ($previous -and $previous.state -eq 'waiting' -and $previous.attentionReason -eq $reason -and $previous.attentionID) { $attention = [string]$previous.attentionID } else { $attention = [guid]::NewGuid().ToString() }
    }
    $completion = $null; if ($state -eq 'completed') { $completion = [guid]::NewGuid().ToString() } elseif ($previous) { $completion = $previous.completionID }
    $start = $null; if ($event -eq 'UserPromptSubmit') { $start = [guid]::NewGuid().ToString() } elseif ($previous) { $start = $previous.startID }
    $record = [ordered]@{ id = $id; state = $state; updatedAt = (Now); completionID = $completion; startID = $start; attentionID = $attention; attentionReason = $reason }
    Write-Atomic $file ($record | ConvertTo-Json -Compress)
    exit 0
  }
  if ($Mode -eq 'statusline') {
    $raw = Read-Stdin; if ($null -eq $raw) { exit 0 }
    $policy = Get-Policy
    if ($policy -and $policy.enabled -and ($policy.visibleIDs -contains 'claude')) {
      try {
        $data = $raw | ConvertFrom-Json
        $now = Now; $quotas = @()
        foreach ($pair in @(@('five_hour', '5小时额度'), @('seven_day', '周额度'))) {
          $w = $data.rate_limits.($pair[0])
          if ($null -ne $w -and $null -ne $w.used_percentage -and $null -ne $w.resets_at) {
            $used = [double]$w.used_percentage; $reset = [double]$w.resets_at
            if ($used -ge 0 -and $used -le 100 -and $reset -gt $now -and $reset -lt 253402300800) {
              $quotas += [ordered]@{ id = $pair[0]; label = $pair[1]; remainingPercent = 100 - $used; resetsAt = $reset; updatedAt = $now }
            }
          }
        }
        if ($quotas.Count -gt 0) { Write-Atomic (Join-Path $root 'claude-quota.json') (@{ quotas = $quotas } | ConvertTo-Json -Compress -Depth 4) }
      } catch { }
    }
    # Preserve the user's original status line renderer with identical input.
    $forward = Join-Path $root 'claude-statusline-forward.json'
    if (Test-Path -LiteralPath $forward -PathType Leaf) {
      $command = [string](Get-Content -LiteralPath $forward -Raw -Encoding UTF8 | ConvertFrom-Json).command
      if (-not [string]::IsNullOrEmpty($command) -and -not $command.Contains('agent-hook.ps1')) {
        $bash = $env:CLAUDE_CODE_GIT_BASH_PATH
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        if ($bash -and (Test-Path -LiteralPath $bash)) { $psi.FileName = $bash; $psi.Arguments = '-c "' + $command.Replace('"', '\"') + '"' }
        else { $psi.FileName = $env:ComSpec; $psi.Arguments = '/d /s /c "' + $command + '"' }
        $psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.StandardInput.Write($raw); $p.StandardInput.Close()
        [Console]::Out.Write($p.StandardOutput.ReadToEnd()); $p.WaitForExit(5000) | Out-Null
      }
    }
    exit 0
  }
} catch { exit 0 }
exit 0
