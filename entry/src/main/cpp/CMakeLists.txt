# the minimum version of CMake.
cmake_minimum_required(VERSION 3.4.1)
project(justpdf_piano)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include)

add_library(piano SHARED napi_init.cpp piano_engine.cpp)

target_link_libraries(piano PUBLIC
    libace_napi.z.so
    libohaudio.so
    libhilog_ndk.z.so)

add_library(justpdfpdf SHARED napi_pdfio.cpp pdf_annot_writer.cpp)

target_link_libraries(justpdfpdf PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so
    libz.so)
