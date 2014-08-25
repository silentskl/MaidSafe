
function(GET_DEPEND_OS_LIBS target result)
  SET(deps ${${target}_LIB_DEPENDS})
  IF(deps)
   FOREACH(lib ${deps})
    IF(NOT lib MATCHES "general" AND NOT lib MATCHES "debug" AND NOT lib MATCHES "optimized")
      GET_TARGET_PROPERTY(lib_location ${lib} LOCATION)
      IF(NOT lib_location)
        SET(ret ${ret} ${lib})
      ENDIF()
    ENDIF()
   ENDFOREACH()
  ENDIF()
  SET(${result} ${ret} PARENT_SCOPE)
endfunction()

set(DevLibDepends maidsafe_common
                  maidsafe_passport
                  maidsafe_rudp
                  maidsafe_routing
                  maidsafe_encrypt
                  maidsafe_api
                  maidsafe_nfs_core
                  maidsafe_nfs_client
                  ${AllBoostLibs}
                  cryptopp
                  protobuf_lite
                  protobuf
                  sqlite)
list(REMOVE_ITEM DevLibDepends BoostGraphParallel BoostMath BoostMpi BoostRegex BoostSerialization BoostTest)
foreach(Libb ${DevLibDepends})
  message("lib - ${Libb}")
endforeach()

SET(SOURCE_FILE ${CMAKE_CURRENT_BINARY_DIR}/maidsafe_depends.cc)
ADD_LIBRARY(maidsafe STATIC ${SOURCE_FILE})
target_include_directories(maidsafe PUBLIC "${CMAKE_SOURCE_DIR}/src/common/include/maidsafe")
SET(OSLIBS)
FOREACH(LIB ${DevLibDepends})
  message("target libs" "${LIB}")
  GET_TARGET_PROPERTY(LIB_LOCATION ${LIB} LOCATION_RELEASE)
  GET_TARGET_PROPERTY(LIB_TYPE ${LIB} TYPE)
  IF(NOT LIB_LOCATION)
     LIST(APPEND OSLIBS ${LIB})
  ELSE()
    IF(LIB_TYPE STREQUAL "STATIC_LIBRARY")
      SET(STATIC_LIBS ${STATIC_LIBS} ${LIB_LOCATION})
      ADD_DEPENDENCIES(maidsafe ${LIB})
      GET_DEPEND_OS_LIBS(${LIB} LIB_OSLIBS)
      LIST(APPEND OSLIBS ${LIB_OSLIBS})
    ELSE()
      LIST(APPEND OSLIBS ${LIB})
    ENDIF()
  ENDIF()
ENDFOREACH()
IF(OSLIBS)
  LIST(REMOVE_DUPLICATES OSLIBS)
  TARGET_LINK_LIBRARIES(maidsafe PUBLIC ${OSLIBS})
ENDIF()

ADD_CUSTOM_COMMAND(
  OUTPUT  ${SOURCE_FILE}
  COMMAND ${CMAKE_COMMAND}  -E touch ${SOURCE_FILE}
  DEPENDS ${STATIC_LIBS})

IF(MSVC)
  SET(LINKER_EXTRA_FLAGS "")
  FOREACH(LIB ${STATIC_LIBS})
    SET(LINKER_EXTRA_FLAGS "${LINKER_EXTRA_FLAGS} ${LIB}")
  ENDFOREACH()
  SET_TARGET_PROPERTIES(maidsafe PROPERTIES STATIC_LIBRARY_FLAGS
    "${LINKER_EXTRA_FLAGS}")
ELSE()
  GET_TARGET_PROPERTY(TARGET_LOCATION maidsafe LOCATION)
  IF(APPLE)
    ADD_CUSTOM_COMMAND(TARGET maidsafe POST_BUILD
      COMMAND rm ${TARGET_LOCATION}
      COMMAND /usr/bin/libtool -static -o ${TARGET_LOCATION}
      ${STATIC_LIBS}
    )
  ELSE()
    ADD_CUSTOM_COMMAND(TARGET maidsafe POST_BUILD
      COMMAND rm ${TARGET_LOCATION}
      COMMAND
    )
      unix_static_lib()
  ENDIF()
ENDIF()


function(unix_static_lib)
  SET(TEMP_DIR ${CMAKE_CURRENT_BINARY_DIR}/merge_libs_temp_dir)
  MAKE_DIRECTORY(${TEMP_DIR})
  FOREACH(LIB ${STATIC_LIBS})
    GET_FILENAME_COMPONENT(NAME_NO_EXT ${LIB} NAME_WE)
    SET(TEMP_SUBDIR ${TEMP_DIR}/${NAME_NO_EXT})
    MAKE_DIRECTORY(${TEMP_SUBDIR})
    EXECUTE_PROCESS(
      COMMAND ${CMAKE_AR} -t ${LIB}
      OUTPUT_VARIABLE LIB_OBJS
      )
    STRING(REGEX REPLACE "\n" ";" LIB_OBJ_LIST "${LIB_OBJS}")
    STRING(REGEX REPLACE ";$" "" LIB_OBJ_LIST "${LIB_OBJ_LIST}")

    LIST(LENGTH LIB_OBJ_LIST LENGTH_WITH_DUPS)
    SET(LIB_OBJ_LIST_NO_DUPS ${LIB_OBJ_LIST})
    LIST(REMOVE_DUPLICATES LIB_OBJ_LIST_NO_DUPS)
    LIST(LENGTH LIB_OBJ_LIST_NO_DUPS LENGTH_WITHOUT_DUPS)

    IF(LENGTH_WITH_DUPS EQUAL LENGTH_WITHOUT_DUPS)
      EXECUTE_PROCESS(
        COMMAND ${CMAKE_AR} -x ${LIB}
        WORKING_DIRECTORY ${TEMP_SUBDIR}
        )
    ELSE()
      LIST(SORT LIB_OBJ_LIST)
      SET(SAME_OBJ_COUNT 1)
      SET(LAST_OBJ_NAME)
      FOREACH(OBJ ${LIB_OBJ_LIST})
        IF(OBJ STREQUAL LAST_OBJ_NAME)
          GET_FILENAME_COMPONENT(OBJ_NO_EXT ${OBJ} NAME_WE)
          FILE(RENAME "${TEMP_SUBDIR}/${OBJ}" "${TEMP_SUBDIR}/${OBJ_NO_EXT}.${SAME_OBJ_COUNT}.o")
          MATH(EXPR SAME_OBJ_COUNT "${SAME_OBJ_COUNT}+1")
        ELSE()
          SET(SAME_OBJ_COUNT 1)
        ENDIF()
        SET(LAST_OBJ_NAME "${OBJ}")
        EXECUTE_PROCESS(
          COMMAND ${CMAKE_AR} -xN ${SAME_OBJ_COUNT} ${LIB} ${OBJ}
          WORKING_DIRECTORY ${TEMP_SUBDIR}
          )
      ENDFOREACH()
    ENDIF()

    FILE(GLOB_RECURSE LIB_OBJECTS "${TEMP_SUBDIR}/*.o")
    SET(OBJECTS ${OBJECTS} ${LIB_OBJECTS})
  ENDFOREACH()

# Use relative paths, makes command line shorter.
  GET_FILENAME_COMPONENT(ABS_TEMP_DIR ${TEMP_DIR} ABSOLUTE)
  FOREACH(OBJ ${OBJECTS})
    FILE(RELATIVE_PATH OBJ ${ABS_TEMP_DIR} ${OBJ})
    FILE(TO_NATIVE_PATH ${OBJ} OBJ)
    SET(ALL_OBJECTS ${ALL_OBJECTS} ${OBJ})
  ENDFOREACH()

  FILE(TO_NATIVE_PATH ${TARGET_LOCATION} ${TARGET_LOCATION})
# Now pack the objects into library with ar.
  EXECUTE_PROCESS(
    COMMAND ${CMAKE_AR} rcs ${TARGET_LOCATION} ${ALL_OBJECTS}
    WORKING_DIRECTORY ${TEMP_DIR}
  )

# Cleanup
  FILE(REMOVE_RECURSE ${TEMP_DIR})
endfunction()
