[CmdletBinding()]param([string]$Root='')
$ErrorActionPreference='Stop'
if(-not$Root){$Root=Split-Path -Parent $PSScriptRoot}
$rootPath=(Resolve-Path -LiteralPath $Root).Path
$issues=[Collections.Generic.List[string]]::new()
$forbiddenExtensions=@('.exe','.dll','.zip','.db','.sqlite','.clixml','.etl','.pcap','.pcapng')
$patterns=[ordered]@{
    'user profile path'='(?i)[A-Z]:\\Users\\(?!<)[^\\\s]+'
    'private IPv4'='(?<![0-9.])(?:10\.(?:\d{1,3}\.){2}\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.(?:\d{1,3}\.)\d{1,3}|192\.168\.(?:\d{1,3}\.)\d{1,3})(?![0-9.])'
    'private key'='-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'
    'GitHub token'='(?i)\bgh[pousr]_[A-Za-z0-9_]{20,}'
    'credential URL'='(?i)https?://[^\s/@:]+:[^\s/@]+@'
    'literal secret'='(?i)(?:password|passwd|token|secret|api[_-]?key)\s*[:=]\s*["''](?!<|\$)[^"'']{5,}["'']'
    'secret CLI value'='(?i)(?<![A-Za-z0-9])--?(?:password|passwd|token|secret)(?:\s+|=)(?!<|\$|%)[^\s"'']{5,}'
}
foreach($file in Get-ChildItem -LiteralPath $rootPath -File -Recurse -Force|Where-Object{$_.FullName-notmatch'[\\/](?:\.git|local|out)[\\/]'}){
    if($file.Extension.ToLowerInvariant()-in$forbiddenExtensions){$issues.Add("Forbidden file type: $($file.FullName)");continue}
    $text=Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
    foreach($entry in $patterns.GetEnumerator()){if($text-match$entry.Value){$issues.Add("$($entry.Key): $($file.FullName)")}}
}
if($issues.Count){$issues|Sort-Object -Unique|ForEach-Object{Write-Error $_};exit 1}
Write-Host 'Publication scan passed.' -ForegroundColor Green
