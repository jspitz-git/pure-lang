if(NOT DEFINED PURE_JIT_SMOKE OR NOT DEFINED PURE_ATTEMPTS)
  message(FATAL_ERROR "Missing Pure fresh-process JIT arguments")
endif()

foreach(attempt RANGE 1 ${PURE_ATTEMPTS})
  execute_process(
    COMMAND "${PURE_JIT_SMOKE}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE stdout
    ERROR_VARIABLE stderr
    TIMEOUT 60
  )
  set(output "${stdout}${stderr}")
  if(NOT result EQUAL 0)
    message(FATAL_ERROR
      "Fresh JIT process ${attempt}/${PURE_ATTEMPTS} failed with ${result}:\n${output}")
  endif()
  if(output MATCHES
     "IMAGE_REL_AMD64_ADDR32NB|AddressSanitizer|runtime error:")
    message(FATAL_ERROR
      "Fresh JIT process ${attempt}/${PURE_ATTEMPTS} reported an address failure:\n${output}")
  endif()
endforeach()
message("Pure fresh-process JIT attempts passed: ${PURE_ATTEMPTS}")
