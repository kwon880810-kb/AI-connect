# 카카오톡 내보내기(.txt)를 대화방별 마스터 파일(01_대화방\<방이름>.txt)에 병합한다.
# 사용법: powershell -ExecutionPolicy Bypass -File tools\병합.ps1
#  - 루트 폴더 또는 00_원본\신규 에 있는 KakaoTalk_*.txt 를 읽어 병합
#  - 처리한 파일은 00_원본\처리완료 로 이동
# 병합 규칙: 마스터의 마지막 날짜(D) 이전은 유지, D 이후(포함)는 새 내보내기 내용으로 교체.
param([string]$Root = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($true)
$roomDir = Join-Path $Root '01_대화방'
$doneDir = Join-Path $Root '00_원본\처리완료'
$inDir   = Join-Path $Root '00_원본\신규'
foreach ($d in @($roomDir, $doneDir, $inDir)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null } }

$dateRe = '^-{15} (\d{4})년 (\d{1,2})월 (\d{1,2})일 .+ -{15}$'

function Get-Sections([string[]]$lines) {
    # 헤더(앞 3줄)와 날짜별 섹션(키 yyyy-MM-dd, 값 줄 목록) 반환
    $header = New-Object System.Collections.Generic.List[string]
    $sections = New-Object System.Collections.Specialized.OrderedDictionary
    $cur = $null
    foreach ($l in $lines) {
        if ($l -match $dateRe) {
            $cur = '{0}-{1:D2}-{2:D2}' -f [int]$Matches[1], [int]$Matches[2], [int]$Matches[3]
            if (-not $sections.Contains($cur)) { $sections[$cur] = New-Object System.Collections.Generic.List[string] }
            $sections[$cur].Add($l)
        } elseif ($null -eq $cur) { $header.Add($l) }
        else { $sections[$cur].Add($l) }
    }
    return @{ Header = $header; Sections = $sections }
}

$files = @(Get-ChildItem -Path $Root, $inDir -Filter 'KakaoTalk_*.txt' -File | Sort-Object Name)
if ($files.Count -eq 0) { Write-Host '병합할 새 파일이 없습니다.'; exit 0 }

foreach ($f in $files) {
    $lines = [System.IO.File]::ReadAllLines($f.FullName, [System.Text.Encoding]::UTF8)
    $room = ($lines[0] -replace ' 님과 카카오톡 대화$', '').Trim()
    $safe = ($room -replace '[\\/:*?"<>|]', '_')
    $master = Join-Path $roomDir "$safe.txt"
    $new = Get-Sections $lines
    $newKeys = @($new.Sections.Keys)
    $added = 0

    if (-not (Test-Path $master)) {
        [System.IO.File]::WriteAllLines($master, $lines, $utf8)
        $added = $newKeys.Count
        $status = '신규 생성'
    } else {
        $old = Get-Sections ([System.IO.File]::ReadAllLines($master, [System.Text.Encoding]::UTF8))
        $oldKeys = @($old.Sections.Keys)
        $lastOld = if ($oldKeys.Count) { $oldKeys[-1] } else { '0000-00-00' }
        $firstNew = if ($newKeys.Count) { $newKeys[0] } else { '9999-99-99' }
        $out = New-Object System.Collections.Generic.List[string]
        $out.Add($lines[0]); $out.Add($lines[1]); if ($old.Header.Count -gt 2) { $out.AddRange([string[]]@($old.Header | Select-Object -Skip 2)) }
        foreach ($k in $oldKeys) { if ($k -lt $lastOld) { $out.AddRange($old.Sections[$k]) } }
        if ($firstNew -gt $lastOld) {
            $out.AddRange($old.Sections[$lastOld])
            $status = "경고: 공백 가능 ($lastOld ~ $firstNew 사이)"
        } else { $status = '병합' }
        foreach ($k in $newKeys) { if ($k -ge $lastOld) { $out.AddRange($new.Sections[$k]); if ($k -gt $lastOld) { $added++ } } }
        if (($newKeys.Count -eq 0) -or ($newKeys[-1] -lt $lastOld)) {
            $status = '건너뜀(기존보다 오래된 내보내기)'
        } else {
            [System.IO.File]::WriteAllLines($master, $out, $utf8)
        }
    }
    Move-Item -LiteralPath $f.FullName -Destination (Join-Path $doneDir $f.Name) -Force
    $lastKey = if ($newKeys.Count) { $newKeys[-1] } else { '-' }
    Write-Host ("[{0}] {1} | 새 날짜 {2}일 | 마지막 {3}" -f $status, $room, $added, $lastKey)
}
