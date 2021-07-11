del %cd%\build\* /f /s /q

rd %cd%\build /s /q

del %cd%\luaclib\* /f /s /q

del %cd%\core* /f /q

del %cd%\lua /f /q

del %cd%\lua.* /f /q

del %cd%\luac /f /q

del %cd%\luac.* /f /q

del %cd%\proto* /f /q

mkdir %cd%\build

cmake --no-warn-unused-cli -DCMAKE_EXPORT_COMPILE_COMMANDS:BOOL=TRUE -H%cd% -B%cd%\build -G "Visual Studio 16 2019" -T host=x64 -A x64

cmake --build %cd%\build --config Release --target ALL_BUILD --clean-first -- /maxcpucount:14

pause