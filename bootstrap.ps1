[CmdletBinding()]
param(
    [Parameter(Position=0)][ValidateSet('plan','build','verify')][string]$Stage='plan',
    [string]$ConfigPath=(Join-Path $PSScriptRoot 'config\topology.example.json'),
    [string]$OutputDirectory=(Join-Path $PSScriptRoot 'out')
)

$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSCommandPath
$expectedOutput=[IO.Path]::GetFullPath((Join-Path $root 'out'))
if(-not[IO.Path]::GetFullPath($OutputDirectory).Equals($expectedOutput,[StringComparison]::OrdinalIgnoreCase)){throw'OutputDirectory is fixed to the repository out directory.'}

function Read-Config([string]$Path){
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50
}

function Find-Placeholders($Value,[string]$Path='$'){
    $found=[Collections.Generic.List[string]]::new()
    if($null-eq$Value){return @($found)}
    if($Value-is[string]){if($Value-match'<[^>]+>'){$found.Add($Path)};return @($found)}
    if($Value-is[Collections.IEnumerable]-and$Value-isnot[string]){$index=0;foreach($item in $Value){foreach($entry in Find-Placeholders $item "$Path[$index]"){$found.Add($entry)};$index++};return @($found)}
    foreach($property in $Value.PSObject.Properties){foreach($entry in Find-Placeholders $property.Value "$Path.$($property.Name)"){$found.Add($entry)}}
    return @($found)
}

function Get-Listener([int]$Port){
    $listener=Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue|Select-Object -First 1
    if(-not$listener){return [pscustomobject]@{ready=$false;owner=''}}
    $process=Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
    return [pscustomobject]@{ready=$true;owner=if($process){[string]$process.ProcessName}else{'unknown'}}
}

$config=Read-Config $ConfigPath
$missing=@(Find-Placeholders $config|Sort-Object -Unique)

if($Stage-eq'plan'){
    $mixed=Get-Listener ([int]$config.proxy.mixed_port)
    $campus=Get-Listener ([int]$config.campus.socks_port)
    [pscustomobject]@{
        schema_version=1
        config_is_local=([IO.Path]::GetFullPath($ConfigPath)-notlike([IO.Path]::GetFullPath((Join-Path $root 'config\topology.example.json'))))
        missing_fields=$missing
        detected=[pscustomobject]@{
            mixed_listener=$mixed.ready
            mixed_owner=$mixed.owner
            campus_socks=$campus.ready
            flclash=[bool](Get-Process FlClash -ErrorAction SilentlyContinue)
            clash_verge=[bool](Get-Process -ErrorAction SilentlyContinue|Where-Object ProcessName -Match 'clash-verge')
            zju_connect=[bool](Get-Command zju-connect.exe -ErrorAction SilentlyContinue)
            tailscale=[bool](Get-Service Tailscale -ErrorAction SilentlyContinue)
        }
        ready_to_build=($missing.Count-eq0)
        next=if($missing.Count){'Copy the example to local/topology.local.json and fill only the listed fields locally.'}else{'Run bootstrap.ps1 build, inspect out/replication-plan.json, then follow docs/replication-guide.md.'}
    }|ConvertTo-Json -Depth 8
    exit 0
}

if($missing.Count){throw('Unresolved local fields: '+($missing-join', '))}
if(Test-Path -LiteralPath $OutputDirectory){Remove-Item -LiteralPath $OutputDirectory -Recurse -Force}
[void](New-Item -ItemType Directory -Path $OutputDirectory)

$exclude=@([string]$config.routing.physical_lan_cidr)
if($config.routing.tailnet_cidr){$exclude+=[string]$config.routing.tailnet_cidr}
$topology=[ordered]@{
    proxy=$config.proxy
    campus=$config.campus
    conditional_dns=[ordered]@{
        listen_port=[int]$config.conditional_dns.listen_port
        health_port=[int]$config.conditional_dns.health_port
        public_servers=@($config.conditional_dns.public_servers)
        campus_servers=@($config.conditional_dns.campus_servers)
        campus_suffixes=@($config.conditional_dns.campus_suffixes)
        vpn_bootstrap_names=@($config.conditional_dns.vpn_bootstrap_names)
        physical_dns=@($config.conditional_dns.physical_dns)
        proxy_doh=@($config.conditional_dns.proxy_doh)
    }
    routing=[ordered]@{
        exclude_cidrs=$exclude
        campus_cidrs=@($config.routing.campus_cidrs)
        tailnet_dns=[string]$config.routing.tailnet_dns
    }
}
$template=Get-Content -LiteralPath (Join-Path $root 'templates\mihomo-overlay.js') -Raw -Encoding UTF8
$overlay=$template.Replace('__TOPOLOGY_JSON__',($topology|ConvertTo-Json -Compress -Depth 20))
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'managed-overlay.js'),$overlay,[Text.UTF8Encoding]::new($false))

$resolver=[ordered]@{
    listen="127.0.0.1:$($config.conditional_dns.listen_port)"
    health_listen="127.0.0.1:$($config.conditional_dns.health_port)"
    public=[ordered]@{servers=@($config.conditional_dns.public_servers);via_socks="127.0.0.1:$($config.proxy.mixed_port)"}
    campus=[ordered]@{servers=@($config.conditional_dns.campus_servers);via_socks="127.0.0.1:$($config.campus.socks_port)"}
    fallback_rule='campus only after every public upstream returns NXDOMAIN or NODATA'
}
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'conditional-dns.json'),($resolver|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))

$plan=[ordered]@{
    generated_utc=(Get-Date).ToUniversalTime().ToString('o')
    actions=@(
        'Reuse a working local proxy client and subscription; do not export the subscription.',
        'Install ZJU Connect from its official release if missing; collect credentials locally.',
        'Run ZJU Connect as loopback SOCKS only; keep its own TUN/add-route/dns-hijack disabled.',
        'Attach managed-overlay.js through the selected client mechanism.',
        'Enable the proxy client TUN settings shown in docs/replication-guide.md.',
        'Start a conditional DNS implementation using conditional-dns.json.',
        'Run bootstrap verify and scripts/zjunet.ps1 doctor.'
    )
    protected_no_change=@('existing proxy Core','TUN driver without explicit approval','dynamic port ranges','firewall','static routes','gateway','unrelated adapters')
    ports=[ordered]@{mixed=$config.proxy.mixed_port;proxy_dns=$config.proxy.dns_port;conditional_dns=$config.conditional_dns.listen_port;conditional_health=$config.conditional_dns.health_port;campus_socks=$config.campus.socks_port}
}
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'replication-plan.json'),($plan|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))

if($Stage-eq'build'){Write-Host "Generated sanitized local artifacts in $OutputDirectory" -ForegroundColor Green;exit 0}

if($overlay-match'<[^>]+>' -or (Get-Content (Join-Path $OutputDirectory 'conditional-dns.json') -Raw)-match'<[^>]+>'){throw'Generated output still contains placeholders.'}
if(Get-Command node.exe -ErrorAction SilentlyContinue){& node.exe --check (Join-Path $OutputDirectory 'managed-overlay.js');if($LASTEXITCODE-ne0){throw'Generated overlay failed JavaScript syntax validation.'}}
& (Join-Path $root 'scripts\zjunet.ps1') doctor -ConfigPath $ConfigPath
exit $LASTEXITCODE
