[CmdletBinding()]param()
$ErrorActionPreference='SilentlyContinue'

function Get-PortOwner([int]$Port){
    $listener=Get-NetTCPConnection -LocalPort $Port -State Listen|Select-Object -First 1
    if(-not$listener){return [pscustomobject]@{ready=$false;owner=''}}
    $process=Get-Process -Id $listener.OwningProcess
    return [pscustomobject]@{ready=$true;owner=if($process){[string]$process.ProcessName}else{'unknown'}}
}

$physical=@(Get-NetAdapter -Physical|Where-Object Status -eq'Up')
$defaults=@(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0')
$result=[ordered]@{
    generated_utc=(Get-Date).ToUniversalTime().ToString('o')
    physical=[ordered]@{active_count=$physical.Count;default_route_count=$defaults.Count;needs_local_selection=($physical.Count-ne1)}
    software=[ordered]@{
        flclash=[bool](Get-Process FlClash)
        clash_verge=[bool](Get-Process|Where-Object ProcessName -Match 'clash-verge')
        mihomo=[bool](Get-Process|Where-Object ProcessName -Match 'mihomo|clash-meta')
        zju_connect=[bool](Get-Command zju-connect.exe)
        tailscale=[bool](Get-Service Tailscale)
    }
    listeners=[ordered]@{
        mixed=Get-PortOwner 7890
        proxy_dns=Get-PortOwner 1053
        conditional_dns=Get-PortOwner 1054
        campus_socks=Get-PortOwner 11080
    }
    privacy_note='This output intentionally omits addresses, GUIDs, paths, usernames, DNS values, routes, subscriptions, and command lines.'
}
$result|ConvertTo-Json -Depth 8
