del %cd%\build\* /f /s /q

rd %cd%\build /s /q

del %cd%\hive\luaclib\* /f /s /q

del %cd%\hive\core* /f /q

del %cd%\hive\lua /f /q

del %cd%\hive\lua.exe /f /q

del %cd%\hive\lua.ilk /f /q

del %cd%\hive\lua.pdb /f /q

del %cd%\hive\luac /f /q

del %cd%\hive\luac.exe /f /q

del %cd%\hive\luac.ilk /f /q

del %cd%\hive\luac.pdb /f /q

mkdir %cd%\build

cmake --no-warn-unused-cli -DCMAKE_EXPORT_COMPILE_COMMANDS:BOOL=TRUE -H%cd% -B%cd%\build -G "Visual Studio 16 2019" -T host=x64 -A x64

cmake --build %cd%\build --config Release --target ALL_BUILD --clean-first -- /maxcpucount:14

pause