@echo off
setlocal
cd /d "%~dp0"

echo [1/4] 初始化 MSVC 编译环境...
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1

echo [2/4] CMake 配置 (Release)...
if not exist build-release mkdir build-release
cd build-release
"C:\Program Files\CMake\bin\cmake.exe" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=E:/Development_environment/qt/6.7.3/msvc2022_64 ..
if %errorlevel% neq 0 (
    echo CMake 配置失败！
    pause
    exit /b 1
)

echo [3/4] 编译 Release...
"C:\Program Files\CMake\bin\cmake.exe" --build . --config Release
if %errorlevel% neq 0 (
    echo 编译失败！
    pause
    exit /b 1
)

echo [4/4] 部署 Qt 运行时 DLL...
E:\Development_environment\qt\6.7.3\msvc2022_64\bin\windeployqt6.exe --qmldir ..\qml im-agent-hub-pc.exe
if %errorlevel% neq 0 (
    echo windeployqt 部署失败！
    pause
    exit /b 1
)

echo.
echo ========================================
echo   Release 构建完成！
echo   输出目录: %cd%
echo   可执行文件: %cd%\im-agent-hub-pc.exe
echo ========================================
echo.
pause
 