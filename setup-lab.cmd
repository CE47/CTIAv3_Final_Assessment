@echo off
setlocal EnableExtensions EnableDelayedExpansion
title setup-lab.cmd  -  %~n0

rem ===========================================================================
rem  setup-lab.cmd  --  one-click lab build for the CTIA FINAL EXAM
rem
rem    setup-lab.cmd                create / update the lab, then open the browser
rem    setup-lab.cmd reset          remove containers, volume and data views, rebuild
rem    setup-lab.cmd regen-compose  rewrite docker-compose.yml, then set up
rem    setup-lab.cmd nolaunch       set up but do not open the browser
rem    setup-lab.cmd -?             this list
rem
rem  Every Docker object name is derived from the folder name, so this lab can
rem  live next to other scenario labs on one machine without colliding, and so
rem  teardown.cmd can prove exactly what it is allowed to delete.
rem
rem  There is a Linux / macOS twin of this file, setup-lab.sh, in the same
rem  folder. It does exactly the same thing in exactly the same order. If you
rem  change one, change the other, or a Windows lab and a Mac lab quietly stop
rem  being the same lab.
rem
rem  DIFFERENCE FROM THE PRACTICE LABS, AND IT IS THE IMPORTANT ONE:
rem  this script hands over a URL, two credentials and nothing else. A practice
rem  lab prints a sheet of queries and the number each one must return. This one
rem  must not, because the student is being examined on choosing the queries.
rem
rem  CONSEQUENCE FOR ANYONE EDITING THIS FILE, PLEASE READ IT:
rem  nothing that names a finding, an indicator of any kind, or a graded count
rem  may live in here, not even inside a comment. The student receives this file
rem  and will read it. One line is enough to give the exam away: a line naming
rem  an address, an account, an event code, or even a CATEGORY of finding turns
rem  the examination into a transcription exercise. Do not name the categories
rem  either - saying what to go and look for is the same as handing over the
rem  answer.
rem
rem  :verify therefore checks only what the student can already see for
rem  themselves: the document totals, which the README publishes anyway, the
rem  alert totals, which the Alerts page shows anyway, and that the four data
rem  views resolve and expose their fields.
rem
rem  It used to assert a dozen further figures, each paired with the query that
rem  produced it.  That was the exam's answer key, in plaintext, in the student's
rem  hands - it existed to catch the lab being built wrong, and it did that job
rem  at the cost of the entire exercise.  Those figures belong in solution.md,
rem  the one file in this folder the student is not meant to open.
rem
rem  THIS FILE MUST KEEP CRLF (Windows) LINE ENDINGS.  That is not a style
rem  preference, it is a correctness requirement, and the failure it causes is
rem  silent and very confusing.  cmd.exe finds a subroutine with CALL by seeking
rem  to the byte offset of its label, and with LF-only endings that seek
rem  mis-lands by one line: the first statement after the label is silently
rem  skipped.  Most of this script runs either way, so the damage only shows up
rem  in one place.  Some editors and every "fix line endings" formatter will
rem  silently rewrite this file back to LF, so if a failure message ever comes
rem  back from a subroutine, check this before looking at anything else.
rem ===========================================================================

rem ------------------------------------------------------------------ settings
set "ESPORT=9200"
set "KBPORT=5601"
set "ESIMAGE=docker.elastic.co/elasticsearch/elasticsearch:9.1.0"
set "KBIMAGE=docker.elastic.co/kibana/kibana:9.1.0"

rem  the lab ships six months of history, so it writes monthly indices
set "AUTHDOCS=14234"
set "NETDOCS=4906"
set "DNSDOCS=6693"
set "CLOUDDOCS=1132"

rem  alert totals, per rule, and the grand total.  These are not a secret: the
rem  Alerts page counts them in front of the student, and the README publishes
rem  the grand total, so asserting them catches a broken lab without hinting.
set "R1ALERTS=1"
set "R2ALERTS=12"
set "R3ALERTS=24"
set "R4ALERTS=23"
set "R5ALERTS=611"
set /a TOTALS=%R1ALERTS%+%R2ALERTS%+%R3ALERTS%+%R4ALERTS%+%R5ALERTS%

rem  There are deliberately NO further constants here.  The figures this exam
rem  grades used to live in this block so that :verify could assert them, and
rem  that turned this file into the answer key.  See the header above.

rem ------------------------------------------------------------------ accounts
rem  Security has to be on. A detection rule cannot be created against a
rem  cluster that has it off: Elasticsearch has no rule API in that mode and
rem  Kibana refuses the rule call, so the Alerts page would always be empty.
rem  These two accounts are throwaway lab credentials. They are printed on
rem  screen and typed into curl by the operator; they protect nothing.
rem  ESBOOT is only used once, to create the account Kibana runs as. Kibana
rem  refuses to run as the built-in elastic superuser, and a plain superuser
rem  cannot create the .kibana* saved-object indices, so the account also
rem  carries the built-in kibana_system role.
set "ESBOOT=LabElastic001"
set "ESUSER=elastic"
set "ESPASS=LabElastic001"
set "KBUSER=lab_kibana"
set "KBPASS=LabKibana001"

rem  the five detection rules, in the order they are installed
rem
rem  The rule NAMES are written out here rather than read out of the rule files.
rem  All three reference labs do exactly this, and it is the right call: parsing
rem  a name back out of a JSON file needs either a shell-out inside a FOR body
rem  (more / findstr, neither of which any reference uses) or a hand-rolled
rem  quote split, and either way the name is now a maintenance trap that only
rem  shows up on Windows.  Keep it here, beside the file it names.
set "RULENAME1=Repeated failed logons for a single account from one external address"
set "RULENAME2=Directory replication requested from a host that is not a domain controller or a backup server"
set "RULENAME3=Office application spawned a command interpreter"
set "RULENAME4=Service account authenticated interactively"
set "RULENAME5=High volume of TXT queries to a single registered domain"

rem ------------------------------------------------------ identity from folder
for %%I in ("%~dp0.") do set "SCEN=%%~nI"
set "LABDIR=%~dp0"
if "%LABDIR:~-1%"=="\" set "LABDIR=%LABDIR:~0,-1%"
set "VOL=%SCEN%_esdata"
set "NETNAME=%SCEN%_lab"
set "WORK=%TEMP%\elklab-%SCEN%"
set "ESURL=http://127.0.0.1:%ESPORT%"
set "KBURL=http://127.0.0.1:%KBPORT%"
set "COMPOSEFILE=%LABDIR%\docker-compose.yml"

rem  every Elasticsearch call is made as the bootstrap superuser, every Kibana
rem  call as the account Kibana itself runs as. Both are kept in variables so
rem  that a password containing a character cmd likes to argue about - ! ^ & -
rem  only ever has to be fixed in one place.
set "ESAUTH=-u %ESUSER%:%ESPASS%"
set "KBAUTH=-u %KBUSER%:%KBPASS%"

set "MODE=setup"
set "LAUNCH=1"
:parseargs
if not "%~1"=="" (
  set "A=%~1"
  if /i "!A!"=="reset"          set "MODE=reset"
  if /i "!A!"=="regen-compose"  set "MODE=regen"
  if /i "!A!"=="nolaunch"       set "LAUNCH=0"
  if /i "!A!"=="-?"             goto :usage
  if /i "!A!"=="--help"         goto :usage
  if /i "!A!"=="help"           goto :usage
  shift
  goto :parseargs
)
goto :start

rem ------------------------------------------------------------------- usage
:usage
echo.
echo  ==============================================================
echo   setup-lab.cmd  -  build the "%SCEN%" lab
echo  ==============================================================
echo.
echo    setup-lab.cmd                create or update the lab, open the browser
echo    setup-lab.cmd reset          remove containers, volume and data views, rebuild
echo    setup-lab.cmd regen-compose  rewrite docker-compose.yml, then set up
echo    setup-lab.cmd nolaunch       set up but do not open the browser
echo    setup-lab.cmd -?             this list
echo.
echo  Docker images are downloaded once and then kept, so the second run of
echo  this script is fast. Nothing outside this scenario is ever touched.
echo.
pause
exit /b 0

:start
echo.
echo  ==============================================================
echo   Scenario lab   :  %SCEN%
echo   Elasticsearch  :  %ESURL%
echo   Kibana         :  %KBURL%
echo   Scratch folder :  %WORK%
echo  ==============================================================
echo.

rem ---------------------------------------------------------------- preflight
call :preflight
if errorlevel 1 exit /b 1

if "!MODE!"=="reset" goto :do_reset
if "!MODE!"=="regen" goto :do_regen
goto :do_setup

rem ===========================================================================
rem  reset
rem ===========================================================================
:do_reset
echo  [reset] removing whatever a previous run of this lab left behind
if exist "%COMPOSEFILE%" docker compose -f "%COMPOSEFILE%" down -v --remove-orphans >nul 2>&1
docker volume rm -f "%VOL%" >nul 2>&1
docker network rm -f "%NETNAME%" >nul 2>&1
docker rm -f "%SCEN%-elasticsearch" "%SCEN%-kibana" >nul 2>&1
echo  [reset] done.
echo.

rem ===========================================================================
rem  compose generation
rem ===========================================================================
:do_regen
echo  [compose] rewriting docker-compose.yml from the settings in this script
call :mkcompose
if errorlevel 1 exit /b 1
goto :do_setup

:do_setup
if exist "%COMPOSEFILE%" (
  echo  [compose] docker-compose.yml already present, reusing it
) else (
  call :mkcompose
  if errorlevel 1 exit /b 1
)

rem --------------------------------------------- refuse a cluster we did not make
call :guardcluster
if errorlevel 1 exit /b 1

rem --------------------------------------- warn, never destroy, on a moved copy
call :checkmoved
if errorlevel 1 exit /b 1

rem =========================================================== 1. bring up ES
rem     Elasticsearch first, on its own. Kibana needs the lab account to exist
rem     before it starts: it refuses to boot against a cluster it cannot
rem     authenticate to, and it refuses to run as the elastic superuser, so
rem     there is no order in which compose could start both and have Kibana
rem     wait. Splitting the two is the only way this works unattended.
echo  [1/10] starting Elasticsearch in Docker
docker compose -f "%COMPOSEFILE%" up -d elasticsearch
if errorlevel 1 (
  call :fail "docker compose up failed" "No data was changed."
  exit /b 1
)
echo.

rem ============================================================= 2. wait: ES
echo  [2/10] waiting for Elasticsearch to answer
set "ESOK="
for /l %%i in (1,1,60) do (
  if not defined ESOK (
    call :docurl -s -o "%WORK%\eshealth.json" %ESAUTH% "%ESURL%/_cluster/health"
    rem  Exclamation marks here, not percent signs.  cmd.exe expands a percent
    rem  variable once, when it parses this whole block, and then runs the
    rem  frozen text on every iteration.  The status code is produced by
    rem  :docurl INSIDE the block, so a percent read would keep comparing the
    rem  code from before the loop started -- always stale, and on a first run
    rem  always "no connection", which made a perfectly healthy Elasticsearch
    rem  look like it had failed to start.  Delayed expansion is re-evaluated
    rem  on each pass, which is what is wanted here.
    if "!CURLCODE!"=="200" findstr /c:"%SCEN%" "%WORK%\eshealth.json" >nul 2>&1 && set "ESOK=1"
    if not defined ESOK (
      ping -n 3 127.0.0.1 >nul 2>&1
      if %%i gtr 2 if %%i lss 60 echo       still starting, attempt %%i of 60
    )
  )
)
if not defined ESOK (
  call :dumpeslog
  call :fail "Elasticsearch did not become ready in time" "The containers are still running so you can inspect them:  docker logs %SCEN%-elasticsearch"
  exit /b 1
)
echo       Elasticsearch is ready.
echo.

rem ================================================== 3. the lab account
echo  [3/10] creating the lab account that Kibana and curl both use
call :mkaccount
if errorlevel 1 exit /b 1
echo.

rem ====================================================== 4. bring up Kibana
echo  [4/10] starting Kibana in Docker
docker compose -f "%COMPOSEFILE%" up -d kibana
if errorlevel 1 (
  call :fail "docker compose up kibana failed" "The log data has not been touched."
  exit /b 1
)
echo.

rem ========================================================== 5. wait: Kibana
echo  [5/10] waiting for Kibana to finish starting
set "KBOK="
for /l %%i in (1,1,150) do (
  if not defined KBOK (
    call :docurl -s -o "%WORK%\kbstatus.json" %KBAUTH% "%KBURL%/api/status"
    if "!CURLCODE!"=="200" findstr /c:"available" "%WORK%\kbstatus.json" >nul 2>&1 && set "KBOK=1"
    if not defined KBOK (
      ping -n 4 127.0.0.1 >nul 2>&1
      if %%i gtr 2 if %%i lss 150 echo       still starting, attempt %%i of 150
    )
  )
)
if not defined KBOK (
  call :dumpkblog
  call :fail "Kibana did not become ready in time" "The containers are still running so you can inspect them:  docker logs %SCEN%-kibana"
  exit /b 1
)
echo       Kibana is available.
echo.

rem ======================================================= 6. index templates
echo  [6/10] installing the index templates, which is what fixes the field types
call :puttemplate auth
if errorlevel 1 exit /b 1
call :puttemplate network
if errorlevel 1 exit /b 1
call :puttemplate dns
if errorlevel 1 exit /b 1
call :puttemplate cloud
if errorlevel 1 exit /b 1
echo.

rem ============================================================ 7. import data
echo  [7/10] checking the datasets
if not exist "%LABDIR%\auth.ndjson"    (call :fail "auth.ndjson is missing from %LABDIR%"    "Nothing was changed." & exit /b 1)
if not exist "%LABDIR%\network.ndjson" (call :fail "network.ndjson is missing from %LABDIR%" "Nothing was changed." & exit /b 1)
if not exist "%LABDIR%\dns.ndjson"     (call :fail "dns.ndjson is missing from %LABDIR%"     "Nothing was changed." & exit /b 1)
if not exist "%LABDIR%\cloud.ndjson"   (call :fail "cloud.ndjson is missing from %LABDIR%"   "Nothing was changed." & exit /b 1)
call :importone auth    %AUTHDOCS%
if errorlevel 1 exit /b 1
call :importone network %NETDOCS%
if errorlevel 1 exit /b 1
call :importone dns     %DNSDOCS%
if errorlevel 1 exit /b 1
call :importone cloud   %CLOUDDOCS%
if errorlevel 1 exit /b 1
echo.

rem ============================================================= 8. data views
echo  [8/10] creating the Kibana data views
call :mkdataview "%SCEN%-auth"    "auth-*"    auth
if errorlevel 1 exit /b 1
call :mkdataview "%SCEN%-network" "network-*" network
if errorlevel 1 exit /b 1
call :mkdataview "%SCEN%-dns"     "dns-*"     dns
if errorlevel 1 exit /b 1
call :mkdataview "%SCEN%-cloud"   "cloud-*"   cloud
if errorlevel 1 exit /b 1
echo.

rem ============================================== 9. the detection rules
echo  [9/10] installing the five detection rules, so the Alerts page has something
call :mkrule
if errorlevel 1 exit /b 1
echo.

rem ============================================== 10. end-to-end truth verify
rem     :verify is called and its status is checked.  In the reference labs
rem     :verify only ever aborts because :fail exits the whole script; a helper
rem     that returns non-zero WITHOUT calling :fail lets the run carry on and
rem     print "The lab is ready" over a lab that verified nothing.  Checking the
rem     status closes that hole.
call :verify
if errorlevel 1 (
  call :fail "the verification pass did not complete" "Nothing was deleted. The messages above say which check disagreed with the live index."
  exit /b 1
)

rem ================================================================= 11. done
echo  ==============================================================
echo    The lab is ready.
echo.
echo    Elasticsearch : %ESURL%
echo    Kibana        : %KBURL%
echo    data view "auth"      index pattern auth-*
echo    data view "network"   index pattern network-*
echo    data view "dns"       index pattern dns-*
echo    data view "cloud"     index pattern cloud-*
echo.
echo    The stack has security switched on, so there are two things to type.
echo    They are lab credentials. They protect nothing.
echo.
echo      Kibana login   %KBUSER%  /  %KBPASS%
echo      in curl        -u %KBUSER%:%KBPASS%
echo.
echo    Telemetry in this lab covers 2026-03-25 to 2026-09-30. Set the Kibana
echo    time range picker to that whole window before you draw any conclusion,
echo    or every count you see will be wrong.
echo.
echo    Times in the data are stored in UTC. Kibana prints them in your own
echo    computer's timezone, so read the clock times off your own screen and
echo    judge the gaps between events, not the absolute numbers.
echo.
echo    There are no investigation queries printed here. Choosing what to run,
echo    and in what order, is the examination.
echo.
echo    Security -^> Alerts and Security -^> Rules are both populated.
echo    Four data views are listed under Discover.
echo.
echo    Your brief, and the form you submit on, is  submission.html
echo      Open it in any browser. It needs no server and no internet.
echo.
echo  ---------------------------------------------------------------------
echo.
echo    Stop the lab but keep the data
echo      docker compose -f docker-compose.yml down
echo.
echo    Remove the lab completely
echo      teardown.cmd
echo.
echo  ==============================================================
echo.

if "%LAUNCH%"=="1" (
  echo  Opening Kibana in your default browser...
  echo  Log in with  %KBUSER%  /  %KBPASS%
  start "" "%KBURL%/app/security/alerts"
  if exist "%LABDIR%\submission.html" start "" "%LABDIR%\submission.html"
)
echo  Press any key to close this window.
pause >nul
exit /b 0


rem ===========================================================================
rem  S U B R O U T I N E S
rem ===========================================================================

:preflight
if not exist "%WORK%" mkdir "%WORK%" >nul 2>&1
if not exist "%WORK%" (
  call :fail "cannot create the scratch folder %WORK%" "Nothing was changed."
  exit /b 1
)
where docker >nul 2>&1
if errorlevel 1 (
  echo  ERROR: "docker" was not found on this computer.
  echo.
  echo    This lab runs Elasticsearch and Kibana inside Docker containers.
  echo    Install Docker Desktop, start it, wait until it says "Engine running",
  echo    then run this file again.
  echo.
  call :fail "" "Nothing was changed."
  exit /b 1
)
set "DVER="
for /f "usebackq delims=" %%v in (`docker version --format "{{.Server.Version}}" 2^>nul`) do if not defined DVER set "DVER=%%v"
if not defined DVER (
  echo  ERROR: Docker is installed but the engine is not responding.
  echo.
  echo    Open Docker Desktop and wait until it says "Engine running", then run
  echo    this file again.
  echo.
  call :fail "" "Nothing was changed."
  exit /b 1
)
echo  [preflight] docker engine version !DVER!
echo  [preflight] every object will be named from the folder name "%SCEN%"
exit /b 0

rem ------------------------------------------- refuse somebody else's cluster

:guardcluster
if not exist "%COMPOSEFILE%" (
  call :fail "docker-compose.yml is missing" "Run  setup-lab.cmd regen-compose  to rewrite it."
  exit /b 1
)
call :docurl -s -o "%WORK%\guard.json" %ESAUTH% "%ESURL%/_cluster/health"
if "%CURLCODE%"=="000" exit /b 0
if "%CURLCODE%"=="401" exit /b 0
findstr /c:"%SCEN%" "%WORK%\guard.json" >nul 2>&1
if not errorlevel 1 exit /b 0
echo  ERROR: something else is already using port %ESPORT%.
echo.
echo    An Elasticsearch is answering on %ESURL%, but it is not the cluster
echo    this lab created, so its name is not "%SCEN%". This script will not
echo    touch a cluster it did not start, and it has changed nothing.
echo.
echo    Fix it one of these ways
echo      - stop the other stack, find it with   docker ps
echo      - change ESPORT and KBPORT at the top of setup-lab.cmd and re-run
echo      - run teardown.cmd inside the folder that owns the other cluster
echo.
echo    For the record, that other cluster says:
type "%WORK%\guard.json" | findstr /c:"cluster_name"
echo.
call :fail "" "Nothing was changed."
exit /b 1

rem ------------------------------- warn, never destroy, on a moved copy of self

:checkmoved
docker inspect "%SCEN%-elasticsearch" --format "{{index .Config.Labels \"com.docker.compose.project.working_dir\"}}" >"%WORK%\moved.txt" 2>&1
if errorlevel 1 exit /b 0
set "MOVED="
for /f "usebackq delims=" %%v in ("%WORK%\moved.txt") do if not defined MOVED set "MOVED=%%v"
if not defined MOVED exit /b 0
if /i "!MOVED!"=="%LABDIR%" exit /b 0
echo  WARNING: a container called "%SCEN%-elasticsearch" already exists, and it
echo            was created from a different folder.
echo.
echo    existing container : %SCEN%-elasticsearch
echo    created from       : !MOVED!
echo    this folder        : %LABDIR%
echo.
docker inspect "%SCEN%-elasticsearch" --format "    status {{.State.Status}}   image {{.Config.Image}}" 2>&1
docker inspect "%SCEN%-elasticsearch" --format "    volume {{range .Mounts}}{{.Name}}{{end}}" 2>&1
docker inspect "%SCEN%-elasticsearch" --format "    ports  {{range $p, $c := .NetworkSettings.Ports}}{{$p}}->{{$c}}{{println}}{{end}}" 2>&1
echo.
echo    This usually means the lab folder was copied. setup-lab.cmd will NOT
echo    destroy the other copy. To start over on purpose, remove it yourself:
echo.
echo      docker rm -f "%SCEN%-elasticsearch" "%SCEN%-kibana"
echo      docker volume rm -f "%VOL%"
echo.
echo    or run  teardown.cmd  which lists and confirms before it deletes.
echo.
call :fail "" "Nothing was deleted."
exit /b 1

rem ------------------------------- write docker-compose.yml from this script
rem     The file this writes is byte-for-byte the file setup-lab.sh writes for
rem     the same folder. Keep the two in step or a Windows lab and a Mac lab
rem     stop being the same lab.

:mkcompose
rem     Only the FIRST line below truncates.  Every other line must append.
rem     This used to open with four ">" lines and then switch to ">>", which
rem     meant each of those four silently truncated everything written before
rem     it: the generated docker-compose.yml came out with NO header at all,
rem     starting straight at "name: final_exam".  Compose did not care and the
rem     file was still valid, which is exactly why it went unnoticed -- but the
rem     header above claims this file is byte-for-byte the one setup-lab.sh
rem     writes, and it was not.
>  "%COMPOSEFILE%" echo # Generated by setup-lab.cmd
>> "%COMPOSEFILE%" echo # Every name and port below is derived from the folder this file
>> "%COMPOSEFILE%" echo # lives in, so the file is safe to delete and regenerate:
>> "%COMPOSEFILE%" echo #     setup-lab.cmd regen-compose
>> "%COMPOSEFILE%" echo name: %SCEN%
>> "%COMPOSEFILE%" echo services:
>> "%COMPOSEFILE%" echo   elasticsearch:
>> "%COMPOSEFILE%" echo     image: %ESIMAGE%
>> "%COMPOSEFILE%" echo     container_name: %SCEN%-elasticsearch
>> "%COMPOSEFILE%" echo     environment:
>> "%COMPOSEFILE%" echo       - node.name=es01
>> "%COMPOSEFILE%" echo       - cluster.name=%SCEN%
>> "%COMPOSEFILE%" echo       - discovery.type=single-node
>> "%COMPOSEFILE%" echo       - bootstrap.memory_lock=true
>> "%COMPOSEFILE%" echo       - xpack.security.enabled=true
>> "%COMPOSEFILE%" echo       - ELASTIC_PASSWORD=%ESBOOT%
>> "%COMPOSEFILE%" echo       - xpack.ml.enabled=false
>> "%COMPOSEFILE%" echo       - ingest.geoip.downloader.enabled=false
>> "%COMPOSEFILE%" echo       - ES_JAVA_OPTS=-Xms1g -Xmx1g
>> "%COMPOSEFILE%" echo     ulimits:
>> "%COMPOSEFILE%" echo       memlock:
>> "%COMPOSEFILE%" echo         soft: -1
>> "%COMPOSEFILE%" echo         hard: -1
>> "%COMPOSEFILE%" echo     volumes:
>> "%COMPOSEFILE%" echo       - "%VOL%:/usr/share/elasticsearch/data"
>> "%COMPOSEFILE%" echo     ports:
>> "%COMPOSEFILE%" echo       - "127.0.0.1:%ESPORT%:9200"
>> "%COMPOSEFILE%" echo     healthcheck:
>> "%COMPOSEFILE%" echo       test: ["CMD-SHELL","curl -s -u %ESUSER%:%ESBOOT% -o /dev/null http://localhost:9200/_cluster/health || exit 1"]
>> "%COMPOSEFILE%" echo       interval: 10s
>> "%COMPOSEFILE%" echo       timeout: 6s
>> "%COMPOSEFILE%" echo       retries: 40
>> "%COMPOSEFILE%" echo     networks:
>> "%COMPOSEFILE%" echo       - lab
>> "%COMPOSEFILE%" echo   kibana:
>> "%COMPOSEFILE%" echo     image: %KBIMAGE%
>> "%COMPOSEFILE%" echo     container_name: %SCEN%-kibana
>> "%COMPOSEFILE%" echo     depends_on:
>> "%COMPOSEFILE%" echo       elasticsearch:
>> "%COMPOSEFILE%" echo         condition: service_healthy
>> "%COMPOSEFILE%" echo     environment:
>> "%COMPOSEFILE%" echo       - ELASTICSEARCH_HOSTS=["http://elasticsearch:9200"]
>> "%COMPOSEFILE%" echo       - ELASTICSEARCH_USERNAME=%KBUSER%
>> "%COMPOSEFILE%" echo       - ELASTICSEARCH_PASSWORD=%KBPASS%
>> "%COMPOSEFILE%" echo       - SERVER_HOST=0.0.0.0
>> "%COMPOSEFILE%" echo       - SERVER_PUBLICBASEURL=http://localhost:%KBPORT%
>> "%COMPOSEFILE%" echo       - TELEMETRY_ENABLED=false
>> "%COMPOSEFILE%" echo       - SECURITY_SHOWINSECURECLUSTERWARNING=false
>> "%COMPOSEFILE%" echo       - XPACK_REPORTING_ENABLED=false
>> "%COMPOSEFILE%" echo       - I18N_LOCALE=en
rem     Kibana will not start a detection rule at all without an encryption key
rem     for its saved objects, and it throws one away on every restart, so the
rem     rule you just installed would vanish the next time the container is
rem     recreated. Both keys are fixed here for that reason - and the reason is
rem     written into the generated file too, so it is still there next to the
rem     keys six months from now, when nobody remembers this comment.
>> "%COMPOSEFILE%" echo       #  Kibana will not start a detection rule at all without an encryption key
>> "%COMPOSEFILE%" echo       #  for its saved objects, and it throws one away on every restart, so the
>> "%COMPOSEFILE%" echo       #  rule just installed would vanish the next time the container is
>> "%COMPOSEFILE%" echo       #  recreated. Both keys are fixed above for that reason.
>> "%COMPOSEFILE%" echo       - XPACK_ENCRYPTEDSAVEDOBJECTS_ENCRYPTIONKEY=%SCEN%labencryptedsavedobjects000001
>> "%COMPOSEFILE%" echo       - XPACK_SECURITY_ENCRYPTIONKEY=%SCEN%labsecurityencryptionkey0000001
>> "%COMPOSEFILE%" echo     ports:
>> "%COMPOSEFILE%" echo       - "127.0.0.1:%KBPORT%:5601"
>> "%COMPOSEFILE%" echo     healthcheck:
>> "%COMPOSEFILE%" echo       test: ["CMD-SHELL","curl -s http://localhost:5601/api/status | grep -q available || exit 1"]
>> "%COMPOSEFILE%" echo       interval: 10s
>> "%COMPOSEFILE%" echo       timeout: 6s
>> "%COMPOSEFILE%" echo       retries: 60
>> "%COMPOSEFILE%" echo     networks:
>> "%COMPOSEFILE%" echo       - lab
>> "%COMPOSEFILE%" echo networks:
>> "%COMPOSEFILE%" echo   lab:
>> "%COMPOSEFILE%" echo     name: %NETNAME%
>> "%COMPOSEFILE%" echo     driver: bridge
>> "%COMPOSEFILE%" echo volumes:
>> "%COMPOSEFILE%" echo   "%VOL%":
>> "%COMPOSEFILE%" echo     name: "%VOL%"
if not exist "%COMPOSEFILE%" (
  call :fail "could not write docker-compose.yml" "Nothing else was started."
  exit /b 1
)
echo  [compose] wrote %COMPOSEFILE%
exit /b 0

rem ------------------------------------------------- create the lab account
rem  Kibana will not run as the built-in elastic account, and an account that
rem  only has the superuser role still cannot create the .kibana* saved-object
rem  indices, so the lab account carries superuser together with the built-in
rem  kibana_system role. Creating it is safe to repeat: the second run finds
rem  the account and rewrites the same password, which is what makes a changed
rem  KBPASS at the top of this file take effect.

:mkaccount
rem  No parentheses and no full_name in the body: a round bracket is a cmd
rem  metacharacter and this line is an unquoted echo, so keeping the body free
rem  of them removes a whole class of surprise for no loss.
>  "%WORK%\acct.json" echo {"password":"!KBPASS!","roles":["superuser","kibana_system"]}
call :docurl -s -o "%WORK%\acct-resp.json" -X PUT "%ESURL%/_security/user/%KBUSER%" -H "Content-Type: application/json" %ESAUTH% --data-binary "@%WORK%\acct.json"
if not "%CURLCODE%"=="200" if not "%CURLCODE%"=="201" (
  call :fail "could not create the lab account %KBUSER%, HTTP %CURLCODE%" "Nothing was deleted. The Elasticsearch log says why:  docker logs %SCEN%-elasticsearch"
  exit /b 1
)
echo       account %KBUSER% ready
exit /b 0

rem ------------------------------------------------- install all five rules
rem  Without a fired rule the Alerts page renders nothing at all. They are
rem  installed through Kibana rather than through Elasticsearch's own rule API,
rem  because Kibana is what actually runs the alerting engine and what writes
rem  the alerts the page reads.
rem
rem  They are deliberately idempotent by name. The create route always mints a
rem  new rule id and there is no update-by-id route, so a second run would install
rem  a second copy and every alert would be counted twice. Counting first is
rem  cheap and needs only a single number back, which is the one thing a batch
rem  file can parse without ceremony.
:mkrule
rem  Five explicit calls rather than "for %%F in (...) do call :onerule %%F".
rem  In a FOR body the errorlevel of the CALL is not checked between iterations,
rem  so a failure on the first rule still runs the other four -- and :fail pauses,
rem  so the operator watches the same failure five times before the script stops.
rem  None of the three reference labs uses for-do-call either.
call :onerule rule.json   "%RULENAME1%"
if errorlevel 1 exit /b 1
call :onerule rule-2.json "%RULENAME2%"
if errorlevel 1 exit /b 1
call :onerule rule-3.json "%RULENAME3%"
if errorlevel 1 exit /b 1
call :onerule rule-4.json "%RULENAME4%"
if errorlevel 1 exit /b 1
call :onerule rule-5.json "%RULENAME5%"
if errorlevel 1 exit /b 1

rem  The rules run on a one minute schedule, so the first alerts cannot exist
rem  for up to a minute. Rather than guess, poll the index the Alerts page
rem  reads and insist on the exact total this lab ships. If this passes, the
rem  page cannot be empty and cannot be wrong, whatever Kibana's UI decides to
rem  render.
echo       waiting for the rules to fire
set "ALERTOK="
for /l %%i in (1,1,60) do (
  if not defined ALERTOK (
    call :docurl -s -o "%WORK%\alerts.json" %ESAUTH% "%ESURL%/.alerts-security.alerts-default/_count?filter_path=count"
    if "!CURLCODE!"=="200" (
      for /f "tokens=2 delims=:,{}" %%a in ('type "%WORK%\alerts.json"') do if not defined ALERTOK if "%%a"=="%TOTALS%" set "ALERTOK=1"
    )
    if not defined ALERTOK (
      ping -n 6 127.0.0.1 >nul 2>&1
      if %%i gtr 1 if %%i lss 60 echo       still waiting, attempt %%i of 60
    )
  )
)
if not defined ALERTOK (
  call :fail "the rules are installed but the Alerts page does not hold %TOTALS% alerts" "Nothing was deleted. Check  docker logs %SCEN%-kibana  for the rules' execution status, and remember the rules only match data from the last 365 days."
  exit /b 1
)
rem  Per-rule counts are asserted too, because a lab that calls itself ready
rem  with the right total and the wrong distribution is worse than one that
rem  refuses to start.
call :verifyrules
if errorlevel 1 exit /b 1
echo       the Alerts page holds exactly %TOTALS% alerts, distributed correctly
exit /b 0

rem  Install one rule, if it is not already on the cluster.
:onerule
rem     %~1 rule file    %~2 rule name, quoted by the caller because it has
rem                        spaces in it
set "RF=%~1"
if not exist "%LABDIR%\%RF%" (
  call :fail "%RF% is missing from %LABDIR%" "The rest of the lab is fine. Put %RF% back and re-run to get the Alerts page working."
  exit /b 1
)
rem  A match_phrase on the rule's name is used rather than a term on its
rem  keyword subfield.  The keyword subfield is normalised to lower case, and
rem  cmd.exe has no way to lower-case a string without a loop that is easy to
rem  get wrong; an analysed text match is already case-insensitive, so the name
rem  can be written here exactly as it is written in the rule file.
set "RULENAME=%~2"
set "RN=%~2"
>  "%WORK%\rulefind.json" echo {"query":{"match_phrase":{"alert.name":"!RULENAME!"}}}
call :esdocount ".kibana_alerting_cases*" "RULEN" "%WORK%\rulefind.json"
if errorlevel 1 exit /b 1
if not "!RULEN!"=="0" (
  echo       already installed, leaving it alone: !RN:~0,48!
  exit /b 0
)
rem  Kibana answers /api/status a moment before it will accept a rule
rem  creation: for a short window after start-up it refuses internal APIs
rem  and answers "not available with the current configuration".  Waiting for the
rem  status page is therefore not enough on its own, so the call is retried a
rem  few times before it is called a failure.
set "RULEOK="
for /l %%i in (1,1,6) do (
  if not defined RULEOK (
    call :docurl -s -o "%WORK%\rule-resp.json" -X POST "%KBURL%/api/detection_engine/rules" -H "kbn-xsrf: true" -H "Content-Type: application/json" %KBAUTH% --data-binary "@%LABDIR%\!RF!"
    if "!CURLCODE!"=="200" set "RULEOK=1"
    if not defined RULEOK (
      ping -n 5 127.0.0.1 >nul 2>&1
      if %%i lss 6 echo       Kibana is not accepting rules yet, retry %%i of 6
    )
  )
)
if not defined RULEOK (
  call :fail "Kibana refused !RF!, HTTP !CURLCODE!" "The log data is still loaded. The reason is in %WORK%\rule-resp.json and in  docker logs %SCEN%-kibana"
  exit /b 1
)
echo       installed: !RN:~0,48!
exit /b 0

rem ------------- assert each rule's own alert count, without printing it
rem  A lab that calls itself ready with the right total and the wrong
rem  distribution is worse than one that refuses to start, so the per-rule
rem  figures are checked as well.
:verifyrules
set /a WVI=0
call :onerulecount rule.json   "%RULENAME1%" %R1ALERTS%
if errorlevel 1 exit /b 1
call :onerulecount rule-2.json "%RULENAME2%" %R2ALERTS%
if errorlevel 1 exit /b 1
call :onerulecount rule-3.json "%RULENAME3%" %R3ALERTS%
if errorlevel 1 exit /b 1
call :onerulecount rule-4.json "%RULENAME4%" %R4ALERTS%
if errorlevel 1 exit /b 1
call :onerulecount rule-5.json "%RULENAME5%" %R5ALERTS%
if errorlevel 1 exit /b 1
echo       every rule fired exactly the number of times the lab ships
exit /b 0

:onerulecount
rem     %~1 rule file   %~2 rule name (quoted)   %~3 expected alerts
set /a WVI+=1
set "RF=%~1"
set "RN=%~2"
set "WANT=%~3"
rem     Note the field name.  The rule DEFINITION lives in .kibana_alerting_cases
rem     and is matched on alert.name; the alert DOCUMENTS this counts live in
rem     .alerts-security.alerts-default and carry the rule's name under
rem     kibana.alert.rule.name.  Two indices, two different field names, and the
rem     easy mistake is to use the first one here.
echo {"query":{"match_phrase":{"kibana.alert.rule.name":"!RN!"}}} > "%WORK%\rf-!WVI!.json"
call :esdocount ".alerts-security.alerts-default*" "AN" "%WORK%\rf-!WVI!.json"
if errorlevel 1 exit /b 1
if not "!AN!"=="!WANT!" (
  echo  MISMATCH  detection rule !WVI! produced !AN! alerts, the lab ships !WANT!.
  call :fail "a rule did not fire the number of times the lab was built around" "Nothing was deleted. Run  setup-lab.cmd reset  to rebuild from the shipped data."
  exit /b 1
)
exit /b 0

:puttemplate
set "TPL=%~1"
if not exist "%LABDIR%\%~1.json" (
  call :fail "the index template %~1.json is missing" "Nothing was changed."
  exit /b 1
)
call :docurl -s -o "%WORK%\tpl-%TPL%.json" -X PUT "%ESURL%/_index_template/%TPL%" -H "Content-Type: application/json" %ESAUTH% --data-binary "@%LABDIR%\%TPL%.json"
if not "%CURLCODE%"=="200" if not "%CURLCODE%"=="201" (
  call :fail "the index template for %TPL% was not accepted, HTTP %CURLCODE%" "No data was imported. Fix %TPL%.json and run this file again."
  exit /b 1
)
echo       %TPL% template accepted
exit /b 0

rem --------------------------------------------- import one dataset, idempotent
:importone
set "DS=%~1"
set "EXP=%~2"
call :esdocount "%DS%*" NDC
if errorlevel 1 exit /b 1
if "!NDC!"=="0" (
  echo       %DS%: no documents loaded yet, importing %EXP% documents
  call :dopost
  if errorlevel 1 exit /b 1
  goto :recount
)
if "!NDC!"=="%EXP%" (
  echo       %DS%: already fully loaded at !NDC! documents, nothing to import
  goto :recount
)
if !NDC! gtr %EXP% (
  echo       %DS%: index holds !NDC! documents, more than the %EXP% this lab ships
  echo       leaving it alone rather than guessing
  goto :recount
)
echo  ERROR: the %DS% index holds !NDC! documents but this lab ships %EXP%.
echo.
echo    Importing now would create duplicates and every count in the exam
echo    would be wrong. This script will not import on top of a partial load,
echo    and it has deleted nothing.
echo.
echo    To rebuild this dataset from scratch
echo      setup-lab.cmd reset
echo    or delete the indices by hand
echo      curl -XDELETE %ESURL%/%DS%-*
echo.
call :fail "" "Nothing was deleted."
exit /b 1
:recount
call :esdocount "%DS%*" NDC2
if errorlevel 1 exit /b 1
if not "!NDC2!"=="%EXP%" (
  call :fail "%DS% should hold %EXP% documents after import but holds !NDC2!" "Nothing was deleted. The next run will detect this and stop rather than duplicate data."
  exit /b 1
)
echo       %DS%: verified !NDC2! documents across its monthly indices
exit /b 0

rem -------------------------------------------------------- the bulk import
rem  This lab ships six months of history, so it writes one index per month
rem  rather than one per day: 2026.03 .. 2026.09 for each dataset. The data view
rem  pattern is still %DS%-* so the student never has to pick an index by name.
rem  The month is read out of the first seven characters of the document's own
rem  @timestamp, so the index name and the data inside it cannot drift apart.
:dopost
set "NDJ=%WORK%\bulk-%DS%.ndjson"
type nul > "%NDJ%"
for /f "usebackq delims=" %%L in ("%LABDIR%\!DS!.ndjson") do (
rem     Pull the month out of the document's own @timestamp.
rem
rem     Every line of every dataset begins with the same 16 characters:
rem         {"@timestamp": "
rem     so the month is simply characters 17 to 23.  One substring expansion,
rem     no external process, and -- the reason this is not written the obvious
rem     way -- no quote character anywhere in the statement.
rem
rem     DO NOT write this as  set "YM=%%L:~16,7%"  .  That does not do what it
rem     looks like.  cmd.exe's ~ substring and substitution modifiers apply to
rem     the ARGUMENT variables %0..%9 and to the loop variable of a FOR /F only
rem     as a plain substitution; the ~ modifier is silently NOT applied to a
rem     FOR variable.  What it does instead is substitute the whole line and
rem     leave the ":~16,7" behind as literal text, so YM comes out as the entire
rem     document followed by ":~16,7", it never equals any month, SUF is never
rem     set, and every single run of this script dies on the FIRST line of the
rem     FIRST dataset with "a document in auth.ndjson is dated outside the lab
rem     window" -- which reads exactly like broken data and is not.
rem
rem     The working spelling is the two lines below.  Copy the line into an
rem     ordinary variable, then take the substring with DELAYED expansion, which
rem     does honour ~.  This is the same operation the .sh twin performs as
rem     MONTH=${L:16:7}, and the two stay in step by construction.
rem
rem     One caveat, and it is checked rather than assumed: delayed expansion
rem     scans the line for "!", so a document containing a literal exclamation
rem     mark would be mangled on its way into L.  All four shipped datasets are
rem     free of them.  If a future dataset is not, escape them at source.
rem
rem     Note also that "echo %%L" below is safe even though these documents
rem     contain ">" and "<" characters inside their message fields.  cmd.exe
rem     resolves redirect operators from the statement text BEFORE the FOR
rem     variable is substituted, so a > arriving in the data is data, not a
rem     redirect.
  set "L=%%L"
  set "YM=!L:~16,7!"
  if /i "!YM!"=="2026-03" set "SUF=2026.03"
  if /i "!YM!"=="2026-04" set "SUF=2026.04"
  if /i "!YM!"=="2026-05" set "SUF=2026.05"
  if /i "!YM!"=="2026-06" set "SUF=2026.06"
  if /i "!YM!"=="2026-07" set "SUF=2026.07"
  if /i "!YM!"=="2026-08" set "SUF=2026.08"
  if /i "!YM!"=="2026-09" set "SUF=2026.09"
  if not defined SUF (
    call :fail "a document in !DS!.ndjson is dated outside the lab window" "No documents were imported. Fix the dataset and run this file again."
    exit /b 1
  )
  >> "%NDJ%" echo {"index":{"_index":"!DS!-!SUF!"}}
  >> "%NDJ%" echo %%L
  set "SUF="
)
rem     filter_path=errors makes Elasticsearch answer with exactly
rem     {"errors":false} and nothing else - sixteen bytes, with no trailing
rem     newline - so the check is a byte comparison against a file this script
rem     wrote.  The expected file is written with <nul set /p and deliberately
rem     without a line ending; a plain echo appends CRLF, which makes a healthy
rem     import look like a failed one.
call :docurl -s -o "%WORK%\bulk-%DS%.json" -X POST "%ESURL%/_bulk?refresh=wait_for&filter_path=errors" -H "Content-Type: application/x-ndjson" %ESAUTH% --data-binary "@%NDJ%"
<nul set /p "={"errors":false}" > "%WORK%\bulkok.txt"
fc /b "%WORK%\bulkok.txt" "%WORK%\bulk-%DS%.json" >nul 2>&1
if errorlevel 1 (
  call :fail "the bulk import for %DS% reported errors, see %WORK%\bulk-%DS%.json" "No documents were deleted. Run  setup-lab.cmd reset  and try again."
  exit /b 1
)
echo       %DS%: %EXP% documents accepted by Elasticsearch
exit /b 0

:mkdataview
set "DVNAME=%~1"
set "DVPAT=%~2"
rem %~3 is a file-name-safe spelling of the pattern, because * is not a legal
rem character in a path
set "DVFILE=%WORK%\dv-%~3.json"
> "%DVFILE%" echo {"attributes":{"title":"!DVPAT!","timeFieldName":"@timestamp"},"references":[]}
call :docurl -s -o "%WORK%\dv-resp.json" -X POST "%KBURL%/api/saved_objects/index-pattern/!DVNAME!?overwrite=true" -H "kbn-xsrf: true" -H "Content-Type: application/json" %KBAUTH% --data-binary "@%DVFILE%"
if not "%CURLCODE%"=="200" (
  call :fail "Kibana refused to create the data view !DVPAT!, HTTP %CURLCODE%" "The log data is still loaded. Check  docker logs %SCEN%-kibana  and run this file again."
  exit /b 1
)
rem     The ampersands in the URL below are written BARE, on purpose.  CALL
rem     makes cmd.exe parse this line a second time, and on that second pass a
rem     caret in the command text is doubled: "^&" reaches curl.exe as "^^&",
rem     so Kibana is asked for a query string full of carets and answers 400.
rem     A bare & typed inside a quoted argument survives both parses intact.
rem     Do not "tidy" this into a variable either - see the note in :esdocount.
call :docurl -s -o "%WORK%\dv-find.json" %KBAUTH% "%KBURL%/api/saved_objects/_find?type=index-pattern&search_fields=title&search=!DVPAT!&fields=title&per_page=50"
findstr /c:"!DVPAT!" "%WORK%\dv-find.json" >nul 2>&1
if errorlevel 1 (
  echo  ERROR: the data view was created but the pattern "!DVPAT!" was not stored.
  echo.
  echo    A data view with an empty index pattern matches no index at all, so
  echo    Discover would show zero fields and no results and there would be no
  echo    visible reason why. That is the most confusing failure mode of this
  echo    lab, so it is checked here instead of being left for you to find.
  echo.
  echo    Fix it with
  echo      setup-lab.cmd reset
  echo.
  call :fail "" "The log data was not touched."
  exit /b 1
)
echo       data view "!DVPAT!" verified, time field @timestamp
exit /b 0

rem ---------------------------------------- end-to-end structural verification

:verify
echo  [verify] reading the lab back out of Elasticsearch
rem  Deliberately shallow.  This checks that the four datasets landed at the
rem  documented totals and that the four data views resolve and expose their
rem  fields - things the student can verify for themselves, so nothing here is
rem  a hint.  It does NOT assert anything the exam grades.  See the header at
rem  the top of this file for why, and solution.md for the real ground truth.
rem
rem  Every assertion is a COUNT read as a bare integer, because that is the
rem  only shape cmd.exe can compare reliably.
>  "%WORK%\k0.txt" echo match_all
call :vqcount "auth-*"    "auth documents             "  %AUTHDOCS%  k0.txt
if errorlevel 1 exit /b 1
call :vqcount "network-*"    "network documents          "  %NETDOCS%  k0.txt
if errorlevel 1 exit /b 1
call :vqcount "dns-*"    "dns documents              "  %DNSDOCS%  k0.txt
if errorlevel 1 exit /b 1
call :vqcount "cloud-*"    "cloud documents            "  %CLOUDDOCS%  k0.txt
if errorlevel 1 exit /b 1
call :verifyviews
if errorlevel 1 exit /b 1
echo  [verify] every check matches the live index.
echo.
exit /b 0

rem -------------------- assert one count, so no number is typed in two places
rem     %~4 is a file in %WORK% holding one KQL string, with its inner double
rem     quotes already backslash-escaped for the JSON string they land in.
:vqcount
set "VQIDX=%~1"
set "VQLBL=%~2"
set "VQEXP=%~3"
set "VQF=%WORK%\vq.json"
set "VQK=%WORK%\%~4"
set "VQKQ="
set /p VQKQ=<"%VQK%"
rem  A missing or empty fixture file leaves VQKQ undefined, which falls through
rem  to the match_all branch below and quietly counts EVERY document in the
rem  index -- turning a broken install into a green run.  An empty fixture is a
rem  broken lab, not a query that means "everything".
if not defined VQKQ (
  call :fail "the verification query %VQK% is missing or empty" "No data was deleted. This is a broken install of the lab, not broken data."
  exit /b 1
)
rem  The literal word match_all means "count everything in the index" and is
rem  turned into a real match_all query.  A bare * would be turned into a
rem  fieldless wildcard instead, which currently returns the same count but
rem  says "everything" by accident rather than on purpose.
if /i "!VQKQ!"=="match_all" (
  > "%VQF%" echo {"size":0,"track_total_hits":true,"query":{"match_all":{}}}
  goto :vqgo
)
> "%VQF%" echo {"size":0,"track_total_hits":true,"query":{"kql":{"query":"!VQKQ!"}}}
:vqgo
call :eskqlcount "!VQIDX!" VQCNT
if errorlevel 1 exit /b 1
if not "!VQCNT!"=="%VQEXP%" (
  echo  MISMATCH  !VQLBL!
  echo            the lab was built around %VQEXP% but the index reports !VQCNT!
  call :fail "a dataset does not match the loaded data" "Nothing was deleted. Run  setup-lab.cmd reset  to rebuild the data exactly as shipped."
  exit /b 1
)
exit /b 0

:verifyviews
call :vdcheck auth    "auth-*"    "event.code"
if errorlevel 1 exit /b 1
call :vdcheck network "network-*" "network.protocol"
if errorlevel 1 exit /b 1
call :vdcheck dns     "dns-*"     "dns.question.type"
if errorlevel 1 exit /b 1
call :vdcheck cloud   "cloud-*"   "oauth.application.name"
if errorlevel 1 exit /b 1
rem     The exit has to be HERE, after the fourth check, and it has to be an
rem     explicit exit rather than a fall-through: the subroutine below is the
rem     very next label, so control running off the end would re-check whatever
rem     the caller happened to pass.  It used to sit one check too early, which
rem     silently skipped the last two data views.
exit /b 0

:vdcheck
call :docurl -s -o "%WORK%\vd-%~1.json" %KBAUTH% "%KBURL%/api/data_views/data_view/%SCEN%-%~1" -H "kbn-xsrf: true"
if not "%CURLCODE%"=="200" (
  echo.
  echo  ERROR: Kibana cannot resolve the "%~2" data view, HTTP %CURLCODE%.
  echo.
  echo    The saved object exists but its index pattern matches no index, or
  echo    Kibana cannot read the mapping. Discover would show zero fields and
  echo    no results and there would be no visible reason why.
  echo.
  echo    Rebuild it with
  echo      setup-lab.cmd reset
  echo.
  call :fail "" "The log data was not touched."
  exit /b 1
)
rem  The three checks below look for a bare word rather than for a quoted JSON
rem  key, and that is on purpose.  cmd.exe has no backslash escape, so
rem  findstr /c:"\"title\":..." is not a dependable way to ask for a quote
rem  character: the backslashes reach findstr as literal backslashes and the
rem  search silently never matches, which would report a healthy lab as broken.
rem  Each bare word below occurs in this response only when the thing it names
rem  is really there - the pattern appears once, in the title; the time field
rem  key appears once; the field name appears only inside the resolved mapping.
findstr /c:"%~2" "%WORK%\vd-%~1.json" >nul 2>&1
if errorlevel 1 (
  call :fail "the %~2 data view did not resolve to the pattern %~2" "The log data was not touched. Run  setup-lab.cmd reset  to rebuild the data view."
  exit /b 1
)
findstr /c:"timeFieldName" "%WORK%\vd-%~1.json" >nul 2>&1
if errorlevel 1 (
  call :fail "the %~2 data view has no @timestamp time field" "The log data was not touched. Run  setup-lab.cmd reset  to rebuild the data view."
  exit /b 1
)
findstr /c:"%~3" "%WORK%\vd-%~1.json" >nul 2>&1
if errorlevel 1 (
  call :fail "the %~2 data view does not expose the field %~3 to Discover" "The log data was not touched. Run  setup-lab.cmd reset  to rebuild the data view."
  exit /b 1
)
echo       data view %~2 resolves, time field @timestamp, field %~3 present
exit /b 0

rem ------------------ the rule has to be there, and it has to be this lab's
rem     Two things can go wrong that nothing else in this script would catch:
rem     the rule can be deleted by hand between runs, and a copy of this lab
rem     folder can be left behind on a shared machine holding a rule with the
rem     same name and a different query. Both are caught here, against the
rem     live cluster.

:esdocount
set "EDIDX=%~1"
set "EDVAR=%~2"
set "EDQ=%~3"
rem     The count URL is written out in full on both CALL lines below, with bare
rem     ampersands, and is deliberately NOT kept in a variable.  This is not
rem     style, it is the only spelling that survives CALL:
rem
rem       in a variable, caret-escaped   set "U=..true^&filter_path=count"
rem             SET consumes the caret, so the variable holds a bare &, and the
rem             second parse that CALL performs doubles it again - curl.exe
rem             receives  allow_no_indices=true^^  and Elasticsearch answers
rem               HTTP 400  illegal_argument_exception
rem                 Failed to parse value [true^^] as only [true] or [false]
rem
rem       in a variable, bare            set "U=..true&filter_path=count"
rem             the & is a command separator on the SET line itself, so the
rem             variable is silently truncated at allow_no_indices=true
rem
rem       inline, caret-escaped          "..true^&filter_path=count"
rem             CALL doubles the caret  ->  ^^&  ->  HTTP 400
rem
rem       inline, bare                  "..true&filter_path=count"   <-- this
rem             the & is inside double quotes on both parses, so it arrives as
rem             a real query-string separator
rem
rem     setup-lab.sh builds the identical URL with a plain &, because bash has
rem     no second parse.  Same URL, same endpoint, opposite outcome - which is
rem     why the two twins disagreed and only the Windows one ever failed.
rem     Verified against Elasticsearch 9.1:  ^^ -> 400,  ^ -> 400,  & -> 200.
call :docurl -s -o nul -X POST %ESAUTH% "%ESURL%/%EDIDX%/_refresh"
if defined EDQ (
  call :docurl -s -o "%WORK%\cnt.json" %ESAUTH% -X POST -H "Content-Type: application/json" --data-binary "@%EDQ%" "%ESURL%/%EDIDX%/_count?allow_no_indices=true&filter_path=count"
) else (
  call :docurl -s -o "%WORK%\cnt.json" %ESAUTH% "%ESURL%/%EDIDX%/_count?allow_no_indices=true&filter_path=count"
)
if not "%CURLCODE%"=="200" (
  call :fail "could not read the document count of %EDIDX%, HTTP %CURLCODE%" "Nothing was changed."
  exit /b 1
)
set "EDVAL="
for /f "tokens=2 delims=:,{}" %%a in ('type "%WORK%\cnt.json"') do if not defined EDVAL set "EDVAL=%%a"
if not defined EDVAL set "EDVAL=0"
set "%EDVAR%=%EDVAL%"
exit /b 0

rem ------------- ES helper: total hits for the query body in %WORK%\vq.json
rem     filter_path collapses the reply to  {"hits":{"total":{"value":N}}}

:eskqlcount
set "EKIDX=%~1"
set "EKVAR=%~2"
call :docurl -s -o nul -X POST %ESAUTH% "%ESURL%/!EKIDX!/_refresh"
call :docurl -s -o "%WORK%\vq.json.out" %ESAUTH% "%ESURL%/!EKIDX!/_search?filter_path=hits.total.value" -X POST -H "Content-Type: application/json" --data-binary "@%WORK%\vq.json"
if not "%CURLCODE%"=="200" (
  call :fail "a verification query against !EKIDX! was rejected, HTTP %CURLCODE%" "Nothing was deleted. The query text is in %WORK%\vq.json"
  exit /b 1
)
set "EKVAL="
for /f "tokens=4 delims=:,{}" %%a in ('type "%WORK%\vq.json.out"') do if not defined EKVAL set "EKVAL=%%a"
set "EKVAL=%EKVAL:}=%"
if not defined EKVAL set "EKVAL=0"
set "%EKVAR%=%EKVAL%"
exit /b 0

rem ------------ HTTP helper that captures the status code, so every call asserts

:docurl
set "CURLCODE="
type nul > "%WORK%\reqhdr.txt"
curl.exe -D "%WORK%\reqhdr.txt" %* >nul 2>&1
for /f "tokens=2" %%a in ('findstr /b HTTP/ "%WORK%\reqhdr.txt"') do if not defined CURLCODE set "CURLCODE=%%a"
if not defined CURLCODE set "CURLCODE=000"
exit /b

rem ---------------------------------------------------- log dumps on timeout

:dumpeslog
echo.
echo  ---- last 40 lines of the Elasticsearch log ----
docker logs --tail 40 "%SCEN%-elasticsearch" 2>&1
echo  -----------------------------------------------------
exit /b 0

:dumpkblog
echo.
echo  ---- last 40 lines of the Kibana log ----
docker logs --tail 40 "%SCEN%-kibana" 2>&1
echo  -----------------------------------------------------
exit /b 0

rem ------------------------------------------------------ one honest failure

:fail
echo.
echo  ==============================================================
echo   FAILED:  %~1
echo.
if not "%~2"=="" echo   %~2
echo.
echo   Nothing outside this %SCEN% lab was touched, and no data was deleted.
echo   Docker images were kept, so the next run starts faster.
echo.
echo   Scratch files :  %WORK%
echo   What is running:  docker ps -a
echo   Compose file :  %COMPOSEFILE%
echo.
echo  ==============================================================
echo.
pause
exit /b 1
