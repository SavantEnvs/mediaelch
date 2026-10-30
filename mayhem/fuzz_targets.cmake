# Injected with -DCMAKE_PROJECT_INCLUDE=... so upstream's CMakeLists.txt stays untouched.
# Defers to the end of the top-level directory, when libmediaelch exists, and adds one libFuzzer
# binary and one run-once standalone reproducer per parser.
function(mayhem_add_fuzzers)
  set(out_dir "$ENV{SRC}")
  if(NOT out_dir)
    set(out_dir "${CMAKE_SOURCE_DIR}")
  endif()
  set(harness_dir "${CMAKE_SOURCE_DIR}/mayhem")
  set(kinds
      movie_nfo=1 tvshow_nfo=2 episode_nfo=3 concert_nfo=4 album_nfo=5 artist_nfo=6
      advanced_settings=7 placeholder_parser=8)
  foreach(entry IN LISTS kinds)
    string(REPLACE "=" ";" parts "${entry}")
    list(GET parts 0 name)
    list(GET parts 1 kind)

    add_executable(fuzz_${name} "${harness_dir}/harness.cpp" "${MAYHEM_LSAN_OFF}")
    target_compile_definitions(fuzz_${name} PRIVATE FUZZ_KIND=${kind})
    target_link_libraries(fuzz_${name} PRIVATE libmediaelch)
    target_link_options(fuzz_${name} PRIVATE -fsanitize=fuzzer)
    set_target_properties(fuzz_${name} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${out_dir}")

    add_executable(fuzz_${name}-standalone "${harness_dir}/harness.cpp" "${MAYHEM_LSAN_OFF}"
                   "$ENV{STANDALONE_FUZZ_MAIN}")
    set_source_files_properties("$ENV{STANDALONE_FUZZ_MAIN}" PROPERTIES LANGUAGE C)
    target_compile_definitions(fuzz_${name}-standalone PRIVATE FUZZ_KIND=${kind})
    target_link_libraries(fuzz_${name}-standalone PRIVATE libmediaelch)
    set_target_properties(fuzz_${name}-standalone PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${out_dir}")
  endforeach()
endfunction()

cmake_language(DEFER DIRECTORY "${CMAKE_SOURCE_DIR}" CALL mayhem_add_fuzzers)
