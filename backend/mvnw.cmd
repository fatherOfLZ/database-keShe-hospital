@echo off
setlocal
set "WRAPPER_DIR=%~dp0.mvn\wrapper"
set "WRAPPER_JAR=%WRAPPER_DIR%\maven-wrapper.jar"
set "WRAPPER_URL=https://repo.maven.apache.org/maven2/org/apache/maven/wrapper/maven-wrapper/3.3.2/maven-wrapper-3.3.2.jar"
if not exist "%WRAPPER_JAR%" (
  if not exist "%WRAPPER_DIR%" mkdir "%WRAPPER_DIR%"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing '%WRAPPER_URL%' -OutFile '%WRAPPER_JAR%'"
)
java "-Dmaven.multiModuleProjectDirectory=%CD%" -classpath "%WRAPPER_JAR%" org.apache.maven.wrapper.MavenWrapperMain %*
if errorlevel 1 exit /b %errorlevel%
endlocal
