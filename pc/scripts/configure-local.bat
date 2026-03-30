@echo off
if not exist build mkdir build
cd build
cmake -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_PREFIX_PATH=D:/Qt/6.7.3/mingw_64 -DCMAKE_C_COMPILER=D:/Qt/Tools/mingw1120_64/bin/gcc.exe -DCMAKE_CXX_COMPILER=D:/Qt/Tools/mingw1120_64/bin/g++.exe ..
