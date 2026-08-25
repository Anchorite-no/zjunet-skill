[CmdletBinding()]
param(
    [Parameter(Position=0)][ValidateSet('status','doctor','capture-udp')][string]$Command='status',
    [Parameter(Position=1)][ValidateSet('','fix')][string]$Action='',
    [string]$ConfigPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'local\topology.local.json')
)
$ErrorActionPreference='Continue'
$healthy=$true

function Show-Check([string]$Name,[bool]$Ok,[string]$Detail,[string]$Next=''){
    $color=if($Ok){'Green'}else{'Red'};$state=if($Ok){'PASS'}else{'FAIL'}
    Write-Host ('{0,-22} [{1}] {2}'-f$Name,$state,$Detail) -ForegroundColor $color
    if(-not$Ok){$script:healthy=$false;if($Next){Write-Host ('  next: '+$Next) -ForegroundColor DarkGray}}
}

function Get-Listener([int]$Port){
    $listener=Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue|Select-Object -First 1
    if(-not$listener){return $null}
    $process=Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
    return [pscustomobject]@{port=$Port;pid=$listener.OwningProcess;owner=if($process){[string]$process.ProcessName}else{'unknown'}}
}

if($Command-eq'capture-udp'){
    $directory=Join-Path $env:LOCALAPPDATA 'ZJUNetSkill\captures';[void](New-Item -ItemType Directory -Path $directory -Force)
    $owners=Get-NetUDPEndpoint -ErrorAction SilentlyContinue|Group-Object OwningProcess|Sort-Object Count -Descending|Select-Object -First 30|ForEach-Object{$process=Get-Process -Id ([int]$_.Name) -ErrorAction SilentlyContinue;[ordered]@{pid=[int]$_.Name;count=$_.Count;process=if($process){[string]$process.ProcessName}else{'exited'}}}
    $event=Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-TCPIP';Id=4266} -MaxEvents 1 -ErrorAction SilentlyContinue
    $record=[ordered]@{captured_utc=(Get-Date).ToUniversalTime().ToString('o');latest_4266=if($event){[ordered]@{record_id=$event.RecordId;time_utc=$event.TimeCreated.ToUniversalTime().ToString('o')}}else{$null};ipv4_dynamic=(& netsh interface ipv4 show dynamicport udp|Out-String);ipv6_dynamic=(& netsh interface ipv6 show dynamicport udp|Out-String);owners=$owners}
    $path=Join-Path $directory ('udp-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json');[IO.File]::WriteAllText($path,($record|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false));Write-Host "Saved local evidence: $path";exit 0
}

if(-not(Test-Path -LiteralPath $ConfigPath)){Write-Error 'Local topology config is missing. Copy config/topology.example.json to local/topology.local.json first.';exit 1}
$config=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8|ConvertFrom-Json
$checks=@(
    @('Mixed proxy',[int]$config.proxy.mixed_port,'Open or configure the existing proxy client.'),
    @('Proxy DNS',[int]$config.proxy.dns_port,'Check the generated Mihomo overlay.'),
    @('Conditional DNS',[int]$config.conditional_dns.listen_port,'Start the local conditional DNS component.'),
    @('Campus SOCKS',[int]$config.campus.socks_port,'Start ZJU Connect with local credentials.')
)

if($Command-eq'doctor'-and$Action-eq'fix'){
    $runtimePath=Join-Path (Split-Path -Parent $ConfigPath) 'runtime.local.json'
    if(-not(Test-Path -LiteralPath $runtimePath)){Write-Error 'runtime.local.json is missing. Offline fix will not guess executable paths.';exit 1}
    $runtime=Get-Content -LiteralPath $runtimePath -Raw|ConvertFrom-Json
    foreach($component in @($runtime.components)){
        if(-not(Test-Path -LiteralPath ([string]$component.executable) -PathType Leaf)){Write-Warning "Missing user-space executable for $($component.name)";continue}
        if(-not(Get-Listener ([int]$component.port))){Start-Process -FilePath ([string]$component.executable) -ArgumentList @($component.arguments) -WindowStyle Hidden|Out-Null}
    }
    Start-Sleep -Seconds 2
}

foreach($check in $checks){$listener=Get-Listener $check[1];Show-Check $check[0] ([bool]$listener) $(if($listener){"127.0.0.1:$($check[1]) owner=$($listener.owner)"}else{"127.0.0.1:$($check[1]) not listening"}) $check[2]}
$latest=Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-TCPIP';Id=4266} -MaxEvents 1 -ErrorAction SilentlyContinue
if($latest){Write-Host "UDP 4266 latest RecordId=$($latest.RecordId); run capture-udp for evidence." -ForegroundColor Yellow}else{Write-Host 'UDP 4266: no accessible event found.' -ForegroundColor Green}
if($healthy){Write-Host 'Overall: OK' -ForegroundColor Green;exit 0}else{Write-Host 'Overall: FAIL' -ForegroundColor Red;exit 1}
