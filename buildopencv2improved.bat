@echo off
setlocal enableDelayedExpansion

:: =================================================================================
:: ==                        ANSI COLOR DEFINITIONS                             ==
:: =================================================================================
:: Robust ESC detection, works in VS Developer Command Prompt, etc.
for /f %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"

set "COLOR_RED=!ESC![91m"
set "COLOR_WHITE=!ESC![97m"
set "COLOR_BLUE=!ESC![94m"
set "COLOR_GRAY=!ESC![90m"
set "COLOR_RESET=!ESC![0m"

:: =================================================================================
:: ==                           ARGUMENT PARSING                                ==
:: =================================================================================
:: Usage examples:
::   build_opencv.bat
::   build_opencv.bat D:\opencv_build
::   build_opencv.bat /FULL
::   build_opencv.bat D:\opencv_build /REUSE
::   build_opencv.bat /FULL /NOLOG
::   build_opencv.bat D:\opencv_build /FULL /NOLOG
::   build_opencv.bat /HELP
::   build_opencv.bat /?

set "ROOT_DIR="
set "MODE="
set "NOLOG=0"

:parse_args
if "%~1"=="" goto after_args

if /I "%~1"=="/HELP" (
    goto print_help
)

if "%~1"=="/?" (
    goto print_help
)

if /I "%~1"=="/FULL" (
    set "MODE=FULL"
    shift
    goto parse_args
)

if /I "%~1"=="/REUSE" (
    set "MODE=REUSE"
    shift
    goto parse_args
)

if /I "%~1"=="/NOLOG" (
    set "NOLOG=1"
    shift
    goto parse_args
)

:: First non-switch argument is ROOT_DIR
if not defined ROOT_DIR (
    set "ROOT_DIR=%~f1"
    shift
    goto parse_args
)

:: Extra arguments are ignored
shift
goto parse_args

:after_args
if not defined ROOT_DIR (
    set "ROOT_DIR=C:\opencv_build"
)
goto start_script

:: =================================================================================
:: ==                             HELP / USAGE                                   ==
:: =================================================================================
:print_help
echo.
echo !COLOR_BLUE!OpenCV + CUDA + cuDNN Build and Deploy Script!COLOR_RESET!
echo.
echo !COLOR_WHITE!Usage:!COLOR_RESET!
echo   build_opencv.bat [ROOT_DIR] [options]
echo.
echo !COLOR_WHITE!Arguments:!COLOR_RESET!
echo   ROOT_DIR       Optional. Root directory for sources/build/install.
echo                 Default: C:\opencv_build
echo.
echo !COLOR_WHITE!Options:!COLOR_RESET!
echo   /FULL         Force full rebuild (delete build dir), no interactive prompt.
echo   /REUSE        Re-run build with new configuration (delete CMake cache only).
echo   /NOLOG        Disable build logging (no build.log file).
echo   /HELP or /?   Show this help message and exit.
echo.
echo !COLOR_WHITE!Examples:!COLOR_RESET!
echo   build_opencv.bat
echo   build_opencv.bat D:\opencv_build
echo   build_opencv.bat /FULL
echo   build_opencv.bat D:\opencv_build /REUSE /NOLOG
echo.
echo !COLOR_GRAY!Note: Run from an elevated "Developer Command Prompt for VS".!COLOR_RESET!
goto end

:: =================================================================================
:: ==                  CONFIGURATION - PLEASE VERIFY THESE VALUES                 ==
:: =================================================================================
:start_script
:: You can override these defaults by setting environment variables before running:
::   set VS_VERSION=Visual Studio 17 2022
::   set CUDA_ARCH=8.9
::   set J_FLAG=16

if not defined VS_VERSION set "VS_VERSION=Visual Studio 17 2022"
if not defined CUDA_ARCH set "CUDA_ARCH=8.9"
if not defined J_FLAG set "J_FLAG=%NUMBER_OF_PROCESSORS%"

:: =================================================================================
:: ==            SCRIPT LOGIC - DO NOT EDIT BELOW THIS LINE                     ==
:: =================================================================================

cls
echo !COLOR_BLUE!##########################################################################!COLOR_RESET!
echo !COLOR_BLUE!#   !COLOR_RED!IMPORTANT:!COLOR_WHITE! This script must be run from an                           !COLOR_BLUE!#
echo !COLOR_BLUE!#   !COLOR_WHITE!"Elevated Developer Command Prompt for VS".                          !COLOR_BLUE!#
echo !COLOR_BLUE!##########################################################################!COLOR_RESET!
echo.
echo !COLOR_GRAY!Build Root Directory is set to: !COLOR_WHITE!"%ROOT_DIR%"!COLOR_RESET!
if /I "%MODE%"=="FULL"  echo !COLOR_GRAY!Mode: !COLOR_WHITE!FULL REBUILD (no prompt)!COLOR_RESET!
if /I "%MODE%"=="REUSE" echo !COLOR_GRAY!Mode: !COLOR_WHITE!RE-RUN with new configuration (no prompt)!COLOR_RESET!
if "%NOLOG%"=="1" (
    echo !COLOR_GRAY!Logging: !COLOR_WHITE!DISABLED (/NOLOG)!COLOR_RESET!
) else (
    echo !COLOR_GRAY!Logging: !COLOR_WHITE!ENABLED (build.log in build directory)!COLOR_RESET!
)
echo.

:: Detect existing configuration
dir /b "%ROOT_DIR%\build\OpenCV.sln" >nul 2>nul
if not errorlevel 1 (
    if /I "%MODE%"=="FULL"  goto full_rebuild_setup
    if /I "%MODE%"=="REUSE" goto reinstall_setup

    echo !COLOR_WHITE!A previously configured build was found.!COLOR_RESET!
    rem choice F=1, R=2; check higher errorlevel first
    choice /C FR /M "!COLOR_WHITE!Choose (F)ull Rebuild or (R)e-run build with new configuration?!COLOR_RESET!"
    if errorlevel 2 goto reinstall_setup
    if errorlevel 1 goto full_rebuild_setup
)

if /I not "%MODE%"=="FULL" if /I not "%MODE%"=="REUSE" (
    echo !COLOR_GRAY!No previous build detected. Starting clean process.!COLOR_RESET!
)
goto prerequisite_check

:full_rebuild_setup
echo. & echo !COLOR_BLUE![MODE]!COLOR_WHITE! Full Rebuild selected. Deleting previous build directory...!COLOR_RESET!
dir /b "%ROOT_DIR%\build" >nul 2>nul && (rd /s /q "%ROOT_DIR%\build")
goto prerequisite_check

:reinstall_setup
echo. & echo !COLOR_BLUE![MODE]!COLOR_WHITE! Re-run selected. Deleting CMake cache to allow path rediscovery...!COLOR_RESET!
dir /b "%ROOT_DIR%\build\CMakeCache.txt" >nul 2>nul && (del "%ROOT_DIR%\build\CMakeCache.txt" /q >nul 2>nul)
goto prerequisite_check

::-------------------------------------------------------------------------------
:: PHASE 1: PREREQUISITE CHECKS
::-------------------------------------------------------------------------------
:prerequisite_check
echo. & echo !COLOR_BLUE!===== PHASE 1: VALIDATING PREREQUISITES =====!COLOR_RESET! & echo.
set "final_error_found=0"

:: Administrator privileges
fsutil dirty query %systemdrive% >nul 2>&1
if not errorlevel 1 (
    echo !COLOR_WHITE![OK]!COLOR_GRAY! Administrator privileges detected.!COLOR_RESET!
) else (
    echo !COLOR_RED![FAIL] Administrator privileges are required.!COLOR_RESET!
    set "final_error_found=1"
)

:: Visual Studio C++ compiler (cl.exe)
where cl.exe >nul 2>nul
if not errorlevel 1 (
    echo !COLOR_WHITE![OK]!COLOR_GRAY! Visual Studio C++ Compiler found.!COLOR_RESET!
) else (
    echo !COLOR_RED![FAIL] VS C++ Compiler not found. Run from a Developer Command Prompt.!COLOR_RESET!
    set "final_error_found=1"
)

:: CMake
where cmake.exe >nul 2>nul
if not errorlevel 1 (
    echo !COLOR_WHITE![OK]!COLOR_GRAY! CMake found.!COLOR_RESET!
) else (
    echo !COLOR_RED![FAIL] CMake not found. Ensure it is in your PATH.!COLOR_RESET!
    set "final_error_found=1"
)

:: CUDA Toolkit (nvcc)
where nvcc.exe >nul 2>nul
if not errorlevel 1 (
    echo !COLOR_WHITE![OK]!COLOR_GRAY! NVIDIA CUDA Toolkit found.!COLOR_RESET!
) else (
    echo !COLOR_RED![FAIL] NVIDIA CUDA Toolkit ^(nvcc^) not found. Ensure it is installed and in your PATH.!COLOR_RESET!
    set "final_error_found=1"
)

:: CUDA_PATH and cuDNN
if not defined CUDA_PATH (
    echo !COLOR_RED![FAIL] CUDA_PATH environment variable is not set.!COLOR_RESET!
    set "final_error_found=1"
) else (
    dir /b "%CUDA_PATH%\include\cudnn.h" >nul 2>nul
    if not errorlevel 1 (
        echo !COLOR_WHITE![OK]!COLOR_GRAY! cuDNN found under CUDA_PATH.!COLOR_RESET!
    ) else (
        echo !COLOR_RED![FAIL] cuDNN not found in "%CUDA_PATH%\include". Ensure cudnn.h is present.!COLOR_RESET!
        set "final_error_found=1"
    )
)

:: Python
where python.exe >nul 2>nul
if not errorlevel 1 (
    echo !COLOR_WHITE![OK]!COLOR_GRAY! Python found.!COLOR_RESET!
) else (
    echo !COLOR_RED![FAIL] Python not found. Ensure it is in your PATH.!COLOR_RESET!
    set "final_error_found=1"
)

:: NumPy for this specific Python
python -m pip show numpy >nul 2>nul
if not errorlevel 1 (
    echo !COLOR_WHITE![OK]!COLOR_GRAY! NumPy package found for this Python interpreter.!COLOR_RESET!
) else (
    echo !COLOR_RED![FAIL] NumPy not found for this Python. Run 'python -m pip install numpy'.!COLOR_RESET!
    set "final_error_found=1"
)

:: Git
where git.exe >nul 2>nul
if not errorlevel 1 (
    echo !COLOR_WHITE![OK]!COLOR_GRAY! Git found.!COLOR_RESET!
) else (
    echo !COLOR_RED![FAIL] Git not found. Ensure it is installed and in your PATH.!COLOR_RESET!
    set "final_error_found=1"
)

if !final_error_found! equ 1 (
    echo. & echo !COLOR_RED!One or more prerequisites are missing. Aborting.!COLOR_RESET!
    goto :error_exit
)
echo. & echo !COLOR_BLUE!All prerequisites validated successfully.!COLOR_RESET!

::-------------------------------------------------------------------------------
:: PHASE 2: SETUP SOURCE AND BUILD DIRECTORIES
::-------------------------------------------------------------------------------
:setup_source_and_build_dir
echo. & echo !COLOR_BLUE!===== PHASE 2: SETUP SOURCE AND BUILD DIRECTORIES =====!COLOR_RESET! & echo.

:: Remember original directory (currently unused, but harmless)
set "ORIG_DIR=%CD%"

:: Ensure root directory exists, then enter it
if not exist "%ROOT_DIR%\" (
    echo !COLOR_GRAY!Creating root directory: "%ROOT_DIR%"!COLOR_RESET!
    mkdir "%ROOT_DIR%" >nul 2>&1
    if errorlevel 1 (
        echo !COLOR_RED![FATAL ERROR] Failed to create root directory "!ROOT_DIR!".!COLOR_RESET!
        goto :return_and_error
    )
)

pushd "%ROOT_DIR%" >nul

:: Ensure build dir exists before logging
if not exist "%ROOT_DIR%\build\" (
    mkdir "%ROOT_DIR%\build"
    if errorlevel 1 (
        echo !COLOR_RED![FATAL ERROR] Failed to create build directory.!COLOR_RESET!
        goto :return_and_error
    )
)

:: Setup logging
set "LOG_FILE=%ROOT_DIR%\build\build.log"
if "%NOLOG%"=="1" (
    set "DO_LOG=0"
) else (
    set "DO_LOG=1"
    echo ===============================================================================>> "%LOG_FILE%"
    echo OpenCV build started at %date% %time% >> "%LOG_FILE%"
    echo ROOT_DIR=%ROOT_DIR% >> "%LOG_FILE%"
    echo VS_VERSION=%VS_VERSION%, CUDA_ARCH=%CUDA_ARCH%, J_FLAG=%J_FLAG%, MODE=%MODE% >> "%LOG_FILE%"
    echo ===============================================================================>> "%LOG_FILE%"
)

:: Clone OpenCV if needed
dir /b "%ROOT_DIR%\opencv\CMakeLists.txt" >nul 2>nul || (
    echo !COLOR_GRAY!Cloning OpenCV...!COLOR_RESET!
    if "%DO_LOG%"=="1" (
        git clone --depth 1 https://github.com/opencv/opencv.git "%ROOT_DIR%\opencv" >> "%LOG_FILE%" 2>&1
    ) else (
        git clone --depth 1 https://github.com/opencv/opencv.git "%ROOT_DIR%\opencv"
    )
    if errorlevel 1 (
        echo !COLOR_RED![FATAL ERROR] Failed to clone OpenCV repository.!COLOR_RESET!
        goto :return_and_error
    )
)

:: Clone OpenCV Contrib if needed
dir /b "%ROOT_DIR%\opencv_contrib\modules" >nul 2>nul || (
    echo !COLOR_GRAY!Cloning OpenCV Contrib...!COLOR_RESET!
    if "%DO_LOG%"=="1" (
        git clone --depth 1 https://github.com/opencv/opencv_contrib.git "%ROOT_DIR%\opencv_contrib" >> "%LOG_FILE%" 2>&1
    ) else (
        git clone --depth 1 https://github.com/opencv/opencv_contrib.git "%ROOT_DIR%\opencv_contrib"
    )
    if errorlevel 1 (
        echo !COLOR_RED![FATAL ERROR] Failed to clone OpenCV Contrib repository.!COLOR_RESET!
        goto :return_and_error
    )
)

pushd "%ROOT_DIR%\build" >nul

::-------------------------------------------------------------------------------
:: PHASE 3: CONFIGURE AND BUILD (CMAKE)
::-------------------------------------------------------------------------------
:configure_and_build
echo. & echo !COLOR_BLUE!===== PHASE 3: CONFIGURE AND BUILD (CMAKE) =====!COLOR_RESET! & echo.
echo !COLOR_GRAY!--- Running CMAKE configuration ---!COLOR_RESET!

if "%DO_LOG%"=="1" (
    cmake -G "%VS_VERSION%" -A x64 -S "%ROOT_DIR%\opencv" -B "%ROOT_DIR%\build" ^
        -D CMAKE_INSTALL_PREFIX="%ROOT_DIR%\install" ^
        -D OPENCV_EXTRA_MODULES_PATH="%ROOT_DIR%\opencv_contrib\modules" ^
        -D OPENCV_DISABLE_VCPKG_INTEGRATION=ON ^
        -D BUILD_PROTOBUF=ON -D BUILD_PNG=ON -D BUILD_JPEG=ON -D BUILD_TIFF=ON -D BUILD_WEBP=ON -D BUILD_OPENEXR=ON ^
        -D BUILD_opencv_world=ON -D BUILD_opencv_python3=ON -D OPENCV_ENABLE_NONFREE=ON ^
        -D WITH_CUDA=ON -D WITH_CUDNN=ON -D OPENCV_DNN_CUDA=ON ^
        -D ENABLE_FAST_MATH=1 -D CUDA_FAST_MATH=1 -D WITH_CUBLAS=1 -D CUDA_ARCH_BIN=%CUDA_ARCH% ^
        -D CUDA_NVCC_FLAGS="--use-local-env" ^
        -D WITH_MSMF=ON -D BUILD_EXAMPLES=OFF -D BUILD_TESTS=OFF -D BUILD_PERF_TESTS=OFF ^
        -D CMAKE_CONFIGURATION_TYPES="Release" >> "%LOG_FILE%" 2>&1
) else (
    cmake -G "%VS_VERSION%" -A x64 -S "%ROOT_DIR%\opencv" -B "%ROOT_DIR%\build" ^
        -D CMAKE_INSTALL_PREFIX="%ROOT_DIR%\install" ^
        -D OPENCV_EXTRA_MODULES_PATH="%ROOT_DIR%\opencv_contrib\modules" ^
        -D OPENCV_DISABLE_VCPKG_INTEGRATION=ON ^
        -D BUILD_PROTOBUF=ON -D BUILD_PNG=ON -D BUILD_JPEG=ON -D BUILD_TIFF=ON -D BUILD_WEBP=ON -D BUILD_OPENEXR=ON ^
        -D BUILD_opencv_world=ON -D BUILD_opencv_python3=ON -D OPENCV_ENABLE_NONFREE=ON ^
        -D WITH_CUDA=ON -D WITH_CUDNN=ON -D OPENCV_DNN_CUDA=ON ^
        -D ENABLE_FAST_MATH=1 -D CUDA_FAST_MATH=1 -D WITH_CUBLAS=1 -D CUDA_ARCH_BIN=%CUDA_ARCH% ^
        -D CUDA_NVCC_FLAGS="--use-local-env" ^
        -D WITH_MSMF=ON -D BUILD_EXAMPLES=OFF -D BUILD_TESTS=OFF -D BUILD_PERF_TESTS=OFF ^
        -D CMAKE_CONFIGURATION_TYPES="Release"
)

if errorlevel 1 (
    echo !COLOR_RED![FATAL ERROR] CMAKE configuration FAILED.!COLOR_RESET!
    if "%DO_LOG%"=="1" echo [ERROR] CMake configure failed. See log: "%LOG_FILE%"
    goto :return_and_error
)

echo. & echo !COLOR_BLUE!CMAKE CONFIGURED SUCCESSFULLY.!COLOR_RESET! & echo.

echo !COLOR_GRAY!--- Compiling ALL_BUILD (This is the longest step) ---!COLOR_RESET!
if "%DO_LOG%"=="1" (
    cmake --build "%ROOT_DIR%\build" --target ALL_BUILD --config Release -- /m:%J_FLAG% >> "%LOG_FILE%" 2>&1
) else (
    cmake --build "%ROOT_DIR%\build" --target ALL_BUILD --config Release -- /m:%J_FLAG%
)
if errorlevel 1 (
    echo !COLOR_RED![FATAL ERROR] BUILD FAILED.!COLOR_RESET!
    if "%DO_LOG%"=="1" echo [ERROR] Build failed. See log: "%LOG_FILE%"
    goto :return_and_error
)
echo !COLOR_BLUE!BUILD SUCCEEDED.!COLOR_RESET!

:: Check for FFMPEG DLL
dir /b "%ROOT_DIR%\build\bin\Release\opencv_videoio_ffmpeg*.dll" >nul 2>nul
if errorlevel 1 (
    echo.
    echo !COLOR_RED![WARNING] FFMPEG DLL not found in build output.!COLOR_RESET!
    echo !COLOR_GRAY!Video I/O ^(e.g., reading MP4 files^) may be limited.!COLOR_RESET!
    echo !COLOR_GRAY!This can happen if the download during CMake configuration failed.!COLOR_RESET!
    echo.
)

::-------------------------------------------------------------------------------
:: PHASE 4: DEPLOYING FILES TO PYTHON
::-------------------------------------------------------------------------------
:deploy_files
echo. & echo !COLOR_BLUE!======================================================!COLOR_RESET!
echo !COLOR_BLUE!=== PHASE 4: DEPLOYING FILES TO PYTHON               ===!COLOR_RESET!
echo !COLOR_BLUE!======================================================!COLOR_RESET! & echo.

echo !COLOR_GRAY!--- Running CMake INSTALL target... ---!COLOR_RESET!
if "%DO_LOG%"=="1" (
    cmake --build "%ROOT_DIR%\build" --target INSTALL --config Release >> "%LOG_FILE%" 2>&1
) else (
    cmake --build "%ROOT_DIR%\build" --target INSTALL --config Release
)
if errorlevel 1 (
    echo !COLOR_RED![FATAL ERROR] INSTALL FAILED.!COLOR_RESET!
    if "%DO_LOG%"=="1" echo [ERROR] Install failed. See log: "%LOG_FILE%"
    goto :return_and_error
)
echo !COLOR_GRAY!INSTALL command completed.!COLOR_RESET! & echo.

echo !COLOR_GRAY!--- Locating Python's cv2 package directory... ---!COLOR_RESET!
set "PYTHON_CV2_DIR="

:: First, try to locate cv2 via Python itself
for /f "delims=" %%P in ('python -c "import cv2, os; print(os.path.dirname(cv2.__file__))" 2^>nul') do (
    set "PYTHON_CV2_DIR=%%P"
)

:: If that failed, fall back to purelib\cv2
if not defined PYTHON_CV2_DIR (
    set "PYTHON_SITEPACKAGES_PATH="
    for /f "delims=" %%P in ('python -c "import sysconfig; print(sysconfig.get_path(''purelib''))"') do (
        set "PYTHON_SITEPACKAGES_PATH=%%P"
    )
    if not defined PYTHON_SITEPACKAGES_PATH (
        echo !COLOR_RED![FATAL ERROR] Could not determine Python site-packages path.!COLOR_RESET!
        goto :return_and_error
    )
    set "PYTHON_CV_DIR_GUESS=!PYTHON_SITEPACKAGES_PATH!\cv2"
    set "PYTHON_CV2_DIR=!PYTHON_CV_DIR_GUESS!"
)

echo !COLOR_GRAY!Destination cv2 directory: !COLOR_WHITE!!PYTHON_CV2_DIR!!COLOR_RESET! & echo.

:: Ensure cv2 directory exists
if not exist "!PYTHON_CV2_DIR!\" (
    echo !COLOR_GRAY!Creating target cv2 directory: "!PYTHON_CV2_DIR!"!COLOR_RESET!
    mkdir "!PYTHON_CV2_DIR!" >nul 2>&1
    if errorlevel 1 (
        echo !COLOR_RED![FATAL ERROR] Failed to create cv2 directory.!COLOR_RESET!
        goto :return_and_error
    )
)

echo !COLOR_GRAY!--- Deploying runtime DLLs... ---!COLOR_RESET!
set "BUILD_BIN_DIR=%ROOT_DIR%\build\bin\Release"
set "TARGET_CV2_DIR=!PYTHON_CV2_DIR!"

copy "!BUILD_BIN_DIR!\opencv_world*.dll" "!TARGET_CV2_DIR!\" >nul
if errorlevel 1 (
    echo !COLOR_RED![FATAL ERROR] Failed to copy opencv_world*.dll.!COLOR_RESET!
    goto :return_and_error
)

copy "!BUILD_BIN_DIR!\opencv_videoio_ffmpeg*.dll" "!TARGET_CV2_DIR!\" >nul 2>nul

copy "!CUDA_PATH!\bin\cudart64_*.dll" "!TARGET_CV2_DIR!\" >nul
if errorlevel 1 (
    echo !COLOR_RED![FATAL ERROR] Failed to copy cudart DLL.!COLOR_RESET!
    goto :return_and_error
)

copy "!CUDA_PATH!\bin\cublas64_*.dll" "!TARGET_CV2_DIR!\" >nul
if errorlevel 1 (
    echo !COLOR_RED![FATAL ERROR] Failed to copy cublas DLL.!COLOR_RESET!
    goto :return_and_error
)

copy "!CUDA_PATH!\bin\cublasLt64_*.dll" "!TARGET_CV2_DIR!\" >nul
if errorlevel 1 (
    echo !COLOR_RED![FATAL ERROR] Failed to copy cublasLt DLL.!COLOR_RESET!
    goto :return_and_error
)

copy "!CUDA_PATH!\bin\cufft64_*.dll" "!TARGET_CV2_DIR!\" >nul
if errorlevel 1 (
    echo !COLOR_RED![FATAL ERROR] Failed to copy cufft DLL.!COLOR_RESET!
    goto :return_and_error
)

copy "!CUDA_PATH!\bin\cudnn*.dll" "!TARGET_CV2_DIR!\" >nul
if errorlevel 1 (
    echo !COLOR_RED![FATAL ERROR] Failed to copy cuDNN DLLs.!COLOR_RESET!
    goto :return_and_error
)

echo !COLOR_BLUE!All necessary DLLs copied successfully.!COLOR_RESET! & echo.
if "%DO_LOG%"=="1" echo Deployment complete. See detailed log at: "%LOG_FILE%"
goto :return_and_success

::-------------------------------------------------------------------------------
:: CENTRALIZED RETURN / CLEANUP
::-------------------------------------------------------------------------------

:return_and_error
:: Pop any directories we pushed (safe even if stack is shallow)
popd >nul 2>&1
popd >nul 2>&1
goto :error_exit

:return_and_success
:: Pop any directories we pushed
popd >nul 2>&1
popd >nul 2>&1
goto :finish

:error_exit
echo. & echo !COLOR_RED!!!!!!!!!!!!!!! SCRIPT HALTED DUE TO A FATAL ERROR !!!!!!!!!!!!!!! !COLOR_RESET!
goto :end

:finish
echo. & echo !COLOR_BLUE!===================================================================!COLOR_RESET!
echo !COLOR_BLUE!=                 !COLOR_WHITE!PROCESS COMPLETE.                               !COLOR_BLUE!=!COLOR_RESET!
echo !COLOR_BLUE!=   !COLOR_GRAY!You can now 'import cv2' in your Python environment.          !COLOR_BLUE!=!COLOR_RESET!
echo !COLOR_BLUE!===================================================================!COLOR_RESET!

:end
endlocal
pause