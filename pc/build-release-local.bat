@echo off
setlocal
cd /d "%~dp0"

echo [1/3] CMake 配置 (Release, MinGW)...
if not exist build-release mkdir build-release
cd build-release
cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=D:/Qt/6.7.3/mingw_64 -DCMAKE_C_COMPILER=D:/Qt/Tools/mingw1120_64/bin/gcc.exe -DCMAKE_CXX_COMPILER=D:/Qt/Tools/mingw1120_64/bin/g++.exe ..
if %errorlevel% neq 0 (
    echo CMake 配置失败！
    pause
    exit /b 1
)

echo [2/3] 编译 Release...
cmake --build . --config Release
if %errorlevel% neq 0 (
    echo 编译失败！
    pause
    exit /b 1
)

echo [3/3] 部署 Qt 运行时 DLL...
D:\Qt\6.7.3\mingw_64\bin\windeployqt6.exe --qmldir ..\qml im-agent-hub-pc.exe
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
