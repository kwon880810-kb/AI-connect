# 지정 날짜 이후 대화를 모든 대화방에서 뽑아 한 파일로 저장 (요청사항 점검용)
# 사용법: powershell -ExecutionPolicy Bypass -File tools\추출.ps1 -Since 2026-10-21 [-Out 경로] [-Exclude '방이름1','방이름2']
param(
    [Parameter(Mandatory)][string]$Since,
    [string]$Out,
    [string[]]$Exclude = @(),
    [string]$Root
)
if (-not $Root) { $Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
if (-not $Root) { $Root = (Get-Location).Path }
$dateRe = '^-{15} (\d{4})년 (\d{1,2})월 (\d{1,2})일 .+ -{15}$'
if (-not $Out) { $Out = Join-Path $Root "_추출_$Since.txt" }
$sb = New-Object System.Text.StringBuilder
foreach ($f in Get-ChildItem (Join-Path $Root '01_대화방') -Filter *.txt | Sort-Object Name) {
    if ($Exclude -contains $f.BaseName) { continue }
    $take = $false; $buf = New-Object System.Text.StringBuilder
    foreach ($l in [System.IO.File]::ReadAllLines($f.FullName, [System.Text.Encoding]::UTF8)) {
        if ($l -match $dateRe) { $take = (('{0}-{1:D2}-{2:D2}' -f [int]$Matches[1], [int]$Matches[2], [int]$Matches[3]) -ge $Since) }
        if ($take) { [void]$buf.AppendLine($l) }
    }
    if ($buf.Length) { [void]$sb.AppendLine("################ [$($f.BaseName)] ################"); [void]$sb.Append($buf.ToString()); [void]$sb.AppendLine() }
}
[System.IO.File]::WriteAllText($Out, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))
Write-Host "저장: $Out ($([math]::Round($sb.Length/1KB))KB)"
