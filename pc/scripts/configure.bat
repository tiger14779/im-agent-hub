@echo off
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
if not exist build mkdir build
cd build
"C:\Program Files\CMake\bin\cmake.exe" -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_PREFIX_PATH=E:/Development_environment/qt/6.7.3/msvc2022_64 ..
