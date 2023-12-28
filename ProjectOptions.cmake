include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(Wop_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(Wop_setup_options)
  option(Wop_ENABLE_HARDENING "Enable hardening" ON)
  option(Wop_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    Wop_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    Wop_ENABLE_HARDENING
    OFF)

  Wop_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR Wop_PACKAGING_MAINTAINER_MODE)
    option(Wop_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(Wop_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(Wop_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(Wop_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(Wop_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(Wop_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(Wop_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(Wop_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(Wop_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(Wop_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(Wop_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(Wop_ENABLE_PCH "Enable precompiled headers" OFF)
    option(Wop_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(Wop_ENABLE_IPO "Enable IPO/LTO" ON)
    option(Wop_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(Wop_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(Wop_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(Wop_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(Wop_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(Wop_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(Wop_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(Wop_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(Wop_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(Wop_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(Wop_ENABLE_PCH "Enable precompiled headers" OFF)
    option(Wop_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      Wop_ENABLE_IPO
      Wop_WARNINGS_AS_ERRORS
      Wop_ENABLE_USER_LINKER
      Wop_ENABLE_SANITIZER_ADDRESS
      Wop_ENABLE_SANITIZER_LEAK
      Wop_ENABLE_SANITIZER_UNDEFINED
      Wop_ENABLE_SANITIZER_THREAD
      Wop_ENABLE_SANITIZER_MEMORY
      Wop_ENABLE_UNITY_BUILD
      Wop_ENABLE_CLANG_TIDY
      Wop_ENABLE_CPPCHECK
      Wop_ENABLE_COVERAGE
      Wop_ENABLE_PCH
      Wop_ENABLE_CACHE)
  endif()

  Wop_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (Wop_ENABLE_SANITIZER_ADDRESS OR Wop_ENABLE_SANITIZER_THREAD OR Wop_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(Wop_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(Wop_global_options)
  if(Wop_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    Wop_enable_ipo()
  endif()

  Wop_supports_sanitizers()

  if(Wop_ENABLE_HARDENING AND Wop_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR Wop_ENABLE_SANITIZER_UNDEFINED
       OR Wop_ENABLE_SANITIZER_ADDRESS
       OR Wop_ENABLE_SANITIZER_THREAD
       OR Wop_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${Wop_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${Wop_ENABLE_SANITIZER_UNDEFINED}")
    Wop_enable_hardening(Wop_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(Wop_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(Wop_warnings INTERFACE)
  add_library(Wop_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  Wop_set_project_warnings(
    Wop_warnings
    ${Wop_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(Wop_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    configure_linker(Wop_options)
  endif()

  include(cmake/Sanitizers.cmake)
  Wop_enable_sanitizers(
    Wop_options
    ${Wop_ENABLE_SANITIZER_ADDRESS}
    ${Wop_ENABLE_SANITIZER_LEAK}
    ${Wop_ENABLE_SANITIZER_UNDEFINED}
    ${Wop_ENABLE_SANITIZER_THREAD}
    ${Wop_ENABLE_SANITIZER_MEMORY})

  set_target_properties(Wop_options PROPERTIES UNITY_BUILD ${Wop_ENABLE_UNITY_BUILD})

  if(Wop_ENABLE_PCH)
    target_precompile_headers(
      Wop_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(Wop_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    Wop_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(Wop_ENABLE_CLANG_TIDY)
    Wop_enable_clang_tidy(Wop_options ${Wop_WARNINGS_AS_ERRORS})
  endif()

  if(Wop_ENABLE_CPPCHECK)
    Wop_enable_cppcheck(${Wop_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(Wop_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    Wop_enable_coverage(Wop_options)
  endif()

  if(Wop_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(Wop_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(Wop_ENABLE_HARDENING AND NOT Wop_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR Wop_ENABLE_SANITIZER_UNDEFINED
       OR Wop_ENABLE_SANITIZER_ADDRESS
       OR Wop_ENABLE_SANITIZER_THREAD
       OR Wop_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    Wop_enable_hardening(Wop_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
