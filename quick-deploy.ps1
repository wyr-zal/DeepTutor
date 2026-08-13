$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0
Set-StrictMode -Version Latest

$ProjectRoot = 'E:/ProjectOwn/DeepTutor'
$Server = 'root@47.110.237.209'
$Domain = 'https://deeptutor.cliproxy.com.cn'
$TarPath = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot 'deeptutor.tar'))
$TarDir = Split-Path -Parent $TarPath
$TarName = Split-Path -Leaf $TarPath
$DockerTempPattern = Join-Path $TarDir ".tmp-$TarName*"
$MinFreeGB = 6
$GitExeCandidates = @(
  (Join-Path ${env:ProgramFiles} 'Git\cmd\git.exe'),
  'D:\Develop\Git\Git\cmd\git.exe',
  'C:\Program Files\Git\cmd\git.exe'
)
$GitExe = $GitExeCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
$OpenSshDir = Join-Path $env:WINDIR 'System32\OpenSSH'
$SshExe = Join-Path $OpenSshDir 'ssh.exe'
$ScpExe = Join-Path $OpenSshDir 'scp.exe'
if (-not (Test-Path -LiteralPath $SshExe) -or -not (Test-Path -LiteralPath $ScpExe)) {
  throw "未找到 Windows OpenSSH 客户端：$OpenSshDir"
}

# 每次执行默认都会基于当前源码构建一个新镜像；如需固定 tag，可手动改成非空字符串。
$Tag = $null

function Assert-LastExitCode([string]$Message) {
  if ($LASTEXITCODE -ne 0) { throw "$Message，退出码：$LASTEXITCODE" }
}

function Assert-DockerReady {
  docker version *> $null
  if ($LASTEXITCODE -ne 0) {
    throw 'Docker Desktop 未启动或 Docker Engine 不可用。请先启动 Docker Desktop，等鲸鱼图标显示 Running 后再重试。'
  }
}

function Invoke-DockerBuild([string]$ImageTag) {
  # In some Windows PowerShell hosts, invoking docker directly can detach
  # buildx before $LASTEXITCODE is updated. Start-Process -Wait keeps the
  # deployment sequence strictly synchronous.
  $DockerExe = (Get-Command docker -ErrorAction Stop).Source
  if (-not $DockerExe.EndsWith('.exe', [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath "$DockerExe.exe")) {
    $DockerExe = "$DockerExe.exe"
  }
  $Args = @('build', '--platform', 'linux/amd64', '--target', 'production', '-t', $ImageTag, '.')
  $Process = Start-Process -FilePath $DockerExe -ArgumentList $Args -WorkingDirectory $ProjectRoot -Wait -PassThru -NoNewWindow
  if ($Process.ExitCode -ne 0) { throw "Docker 镜像构建失败，退出码：$($Process.ExitCode)" }
}

function Invoke-DockerSave([string]$ImageTag, [string]$OutputPath) {
  $DockerExe = (Get-Command docker -ErrorAction Stop).Source
  if (-not $DockerExe.EndsWith('.exe', [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath "$DockerExe.exe")) {
    $DockerExe = "$DockerExe.exe"
  }
  $Args = @('save', '--output', $OutputPath, $ImageTag)
  $Process = Start-Process -FilePath $DockerExe -ArgumentList $Args -WorkingDirectory $ProjectRoot -Wait -PassThru -NoNewWindow
  if ($Process.ExitCode -ne 0) { throw "docker save 失败，退出码：$($Process.ExitCode)" }
}

function Assert-FreeSpace([string]$Path, [int]$MinGB) {
  $Root = [System.IO.Path]::GetPathRoot($Path)
  $DriveName = $Root.Substring(0,1)
  $Drive = Get-PSDrive -Name $DriveName
  $FreeGB = [math]::Round($Drive.Free / 1GB, 2)
  if ($FreeGB -lt $MinGB) {
    throw "$Root 可用空间不足：${FreeGB}GB，至少需要 ${MinGB}GB 用于导出 deeptutor.tar"
  }
  Write-Host "磁盘空间 OK：$Root 可用 ${FreeGB}GB" -ForegroundColor Green
}

function Assert-FileReady([string]$Path, [string]$Message) {
  if (-not (Test-Path -LiteralPath $Path)) { throw "$Message：文件不存在：$Path" }
  $Item = Get-Item -LiteralPath $Path
  if ($Item.Length -le 0) { throw "$Message：文件为空：$Path" }
  return $Item
}

function Repair-DockerSaveTempFile([string]$FinalPath, [string]$TempPattern, [datetime]$StartedAt) {
  if (Test-Path -LiteralPath $FinalPath) { return }

  $Candidates = Get-ChildItem -Path $TempPattern -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Length -gt 0 -and $_.LastWriteTime -ge $StartedAt.AddSeconds(-10) } |
    Sort-Object LastWriteTime -Descending

  if (-not $Candidates) { return }
  if (@($Candidates).Count -gt 1) {
    $Names = ($Candidates | Select-Object -ExpandProperty Name) -join ', '
    throw "docker save 留下多个候选临时文件，无法自动判断：$Names"
  }

  $Candidate = $Candidates[0]
  Write-Host "检测到 Docker 已写出隐藏临时 tar，准备自动改名：$($Candidate.Name) -> $(Split-Path -Leaf $FinalPath)" -ForegroundColor Yellow

  $LastLength = -1
  for ($i = 1; $i -le 30; $i++) {
    $Current = Get-Item -LiteralPath $Candidate.FullName -ErrorAction Stop
    if ($Current.Length -eq $LastLength) { break }
    $LastLength = $Current.Length
    Start-Sleep -Milliseconds 500
  }

  $LastError = $null
  for ($i = 1; $i -le 20; $i++) {
    try {
      Move-Item -LiteralPath $Candidate.FullName -Destination $FinalPath -Force -ErrorAction Stop
      Write-Host "隐藏临时 tar 已改名为：$FinalPath" -ForegroundColor Green
      return
    } catch {
      $LastError = $_.Exception.Message
      Start-Sleep -Seconds 1
    }
  }

  throw "隐藏临时 tar 改名失败，文件可能仍被占用：$LastError"
}

function Invoke-RemoteBash([string]$ServerName, [string]$Script, [string]$FailureMessage) {
  $LfScript = $Script -replace "`r`n", "`n" -replace "`r", "`n"
  $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  $Bytes = $Utf8NoBom.GetBytes($LfScript)

  $Process = New-Object System.Diagnostics.Process
  $Process.StartInfo.FileName = $SshExe
  # Windows PowerShell 5.1 的 ProcessStartInfo 没有 ArgumentList，使用 Arguments 兼容写法。
  $Process.StartInfo.Arguments = "$ServerName bash -s"
  $Process.StartInfo.RedirectStandardInput = $true
  $Process.StartInfo.RedirectStandardOutput = $false
  $Process.StartInfo.RedirectStandardError = $false
  $Process.StartInfo.UseShellExecute = $false
  [void]$Process.Start()
  $Process.StandardInput.BaseStream.Write($Bytes, 0, $Bytes.Length)
  $Process.StandardInput.Close()
  $Process.WaitForExit()
  if ($Process.ExitCode -ne 0) { throw "$FailureMessage，退出码：$($Process.ExitCode)" }
}

try {
cd $ProjectRoot

Write-Host '== 0/8 检查 Docker Engine ==' -ForegroundColor Cyan
Assert-DockerReady

if (-not $Tag) {
  $VersionLine = Select-String -LiteralPath (Join-Path $ProjectRoot 'deeptutor/__version__.py') -Pattern '__version__\s*=\s*"([^"]+)"' | Select-Object -First 1
  $Version = if ($VersionLine -and $VersionLine.Matches.Count -gt 0) { $VersionLine.Matches[0].Groups[1].Value } else { 'local-patch' }
  $SafeVersion = $Version -replace '[^0-9A-Za-z_.-]', '-'
  if ($GitExe) {
    $GitShort = & $GitExe rev-parse --short HEAD 2>$null
  } else {
    $GitShort = 'nogit'
  }
  if ($LASTEXITCODE -ne 0 -or -not $GitShort) { $GitShort = 'nogit' }
  $Tag = "deeptutor:custom-$(Get-Date -Format yyyyMMdd-HHmm)-v$SafeVersion-$GitShort"
}

Write-Host "== 1/8 本地构建新镜像：$Tag ==" -ForegroundColor Cyan
Invoke-DockerBuild $Tag

Write-Host '== 2/8 校验新镜像版本 ==' -ForegroundColor Cyan
docker run --rm --entrypoint /bin/sh $Tag -lc 'cat /app/deeptutor/__version__.py | grep __version__ && grep -R "NEXT_PUBLIC_APP_VERSION" -n /app/web/server.js /app/web/.next/required-server-files.json 2>/dev/null | head -5'
Assert-LastExitCode '新镜像版本校验失败'

Write-Host "== 3/8 导出镜像：$Tag ==" -ForegroundColor Cyan
Assert-FreeSpace $TarPath $MinFreeGB
Remove-Item $TarPath -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path $DockerTempPattern -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
$SaveStartedAt = Get-Date
Invoke-DockerSave $Tag $TarPath
Repair-DockerSaveTempFile $TarPath $DockerTempPattern $SaveStartedAt
$SavedTar = Assert-FileReady $TarPath 'docker save 未生成有效 tar 包'
$SavedTar | Select-Object FullName,@{N='SizeMB';E={[math]::Round($_.Length/1MB,2)}}

Write-Host '== 4/8 上传 tar 到服务器 /tmp/ ==' -ForegroundColor Cyan
& $ScpExe -C $TarPath "${Server}:/tmp/deeptutor.tar"
Assert-LastExitCode '上传 deeptutor.tar 失败'

Write-Host '== 5/8 远程加载镜像并切换 docker-compose.yml ==' -ForegroundColor Cyan
$RemoteDeployLines = @(
  'set -euo pipefail',
  "TAG='$Tag'",
  'APP_DIR=/opt/deeptutor',
  'TAR=/tmp/deeptutor.tar',
  'COMPOSE=${APP_DIR}/docker-compose.yml',
  'cd "${APP_DIR}"',
  'echo "加载镜像：${TAG}"',
  'docker load -i "${TAR}"',
  'docker image inspect "${TAG}" >/dev/null',
  'if [ -f "${COMPOSE}" ]; then cp "${COMPOSE}" "${COMPOSE}.bak-$(date +%Y%m%d-%H%M%S)"; fi',
  'cat > "${COMPOSE}" <<EOF',
  'services:',
  '  deeptutor:',
  '    image: ${TAG}',
  '    pull_policy: never',
  '    container_name: deeptutor',
  '    restart: unless-stopped',
  '    environment:',
  '      - TZ=Asia/Shanghai',
  '    ports:',
  '      - "127.0.0.1:8001:8001"',
  '      - "127.0.0.1:3782:3782"',
  '    volumes:',
  '      # v1.5.11 persists system settings, users, partners and channel config under data/.',
  '      - ./data:/app/data',
  '    healthcheck:',
  '      test: ["CMD", "curl", "-f", "http://localhost:8001/"]',
  '      interval: 30s',
  '      timeout: 10s',
  '      retries: 3',
  '      start_period: 60s',
  'EOF',
  'echo "校验 docker-compose.yml"',
  'docker compose -f "${COMPOSE}" config >/dev/null',
  'echo "YAML OK"',
  'echo "重建容器：必须 down + up，不使用 restart"',
  'docker compose down',
  'docker compose up -d'
)
$RemoteDeploy = $RemoteDeployLines -join "`n"
Invoke-RemoteBash $Server $RemoteDeploy '远程加载镜像、切换 compose 或重建容器失败'

Write-Host '== 6/8 远程查看启动日志 ==' -ForegroundColor Cyan
$RemoteLogs = @(
  'set -e',
  'cd /opt/deeptutor',
  'sleep 12',
  'docker compose ps',
  'docker compose logs --tail=40 deeptutor'
) -join "`n"
Invoke-RemoteBash $Server $RemoteLogs '读取远程容器日志失败'

Write-Host '== 7/8 远程冒烟测试 ==' -ForegroundColor Cyan
$RemoteSmoke = @(
  'set -e',
  'for i in $(seq 1 40); do',
  '  if curl -fsS http://127.0.0.1:8001/ >/tmp/deeptutor-smoke-root.log 2>&1 && curl -fsS http://127.0.0.1:8001/api/v1/system/status >/tmp/deeptutor-smoke-status.log 2>&1; then',
  '    echo "本机后端冒烟通过"',
  '    break',
  '  fi',
  '  if [ "$i" -eq 40 ]; then',
  '    echo "本机后端 80 秒内未响应，输出最近日志"',
  '    cd /opt/deeptutor && docker compose logs --tail=120 deeptutor || true',
  '    exit 1',
  '  fi',
  '  sleep 2',
  'done',
  "curl -k -fsSI '$Domain' >/tmp/deeptutor-smoke-domain-head.log",
  "curl -k -fsS '$Domain/api/v1/system/status' >/tmp/deeptutor-smoke-domain-status.log",
  'echo "HTTPS 冒烟通过"',
  'head -20 /tmp/deeptutor-smoke-domain-head.log',
  'rm -f /tmp/deeptutor.tar',
  'echo "已清理 /tmp/deeptutor.tar"'
) -join "`n"
Invoke-RemoteBash $Server $RemoteSmoke '远程冒烟测试失败'

Write-Host '== 8/8 本地确认线上首页响应（可选） ==' -ForegroundColor Cyan
try {
  Invoke-WebRequest -Uri $Domain -Method Head -UseBasicParsing -TimeoutSec 15 | Select-Object StatusCode,StatusDescription
} catch {
  Write-Host "本地 HEAD 检查失败，但远程 HTTPS 冒烟已通过，不判定部署失败：$($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host '== 发布完成 ==' -ForegroundColor Green
Write-Host "已部署镜像：$Tag" -ForegroundColor Green
Write-Host "线上地址：$Domain" -ForegroundColor Green
Write-Host '浏览器最终验收：F12 → Network 勾 Disable cache → Ctrl+Shift+R 硬刷新。' -ForegroundColor Yellow
}
catch {
  Write-Host ''
  Write-Host "一键构建部署失败，已停止执行：$($_.Exception.Message)" -ForegroundColor Red
  Write-Host '排查建议：先确认 Docker Desktop 已启动、docker build 能完成、SSH/SCP 可连接服务器；失败后不要手动继续执行后续片段。' -ForegroundColor Yellow
  exit 1
}
