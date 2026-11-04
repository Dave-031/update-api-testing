@echo off
setlocal enabledelayedexpansion

:: =====================================================================
::  UPDATER  -  checks a JSON update endpoint and downloads the latest file.
::              It also keeps ITSELF up to date.
::
::  HOW TO USE
::   1. Edit the SETTINGS section below (at minimum APP_NAME and API_URL).
::   2. Double-click this file to check for updates and download.
::   3. Run  update.bat /force  to re-download even if you already have it.
::
::  YOUR ENDPOINT MUST RETURN JSON LIKE THIS
::   {
::     "version":      "1.0.0",
::     "commit_id":    "abc1234def5678...",
::     "download_url": "https://example.com/files/myapp-1.0.0.zip",
::     "updater": { "version": "1.0.0", "download_url": "https://example.com/update-1.0.0.bat" }
::   }
::  The "updater" part is optional. If your JSON uses other key names for the
::  first three, change the JSON_ settings below.
::
::  HOW IT DECIDES YOU ALREADY HAVE THE LATEST
::   The saved file name gets the first few characters of the commit id added,
::   e.g. myapp-1.0.0.zip becomes myapp-1.0.0-abc123.zip. If that exact file
::   is already in your download folder, there is nothing new to download.
::
::  HOW SELF-UPDATING WORKS
::   The server says which updater version is newest. If it is higher than the
::   UPDATER_VERSION below, this script downloads the new one, replaces itself
::   and restarts. If the server cannot be reached, it checks a backup location
::   (the GitHub repo through jsDelivr) for a newer updater, so an old copy can
::   always get back on track.
::   NOTE: self-updating replaces this whole file, including your SETTINGS.
::   Set SELF_UPDATE to 0 if you do not want that.
::
::  NEEDS: Windows 10 or 11 (uses the built-in PowerShell, nothing to install)
:: =====================================================================

:: ------------------------------ SETTINGS ------------------------------

:: Name shown in the window title and banner
set "APP_NAME=Updater"

:: Link to your update endpoint (the page that returns the JSON)
set "API_URL=https://update-cc1.whf.bz/update.php"

:: Where the file is saved (default: your Downloads folder)
set "DEST=%USERPROFILE%\Downloads"

:: Names of the keys in your JSON
set "JSON_VERSION=version"
set "JSON_COMMIT=commit_id"
set "JSON_URL=download_url"

:: How many characters of the commit id to add to the file name
set "COMMIT_CHARS=6"

:: 1 = check that the file is a real zip, 0 = skip that check (for non-zip files)
set "VERIFY_ZIP=1"

:: 1 = open the folder with the file selected when finished
set "AUTO_OPEN=0"

:: 1 = use colors, 0 = plain text (set 0 if the colors look like garbage)
set "COLORS=1"

:: 1 = wait for a key press at the end, 0 = close right away
set "PAUSE_AT_END=1"

:: 1 = also print the raw server response when something fails
set "DEBUG=0"

:: ---- self-update settings ----
:: 1 = keep this updater up to date by itself, 0 = never replace this file
set "SELF_UPDATE=1"

:: Backup location, used only when the update server cannot be reached.
:: Newer updaters are looked for in the /updater-script/ folder of this GitHub repo.
set "UPDATER_USER=Dave-031"
set "UPDATER_REPO=update-api-testing"
set "UPDATER_BRANCH=main"

:: ---- version of THIS updater script (raise it when you publish a new one) ----
set "UPDATER_VERSION=1.0.0"

:: ---------------------- you can stop editing here ---------------------

title %APP_NAME%
set "UA=Mozilla/5.0 (Windows NT 10.0; Win64; x64) %APP_NAME%/%UPDATER_VERSION% (update checker + downloader)"
set "BODY=%TEMP%\updater_body.txt"
set "STATUS_FILE=%TEMP%\updater_status.txt"
set "NEWFILE=%TEMP%\updater_new.bat"
del "%BODY%" "%STATUS_FILE%" >nul 2>&1

:: command line options
set "FORCE=0"
set "JUST_UPDATED=0"
set "FALLBACK_TRIED=0"
for %%A in (%*) do (
    if /i "%%~A"=="/force" set "FORCE=1"
    if /i "%%~A"=="/updated" set "JUST_UPDATED=1"
)

:: colors
set "C_OK=" & set "C_ERR=" & set "C_WARN=" & set "C_STEP=" & set "C_DIM=" & set "C_RST="
if "%COLORS%"=="1" (
    for /f "delims=#" %%a in ('"prompt #$E# & for %%a in (1) do rem"') do set "ESC=%%a"
    set "C_OK=!ESC![92m"
    set "C_ERR=!ESC![91m"
    set "C_WARN=!ESC![93m"
    set "C_STEP=!ESC![96m"
    set "C_DIM=!ESC![90m"
    set "C_RST=!ESC![0m"
)

echo !C_STEP!==========================================!C_RST!
echo !C_STEP!   %APP_NAME%  !C_DIM!(updater v%UPDATER_VERSION%)!C_RST!
echo !C_STEP!==========================================!C_RST!
if "!JUST_UPDATED!"=="1" echo !C_OK!   The updater was just updated to v%UPDATER_VERSION%.!C_RST!
echo.

:: make sure the URL was filled in
if "%API_URL%"=="" (
    set "REASON=No API_URL is set. Open this file in Notepad and edit the SETTINGS section."
    goto :fail
)
if /i "%API_URL%"=="PUT_YOUR_URL_HERE" (
    set "REASON=API_URL is still the placeholder. Open this file in Notepad and edit the SETTINGS section."
    goto :fail
)

:: ---- Step 1: contact the server ----
echo !C_STEP![1/6] Checking for updates...!C_RST!

powershell -NoProfile -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; try { $r = Invoke-WebRequest -Uri '%API_URL%' -UserAgent '%UA%' -UseBasicParsing; Set-Content -Path '%BODY%' -Value $r.Content; Set-Content -Path '%STATUS_FILE%' -Value ('HTTP ' + [int]$r.StatusCode) } catch { $m = $_.Exception.Message; $code = ''; $b = ''; if ($_.Exception.Response) { $code = 'HTTP ' + [int]$_.Exception.Response.StatusCode + ' - '; if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $b = $_.ErrorDetails.Message } else { try { $b = (New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())).ReadToEnd() } catch {} } }; Set-Content -Path '%BODY%' -Value $b; Set-Content -Path '%STATUS_FILE%' -Value ($code + $m) }"

set "STATUS=no response"
if exist "%STATUS_FILE%" set /p STATUS=<"%STATUS_FILE%"

if /i not "!STATUS!"=="HTTP 200" (
    set "REASON=Could not reach the update server: !STATUS!"
    goto :netfail
)
echo !C_DIM!      Connected to the update server.!C_RST!

:: ---- Step 2: read the update info ----
echo !C_STEP![2/6] Reading update info...!C_RST!

findstr /i /c:"aes.js" "%BODY%" >nul 2>&1
if not errorlevel 1 (
    set "REASON=The host blocked the request with its browser check instead of returning the update info."
    goto :netfail
)

set "VERSION="
set "COMMIT="
set "DL_URL="
set "UPD_VER="
set "UPD_URL="
for /f "tokens=1-5 delims=|" %%A in ('powershell -NoProfile -Command "try { $r = ConvertFrom-Json (Get-Content -Raw '%BODY%'); if (-not $r.'%JSON_URL%') { 'NOURL' } else { $uv = '-'; $uu = '-'; if ($r.updater -and $r.updater.version -and $r.updater.download_url) { $uv = $r.updater.version; $uu = $r.updater.download_url }; ($r.'%JSON_VERSION%', $r.'%JSON_COMMIT%', $r.'%JSON_URL%', $uv, $uu) -join '|' } } catch { 'PARSEFAIL' }"') do (
    set "VERSION=%%A"
    set "COMMIT=%%B"
    set "DL_URL=%%C"
    set "UPD_VER=%%D"
    set "UPD_URL=%%E"
)

if not defined DL_URL (
    set "REASON=The reply was not valid update info. Check API_URL and the JSON_ key names in SETTINGS."
    goto :netfail
)
if "!UPD_VER!"=="-" (
    set "UPD_VER="
    set "UPD_URL="
)

:: Local file name = name from the url + first few characters of the commit id
:: e.g. myapp-1.0.0.zip  ->  myapp-1.0.0-abc123.zip
set "COMMIT_SHORT=!COMMIT:~0,%COMMIT_CHARS%!"
set "FILENAME="
for /f "delims=" %%F in ('powershell -NoProfile -Command "$p = ([uri]'!DL_URL!').AbsolutePath; $n = [IO.Path]::GetFileNameWithoutExtension($p); $e = [IO.Path]::GetExtension($p); if (-not $n) { $n = 'update' }; if (-not $e) { $e = '.zip' }; $n + '-!COMMIT_SHORT!' + $e"') do set "FILENAME=%%F"
if not defined FILENAME set "FILENAME=update-!COMMIT_SHORT!.zip"

echo !C_DIM!      Latest version: !VERSION!!C_RST!
echo !C_DIM!      Latest commit:  !COMMIT_SHORT!!C_RST!

:: ---- Step 3: check if this updater is out of date ----
echo !C_STEP![3/6] Checking for updater updates...!C_RST!

if not "!SELF_UPDATE!"=="1" (
    echo !C_DIM!      Self-update is turned off.!C_RST!
    goto :step4
)
if "!JUST_UPDATED!"=="1" (
    echo !C_DIM!      Already updated this run.!C_RST!
    goto :step4
)
if not defined UPD_URL (
    echo !C_DIM!      The server did not list a newer updater.!C_RST!
    goto :step4
)

set "UPD_CHECK=SAME"
for /f "delims=" %%R in ('powershell -NoProfile -Command "try { if ([version]'!UPD_VER!' -gt [version]'%UPDATER_VERSION%') { 'NEWER' } else { 'SAME' } } catch { 'SAME' }"') do set "UPD_CHECK=%%R"

if /i "!UPD_CHECK!"=="NEWER" (
    echo !C_WARN!      A newer updater is available: v!UPD_VER!, you have v%UPDATER_VERSION%.!C_RST!
    set "SU_RETURN=step4"
    goto :selfupdate
)
echo !C_DIM!      Your updater is up to date, v%UPDATER_VERSION%.!C_RST!

:step4
:: ---- Step 4: check if you already have the latest file ----
echo !C_STEP![4/6] Checking if you already have it...!C_RST!

if "!FORCE!"=="1" (
    echo !C_WARN!      Force mode, downloading again.!C_RST!
    goto :download
)

if not exist "%DEST%\!FILENAME!" (
    echo !C_DIM!      You don't have this version yet.!C_RST!
    goto :download
)

:: the file is there, make sure it is not a broken download
powershell -NoProfile -Command "$f='%DEST%\!FILENAME!'; try { $fs = [IO.File]::OpenRead($f); $buf = New-Object byte[] 2; $n = $fs.Read($buf,0,2); $fs.Close(); if ('!VERIFY_ZIP!' -eq '1' -and ($n -lt 2 -or $buf[0] -ne 80 -or $buf[1] -ne 75)) { exit 1 } } catch { exit 1 }"
if not errorlevel 1 goto :uptodate

echo !C_WARN!      Found the file but it looks damaged, downloading it again.!C_RST!

:download
:: ---- Step 5: download ----
echo !C_STEP![5/6] Downloading !FILENAME!...!C_RST!

if not exist "%DEST%" mkdir "%DEST%" >nul 2>&1

powershell -NoProfile -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $ProgressPreference='SilentlyContinue'; $f='%DEST%\!FILENAME!'; try { Invoke-WebRequest -Uri '!DL_URL!' -UserAgent '%UA%' -UseBasicParsing -OutFile $f } catch { Set-Content -Path '%STATUS_FILE%' -Value ('Download failed: ' + $_.Exception.Message); exit 1 }; Set-Content -Path '%STATUS_FILE%' -Value 'ok'"

if errorlevel 1 (
    set "REASON=The download failed."
    if exist "%STATUS_FILE%" set /p REASON=<"%STATUS_FILE%"
    goto :fail
)
echo !C_DIM!      Download complete.!C_RST!

:: ---- Step 6: verify ----
echo !C_STEP![6/6] Verifying the file...!C_RST!

powershell -NoProfile -Command "$f='%DEST%\!FILENAME!'; $fs = [IO.File]::OpenRead($f); $buf = New-Object byte[] 2; $n = $fs.Read($buf,0,2); $len = $fs.Length; $fs.Close(); if ($len -eq 0 -or ('!VERIFY_ZIP!' -eq '1' -and ($n -lt 2 -or $buf[0] -ne 80 -or $buf[1] -ne 75))) { Remove-Item $f; exit 2 }; Set-Content -Path '%STATUS_FILE%' -Value ([string]$len)"

if errorlevel 1 (
    set "REASON=The downloaded file was empty or not a valid zip, so it was removed."
    goto :fail
)
set /p SIZE=<"%STATUS_FILE%"
echo !C_DIM!      File looks good, !SIZE! bytes.!C_RST!

echo.
echo !C_OK!==========================================!C_RST!
echo !C_OK!  Done. Version !VERSION! saved to:!C_RST!
echo !C_OK!  %DEST%\!FILENAME!!C_RST!
echo !C_OK!==========================================!C_RST!
goto :finish

:uptodate
echo !C_DIM!      You already have the latest version.!C_RST!
echo.
echo !C_OK!==========================================!C_RST!
echo !C_OK!  Up to date. Version !VERSION! is already at:!C_RST!
echo !C_OK!  %DEST%\!FILENAME!!C_RST!
echo !C_OK!  Nothing to download.!C_RST!
echo !C_OK!==========================================!C_RST!
goto :finish

:: =====================================================================
::  Server could not be used: try the backup location for a newer updater
:: =====================================================================
:netfail
if not "!SELF_UPDATE!"=="1" goto :fail
if not "!JUST_UPDATED!"=="0" goto :fail
if not "!FALLBACK_TRIED!"=="0" goto :fail
set "FALLBACK_TRIED=1"

echo.
echo !C_WARN!Could not get update info. Checking the backup location for a newer updater...!C_RST!

set "UPD_VER="
set "UPD_URL="
for /f "tokens=1-2 delims=|" %%A in ('powershell -NoProfile -Command "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; try { $d = Invoke-RestMethod -Uri 'https://data.jsdelivr.com/v1/package/gh/%UPDATER_USER%/%UPDATER_REPO%@%UPDATER_BRANCH%/flat' -UserAgent '%UA%'; $bv = $null; $bn = ''; foreach ($f in $d.files) { if ($f.name -match '\A/updater-script/update-(\d+(\.\d+)+)\.bat$') { $v = [version]$Matches[1]; if (-not $bv -or $v -gt $bv) { $bv = $v; $bn = $f.name } } }; if ($bv -and $bv -gt [version]'%UPDATER_VERSION%') { $bv.ToString() + '|https://cdn.jsdelivr.net/gh/%UPDATER_USER%/%UPDATER_REPO%@%UPDATER_BRANCH%' + $bn } else { 'NONE' } } catch { 'NONE' }"') do (
    set "UPD_VER=%%A"
    set "UPD_URL=%%B"
)

if not defined UPD_URL (
    echo !C_DIM!      No newer updater found there.!C_RST!
    goto :fail
)

echo !C_WARN!      Found a newer updater there: v!UPD_VER!, you have v%UPDATER_VERSION%.!C_RST!
set "SU_RETURN=fail"
goto :selfupdate

:: =====================================================================
::  Replace this file with the newer updater and restart
::  (expects UPD_URL, UPD_VER and SU_RETURN to be set)
:: =====================================================================
:selfupdate
echo !C_STEP!      Downloading the new updater...!C_RST!
del "%NEWFILE%" >nul 2>&1

powershell -NoProfile -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $ProgressPreference='SilentlyContinue'; try { Invoke-WebRequest -Uri '!UPD_URL!' -UserAgent '%UA%' -UseBasicParsing -OutFile '%NEWFILE%' } catch { exit 1 }; $t = [IO.File]::ReadAllText('%NEWFILE%'); if (-not [regex]::IsMatch($t, '(?im)\A\s*@echo off')) { exit 2 }; $m = [regex]::Match($t, 'set \x22UPDATER_VERSION=(.+?)\x22'); if (-not $m.Success) { exit 2 }; if ([version]$m.Groups[1].Value -le [version]'%UPDATER_VERSION%') { exit 3 }; $t = [regex]::Replace($t, '\r?\n', ([string][char]13 + [string][char]10)); [IO.File]::WriteAllText('%NEWFILE%', $t, (New-Object Text.UTF8Encoding $false)); Set-Content -Path '%STATUS_FILE%' -Value $m.Groups[1].Value"

set "SU_ERR=0"
if errorlevel 1 set "SU_ERR=1"
if errorlevel 2 set "SU_ERR=2"
if errorlevel 3 set "SU_ERR=3"
if not "!SU_ERR!"=="0" goto :selfupdate_failed

set "NEW_VER=?"
if exist "%STATUS_FILE%" set /p NEW_VER=<"%STATUS_FILE%"
echo !C_OK!      New updater ready, v!NEW_VER!. Restarting...!C_RST!
echo.
del "%BODY%" "%STATUS_FILE%" >nul 2>&1

:: (goto) lets this file be replaced while it is running, then the new one starts
(goto) 2>nul & move /y "%NEWFILE%" "%~f0" >nul & "%~f0" %* /updated

:selfupdate_failed
if "!SU_ERR!"=="3" (
    echo !C_WARN!      The updater online does not have a higher version number than this one, so it was skipped.!C_RST!
) else if "!SU_ERR!"=="2" (
    echo !C_WARN!      The file online is not a valid updater, so it was skipped.!C_RST!
) else (
    echo !C_WARN!      Could not download the new updater, continuing with this one.!C_RST!
)
del "%NEWFILE%" >nul 2>&1
goto :%SU_RETURN%

:fail
echo.
echo !C_ERR![X] Update failed: !REASON!!C_RST!
if "%DEBUG%"=="1" (
    echo.
    echo !C_DIM!--- raw server response ---!C_RST!
    powershell -NoProfile -Command "if (Test-Path '%BODY%') { $t = Get-Content -Raw '%BODY%' }; if (-not $t) { '(empty)' } elseif ($t.Length -gt 600) { $t.Substring(0,600) + ' ...[cut]' } else { $t }"
    echo !C_DIM!---------------------------!C_RST!
)
goto :end

:finish
if "%AUTO_OPEN%"=="1" if exist "%DEST%\!FILENAME!" explorer /select,"%DEST%\!FILENAME!"

:end
del "%BODY%" "%STATUS_FILE%" "%NEWFILE%" >nul 2>&1
echo.
if "%PAUSE_AT_END%"=="1" pause
endlocal
