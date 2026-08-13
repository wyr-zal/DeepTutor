@echo off
setlocal EnableExtensions

set "MODE=%~1"
if "%MODE%"=="" set "MODE=both"
if /i not "%MODE%"=="debug" if /i not "%MODE%"=="release" if /i not "%MODE%"=="both" (
  echo [DeepTutor] Invalid build mode: %MODE%. Use debug, release, or both.
  exit /b 2
)

set "FLUTTER_HOME=F:\Dev\Flutter"
set "ANDROID_HOME=F:\Dev\AndroidSdk"
set "ANDROID_AVD_HOME=F:\Dev\AndroidAvd"
set "PUB_CACHE=F:\Dev\PubCache"
set "GRADLE_USER_HOME=F:\Dev\Caches\gradle"
set "JAVA_HOME=D:\Develop\JDK\jdk21"

rem Ambient Windows variables must not silently redirect shared build caches.
rem Use the DeepTutor-prefixed variables only when an explicit override is needed.
if defined DEEPTUTOR_FLUTTER_HOME set "FLUTTER_HOME=%DEEPTUTOR_FLUTTER_HOME%"
if defined DEEPTUTOR_ANDROID_HOME set "ANDROID_HOME=%DEEPTUTOR_ANDROID_HOME%"
if defined DEEPTUTOR_ANDROID_AVD_HOME set "ANDROID_AVD_HOME=%DEEPTUTOR_ANDROID_AVD_HOME%"
if defined DEEPTUTOR_PUB_CACHE set "PUB_CACHE=%DEEPTUTOR_PUB_CACHE%"
if defined DEEPTUTOR_GRADLE_USER_HOME set "GRADLE_USER_HOME=%DEEPTUTOR_GRADLE_USER_HOME%"
if defined DEEPTUTOR_JAVA_HOME set "JAVA_HOME=%DEEPTUTOR_JAVA_HOME%"
set "ANDROID_SDK_ROOT=%ANDROID_HOME%"

set "FLUTTER=%FLUTTER_HOME%\bin\flutter.bat"
set "ADB=%ANDROID_HOME%\platform-tools\adb.exe"
set "PROJECT_DIR=%~dp0.."
set "PATH=%FLUTTER_HOME%\bin;%ANDROID_HOME%\platform-tools;%JAVA_HOME%\bin;D:\Develop\Git\Git\cmd;C:\Windows\System32;C:\Windows;C:\Windows\System32\Wbem;C:\Windows\System32\WindowsPowerShell\v1.0;%PATH%"

if not exist "%FLUTTER%" (
  echo [DeepTutor] Flutter not found: %FLUTTER%
  exit /b 3
)
if not exist "%ANDROID_HOME%" (
  echo [DeepTutor] Android SDK not found: %ANDROID_HOME%
  exit /b 3
)
if not exist "%JAVA_HOME%\bin\java.exe" (
  echo [DeepTutor] JDK not found: %JAVA_HOME%
  exit /b 3
)
if not exist "D:\Develop\Git\Git\cmd\git.exe" (
  echo [DeepTutor] Git not found: D:\Develop\Git\Git\cmd\git.exe
  exit /b 3
)

if /i "%MODE%"=="release" call :check_release || exit /b %ERRORLEVEL%
if /i "%MODE%"=="both" call :check_release || exit /b %ERRORLEVEL%

pushd "%PROJECT_DIR%" || exit /b 4

echo [DeepTutor] Starting Windows-native %MODE% build...
echo [DeepTutor] Project: %CD%
echo [DeepTutor] Flutter: %FLUTTER%
echo [DeepTutor] Android SDK: %ANDROID_HOME%
echo [DeepTutor] Pub cache: %PUB_CACHE%
echo [DeepTutor] Gradle cache: %GRADLE_USER_HOME%

if "%CLEAN%"=="1" (
  echo [DeepTutor] Running flutter clean...
  call "%FLUTTER%" clean
  if errorlevel 1 goto :failed
)

echo [DeepTutor] Running flutter pub get...
call "%FLUTTER%" pub get
if errorlevel 1 goto :failed

if /i "%MODE%"=="debug" (
  call :build_apk debug || goto :failed
  set "FINAL_APK=build\app\outputs\flutter-apk\app-debug.apk"
)
if /i "%MODE%"=="release" (
  call :build_apk release || goto :failed
  set "FINAL_APK=build\app\outputs\flutter-apk\app-release.apk"
)
if /i "%MODE%"=="both" (
  call :build_apk debug || goto :failed
  call :build_apk release || goto :failed
  set "FINAL_APK=build\app\outputs\flutter-apk\app-release.apk"
)

if "%INSTALL%"=="1" (
  if not exist "%ADB%" (
    echo [DeepTutor] INSTALL=1 but adb was not found: %ADB%
    goto :failed
  )
  echo [DeepTutor] Installing %FINAL_APK% on the connected Windows Android device...
  "%ADB%" install -r "%FINAL_APK%"
  if errorlevel 1 (
    echo [DeepTutor] Install failed. Debug and release signatures cannot overwrite each other.
    goto :failed
  )
)

echo [DeepTutor] APK output: mobile\build\app\outputs\flutter-apk\
popd
exit /b 0

:check_release
if not defined SERVER_URL if not "%ALLOW_SERVER_ENTRY%"=="1" (
  echo [DeepTutor] Release requires SERVER_URL or ALLOW_SERVER_ENTRY=1.
  exit /b 5
)
if exist "%PROJECT_DIR%\android\key.properties" exit /b 0
if defined DEEPTUTOR_ANDROID_STORE_FILE exit /b 0
echo [DeepTutor] Release signing is not configured. Add android\key.properties or DEEPTUTOR_ANDROID_* variables.
exit /b 6

:build_apk
set "FLAVOR=%~1"
set "SERVER_ARG="
set "ENTRY_ARG="
set "TREE_ARG="
if defined SERVER_URL set "SERVER_ARG=--dart-define=DEEPTUTOR_FIXED_SERVER_URL=%SERVER_URL%"
if "%ALLOW_SERVER_ENTRY%"=="1" set "ENTRY_ARG=--dart-define=DEEPTUTOR_ALLOW_SERVER_ENTRY=true"
if "%NO_TREE_SHAKE%"=="1" set "TREE_ARG=--no-tree-shake-icons"
echo [DeepTutor] Building %FLAVOR% APK with Windows Flutter...
call "%FLUTTER%" build apk --%FLAVOR% %SERVER_ARG% %ENTRY_ARG% %TREE_ARG%
if errorlevel 1 exit /b %ERRORLEVEL%
if not exist "build\app\outputs\flutter-apk\app-%FLAVOR%.apk" (
  echo [DeepTutor] APK missing after build: app-%FLAVOR%.apk
  exit /b 7
)
for %%I in ("build\app\outputs\flutter-apk\app-%FLAVOR%.apk") do echo [DeepTutor] %FLAVOR% complete: %%~fI ^(%%~zI bytes^)
exit /b 0

:failed
set "EXIT_CODE=%ERRORLEVEL%"
if "%EXIT_CODE%"=="0" set "EXIT_CODE=1"
echo [DeepTutor] Build failed with exit code %EXIT_CODE%.
popd
exit /b %EXIT_CODE%
