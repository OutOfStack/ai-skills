param([switch]$Apply, [switch]$SelfTest, [string]$ReportDir)
$ErrorActionPreference = 'Stop'

function Test-Contained([string]$Path, [string]$Root) {
    $full = [IO.Path]::GetFullPath($Path)
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    return $full.StartsWith($base + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Test-PlainPath([string]$Path, [string]$Root) {
    if (-not (Test-Contained $Path $Root)) { return $false }
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        try {
            if ([IO.File]::GetAttributes($cursor) -band [IO.FileAttributes]::ReparsePoint) { return $false }
        } catch [IO.FileNotFoundException] {
            # The directory-walk boundary probe deliberately uses a nonexistent child.
        } catch [IO.DirectoryNotFoundException] { }
        $parent = [IO.Path]::GetDirectoryName($cursor)
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
    return $true
}

# The plan file is untrusted on reload: keep only entries under roots this run still targets.
function Get-ReviewedPlan([string]$File, [string[]]$Roots) {
    $loaded = Get-Content -LiteralPath $File -Raw | ConvertFrom-Json
    return @($loaded | ForEach-Object { $_ } | Where-Object { $_ -and $Roots -contains $_.Root })
}

if ($SelfTest) {
    $root = 'C:\example\cache'
    if (-not (Test-Contained 'C:\example\cache\nested\item' $root)) { throw 'Contained path rejected' }
    foreach ($outside in @($root, 'C:\example\cache-other\item', 'C:\example\cache\..\personal.txt')) {
        if (Test-Contained $outside $root) { throw "Unsafe path accepted: $outside" }
    }
    $fixture = Join-Path ([IO.Path]::GetTempPath()) ('cleanup-check-' + [Guid]::NewGuid().ToString('N'))
    $cache = Join-Path $fixture 'cache'
    $personal = Join-Path $fixture 'personal'
    $link = Join-Path $cache 'linked'
    try {
        [IO.Directory]::CreateDirectory($cache) | Out-Null
        [IO.Directory]::CreateDirectory($personal) | Out-Null
        [IO.File]::WriteAllText((Join-Path $cache 'disposable.bin'), 'cache')
        [IO.File]::WriteAllText((Join-Path $personal 'keep.txt'), 'personal')
        if (-not (Test-PlainPath (Join-Path $cache 'disposable.bin') $cache)) { throw 'Regular cache path rejected' }
        New-Item -ItemType Junction -Path $link -Target $personal | Out-Null
        if (Test-PlainPath (Join-Path $link 'keep.txt') $cache) { throw 'Junction escape accepted' }
        if ([IO.File]::ReadAllText((Join-Path $personal 'keep.txt')) -ne 'personal') { throw 'Fixture personal data changed' }
        $planFile = Join-Path $fixture 'plan.json'
        ConvertTo-Json -InputObject @([pscustomobject]@{Root=$cache;Path='a'}, [pscustomobject]@{Root=$personal;Path='b'}) |
            Set-Content -LiteralPath $planFile -Encoding utf8
        $kept = @(Get-ReviewedPlan $planFile @($cache.ToUpper()))
        if ($kept.Count -ne 1 -or $kept[0].Path -ne 'a') { throw 'Plan entry outside current roots accepted' }
    } finally {
        if (Test-Path -LiteralPath $link) { [IO.Directory]::Delete($link) }
        foreach ($file in @((Join-Path $cache 'disposable.bin'), (Join-Path $personal 'keep.txt'), (Join-Path $fixture 'plan.json'))) {
            if (Test-Contained $file $fixture) { [IO.File]::Delete($file) }
        }
        foreach ($directory in @($cache, $personal, $fixture)) {
            if ([IO.Directory]::Exists($directory)) { [IO.Directory]::Delete($directory, $false) }
        }
    }
    'Cleanup path-boundary self-check passed.'
    exit 0
}
if (-not $ReportDir) { throw 'ReportDir is required.' }
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
$profileRoot = [Environment]::GetFolderPath('UserProfile')
$localRoot = Join-Path $profileRoot 'AppData\Local'
$roamingRoot = Join-Path $profileRoot 'AppData\Roaming'
$dataRoot = [Environment]::GetFolderPath('CommonApplicationData')
$cutoff = [DateTime]::UtcNow.AddHours(-72)
$targets = [Collections.Generic.List[object]]::new()
$plan = [Collections.Generic.List[object]]::new()
$skipped = [Collections.Generic.List[object]]::new()
$preserved = [Collections.Generic.List[string]]::new()

function Add-Target([string]$Category, [string]$Root, [string]$Pattern = '*') {
    if (Test-Path -LiteralPath $Root -PathType Container) {
        $targets.Add([pscustomobject]@{Category=$Category;Root=[IO.Path]::GetFullPath($Root);Pattern=$Pattern})
    }
}

Add-Target 'NVIDIA shader cache' (Join-Path $localRoot 'NVIDIA\DXCache')
Add-Target 'NVIDIA shader cache' (Join-Path $localRoot 'NVIDIA\GLCache')
Add-Target 'NVIDIA shader cache' (Join-Path $localRoot 'NVIDIA Corporation\NV_Cache')
Add-Target 'VS Code downloaded extension packages' (Join-Path $roamingRoot 'Code\CachedExtensionVSIXs')
Add-Target 'Logitech downloaded packages' (Join-Path $dataRoot 'LGHUB\cache') '^[0-9a-f]{64}$'
Add-Target 'Go compiled build cache' (Join-Path $localRoot 'go-build') '^[0-9a-f]{64}-[ad]$'

$installerActive = @(Get-Process | Where-Object { $_.ProcessName -match '^(setup|msiexec|NVIDIAInstaller|NVI2|installer)$' }).Count -gt 0
if (-not $installerActive) {
    $jetbrains = Join-Path $localRoot 'JetBrains'
    if (Test-Path -LiteralPath $jetbrains) {
        foreach ($ide in Get-ChildItem -LiteralPath $jetbrains -Directory) {
            if ($ide.Name -match '^(GoLand|IntelliJIdea|Rider|WebStorm|PyCharm)\d{4}\.\d+$') {
                Add-Target 'JetBrains old patch downloads' (Join-Path $ide.FullName 'tmp\patch-update')
            }
        }
    }
    $drivers = Join-Path $dataRoot 'NVIDIA Corporation\NVIDIA App\UpdateFramework\ota-artifacts\grd'
    if (Test-Path -LiteralPath $drivers) {
        $bundles = @(Get-ChildItem -LiteralPath $drivers -Directory | Where-Object { $_.Name -match '^[0-9a-f]{32}$' } | Sort-Object CreationTimeUtc -Descending)
        if ($bundles.Count) { $preserved.Add($bundles[0].FullName) }
        foreach ($bundle in ($bundles | Select-Object -Skip 1)) {
            Add-Target 'NVIDIA older driver installer' $bundle.FullName
            Add-Target 'NVIDIA older driver installer' (Join-Path $drivers ('post-processing\' + $bundle.Name))
        }
    }
} else {
    $preserved.Add('Installer caches skipped because an installer is running.')
}

foreach ($target in $targets) {
    $stack = [Collections.Generic.Stack[string]]::new()
    $stack.Push($target.Root)
    while ($stack.Count) {
        $directory = $stack.Pop()
        if (-not (Test-PlainPath (Join-Path $directory '__boundary_check__') $target.Root)) {
            $skipped.Add([pscustomobject]@{Path=$directory;Reason='Linked or unsafe path'})
            continue
        }
        try { $entries = @(Get-ChildItem -LiteralPath $directory -Force) }
        catch { $skipped.Add([pscustomobject]@{Path=$directory;Reason=$_.Exception.Message}); continue }
        foreach ($file in $entries) {
            if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                $skipped.Add([pscustomobject]@{Path=$file.FullName;Reason='Reparse point'})
            } elseif ($file.PSIsContainer) {
                $stack.Push($file.FullName)
            } elseif (($target.Pattern -eq '*' -or $file.Name -match $target.Pattern) -and
                      $file.CreationTimeUtc -lt $cutoff -and $file.LastWriteTimeUtc -lt $cutoff) {
                $plan.Add([pscustomobject]@{Category=$target.Category;Root=$target.Root;Path=$file.FullName;
                    Bytes=$file.Length;WrittenTicks=$file.LastWriteTimeUtc.Ticks;CreatedTicks=$file.CreationTimeUtc.Ticks})
            }
        }
    }
}
$planFile = Join-Path $ReportDir 'cleanup-plan.json'
if ($Apply) {
    # Delete only what the user reviewed, not a fresh plan that may include newly aged files.
    if (-not (Test-Path -LiteralPath $planFile)) { throw 'No reviewed plan; run without -Apply first.' }
    $plan = @(Get-ReviewedPlan $planFile @($targets | ForEach-Object Root))
} else {
    ConvertTo-Json -InputObject @($plan) -Depth 4 | Set-Content -LiteralPath $planFile -Encoding utf8
}
$before = [IO.DriveInfo]::new('C').AvailableFreeSpace
$removed = [Collections.Generic.List[object]]::new()
if ($Apply) {
    foreach ($entry in $plan) {
        try {
            if (-not (Test-PlainPath $entry.Path $entry.Root)) { throw 'Path changed or links detected' }
            $current = Get-Item -LiteralPath $entry.Path -Force
            if ($current.PSIsContainer -or $current.Length -ne $entry.Bytes -or
                $current.LastWriteTimeUtc.Ticks -ne $entry.WrittenTicks -or
                $current.CreationTimeUtc.Ticks -ne $entry.CreatedTicks) { throw 'File changed since plan' }
            # Do not clear caches currently held open by an app or driver.
            $handle = [IO.File]::Open($entry.Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
            $handle.Dispose()
            Remove-Item -LiteralPath $entry.Path -Force
            $removed.Add($entry)
        } catch { $skipped.Add([pscustomobject]@{Path=$entry.Path;Reason=$_.Exception.Message}) }
    }
}
$after = [IO.DriveInfo]::new('C').AvailableFreeSpace
$summary = [pscustomobject]@{
    Mode=$(if ($Apply) {'Applied'} else {'Plan only'});Time=[DateTime]::Now.ToString('o');
    BeforeFreeGiB=[math]::Round($before/1GB,3);AfterFreeGiB=[math]::Round($after/1GB,3);
    ActualFreeGainGiB=[math]::Round(($after-$before)/1GB,3);
    PlannedFiles=$plan.Count;RemovedFiles=$removed.Count;SkippedCount=$skipped.Count;
    PlannedCategories=@($plan | Group-Object Category | ForEach-Object {
        [pscustomobject]@{Category=$_.Name;Files=$_.Count;GiB=[math]::Round(($_.Group | Measure-Object Bytes -Sum).Sum/1GB,3)} });
    RemovedCategories=@($removed | Group-Object Category | ForEach-Object {
        [pscustomobject]@{Category=$_.Name;Files=$_.Count;GiB=[math]::Round(($_.Group | Measure-Object Bytes -Sum).Sum/1GB,3)} });
    Preserved=$preserved.ToArray();SkippedExamples=@($skipped | Select-Object -First 20)
}
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $ReportDir 'cleanup-summary.json') -Encoding utf8
ConvertTo-Json -InputObject @($skipped) -Depth 4 | Set-Content -LiteralPath (Join-Path $ReportDir 'cleanup-skipped.json') -Encoding utf8
$summary | ConvertTo-Json -Depth 6
