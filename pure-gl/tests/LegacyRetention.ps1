param([string]$Source,[string]$Root,[string]$Compiler,[string]$CMake)
$ErrorActionPreference='Stop'
$fixture=Join-Path $Root 'legacy fixture'
$tools=Join-Path $fixture 'tools'
$package=Join-Path $fixture 'package'
$build=Join-Path $fixture 'build'
foreach($path in @($tools,"$package/cmake",$build)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
& $Compiler -std=c11 -Wall -Wextra -Werror -municode "$Source/tests/legacy_retention_fixture.c" -o "$tools/ctest.exe"
if($LASTEXITCODE -ne 0) { throw 'Cannot compile legacy retention fixture' }
$utf8=[Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText("$package/.pure-gl-source","pure-gl source 0.9`n",$utf8)
[IO.File]::WriteAllText("$package/GL.c","retained source`n",$utf8)
[IO.File]::WriteAllText("$build/CMakeCache.txt","PURE_GL_STRICT_AUDIT:BOOL=ON`nCMAKE_HOME_DIRECTORY:INTERNAL=$($package.Replace('\','/'))`n",$utf8)
$original=[IO.File]::ReadAllText("$Source/cmake/LegacyWorkflow.ps1")
$script="$package/cmake/LegacyWorkflow.ps1"
$failures=@()
foreach($case in @('dispatch','new-leaf','package-directories')) {
 $package=Join-Path $fixture "package-$case"
 $script="$package/cmake/LegacyWorkflow.ps1"
 New-Item -ItemType Directory -Path "$package/cmake" -Force | Out-Null
 [IO.File]::WriteAllText("$package/.pure-gl-source","pure-gl source 0.9`n",$utf8)
 [IO.File]::WriteAllText("$package/GL.c","retained source`n",$utf8)
 [IO.File]::WriteAllText("$build/CMakeCache.txt","PURE_GL_STRICT_AUDIT:BOOL=ON`nCMAKE_HOME_DIRECTORY:INTERNAL=$($package.Replace('\','/'))`n",$utf8)
 $text=$original
 if($case -eq 'new-leaf') {
  $needle="  [IO.File]::WriteAllText((Join-Path `$taskLeaf '.pure-gl-owner'),`$taskLeafOwner,`$taskUtf8)"
  $text=$text.Replace($needle,"  & '$tools/ctest.exe' --directory `$taskLeaf; if(`$LASTEXITCODE -ne 0) { throw 'New leaf identity was not retained before child access' }`n"+$needle)
 } elseif($case -eq 'package-directories') {
  $needle='   $destination=Join-Path $taskPackage $name'
  $text=$text.Replace($needle,"   foreach(`$d in @('','GL','cmake','debian','debian/source','examples','examples/flexi-line','tests','tests/fixtures')) { & '$tools/ctest.exe' --directory ((Join-Path `$taskPackage `$d).TrimEnd('\')); if(`$LASTEXITCODE -ne 0) { throw 'Package directory identity was not retained before child access' } }`n"+$needle)
 }
 [IO.File]::WriteAllText($script,$text,$utf8)
 $ErrorActionPreference='Continue'
 if($case -eq 'dispatch') {
  $output=& powershell.exe -NoProfile -NonInteractive -File $script -Mode distcheck -SourceRoot $package -CMake "$tools/cmake.exe" -AuditBuild $build 2>&1
 } else {
  $output=& powershell.exe -NoProfile -NonInteractive -File $script -Mode dist -SourceRoot $package -CMake $CMake -DistFiles '.pure-gl-source GL.c' 2>&1
 }
 $ErrorActionPreference='Stop'
 if($LASTEXITCODE -ne 0) { $failures+="$case`: $output" }
}
if($failures.Count) { throw "Legacy retention failed: $($failures -join '; ')" }
Write-Output 'PURE_GL_LEGACY_RETENTION_OK synchronized_dispatch=1 new_directory_checks=10'
