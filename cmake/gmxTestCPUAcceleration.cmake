#
# This file is part of the GROMACS molecular simulation package.
#
# Copyright (c) 2012,2013,2014, by the GROMACS development team, led by
# Mark Abraham, David van der Spoel, Berk Hess, and Erik Lindahl,
# and including many others, as listed in the AUTHORS file in the
# top-level source directory and at http://www.gromacs.org.
#
# GROMACS is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public License
# as published by the Free Software Foundation; either version 2.1
# of the License, or (at your option) any later version.
#
# GROMACS is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with GROMACS; if not, see
# http://www.gnu.org/licenses, or write to the Free Software Foundation,
# Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA.
#
# If you want to redistribute modifications to GROMACS, please
# consider that scientific software is very special. Version
# control is crucial - bugs must be traceable. We will be happy to
# consider code for inclusion in the official distribution, but
# derived work must not be called official GROMACS. Details are found
# in the README & COPYING files - if they are missing, get the
# official version at http://www.gromacs.org.
#
# To help us fund GROMACS development, we humbly ask that you cite
# the research papers on the package. Check out http://www.gromacs.org.

# include avx test source, used if the AVX flags are set below
include(gmxTestAVXMaskload)
include(gmxFindFlagsForSource)


macro(gmx_use_clang_as_with_gnu_compilers_on_osx)
    # On OS X, we often want to use gcc instead of clang, since gcc supports
    # OpenMP. However, by default gcc uses the external system assembler, which
    # does not support AVX, so we need to tell the linker to use the clang
    # compilers assembler instead - and this has to happen before we detect AVX
    # flags.
    if(APPLE AND ${CMAKE_C_COMPILER_ID} STREQUAL "GNU")
        gmx_test_cflag(GNU_C_USE_CLANG_AS "-Wa,-q" ACCELERATION_C_FLAGS)
    endif()
    if(APPLE AND ${CMAKE_CXX_COMPILER_ID} STREQUAL "GNU")
        gmx_test_cxxflag(GNU_CXX_USE_CLANG_AS "-Wa,-q" ACCELERATION_CXX_FLAGS)
    endif()
endmacro()


macro(gmx_test_cpu_acceleration)
#
# To improve backward compatibility on x86 SIMD architectures,
# we set the flags for all accelerations that are supported, not only
# the most recent instruction set. I.e., if your machine supports AVX2_256,
# we will set flags both for AVX2_256, AVX_256, SSE4.1, and SSE2 support.

if(${GMX_CPU_ACCELERATION} STREQUAL "NONE")
    # nothing to do configuration-wise
    set(ACCELERATION_STATUS_MESSAGE "CPU SIMD acceleration disabled")
elseif(${GMX_CPU_ACCELERATION} STREQUAL "SSE2")

    gmx_find_cflag_for_source(CFLAGS_SSE2 "C compiler SSE2 flag"
                              "#include<xmmintrin.h>
                              int main(){__m128 x=_mm_set1_ps(0.5);x=_mm_rsqrt_ps(x);return 0;}"
                              ACCELERATION_C_FLAGS
                              "-msse2" "/arch:SSE2")
    gmx_find_cxxflag_for_source(CXXFLAGS_SSE2 "C++ compiler SSE2 flag"
                                "#include<xmmintrin.h>
                                int main(){__m128 x=_mm_set1_ps(0.5);x=_mm_rsqrt_ps(x);return 0;}"
                                ACCELERATION_CXX_FLAGS
                                "-msse2" "/arch:SSE2")

    if(NOT CFLAGS_SSE2 OR NOT CXXFLAGS_SSE2)
        message(FATAL_ERROR "Cannot find SSE2 compiler flag. Use a newer compiler, or disable acceleration (slower).")
    endif()

    set(GMX_CPU_ACCELERATION_X86_SSE2 1)
    set(GMX_X86_SSE2 1)

    set(ACCELERATION_STATUS_MESSAGE "Enabling SSE2 SIMD Gromacs acceleration")

elseif(${GMX_CPU_ACCELERATION} STREQUAL "SSE4.1")

    # Note: MSVC enables SSE4.1 with the SSE2 flag, so we include that in testing.
    gmx_find_cflag_for_source(CFLAGS_SSE4_1 "C compiler SSE4.1 flag"
                              "#include<smmintrin.h>
                              int main(){__m128 x=_mm_set1_ps(0.5);x=_mm_dp_ps(x,x,0x77);return 0;}"
                              ACCELERATION_C_FLAGS
                              "-msse4.1" "/arch:SSE4.1" "/arch:SSE2")
    gmx_find_cxxflag_for_source(CXXFLAGS_SSE4_1 "C++ compiler SSE4.1 flag"
                                "#include<smmintrin.h>
                                int main(){__m128 x=_mm_set1_ps(0.5);x=_mm_dp_ps(x,x,0x77);return 0;}"
                                ACCELERATION_CXX_FLAGS
                                "-msse4.1" "/arch:SSE4.1" "/arch:SSE2")

    if(NOT CFLAGS_SSE4_1 OR NOT CXXFLAGS_SSE4_1)
        message(FATAL_ERROR "Cannot find SSE4.1 compiler flag. "
                            "Use a newer compiler, or choose SSE2 acceleration (slower).")
    endif()

    if(CMAKE_C_COMPILER_ID MATCHES "Intel" AND CMAKE_C_COMPILER_VERSION VERSION_EQUAL "11.1")
        message(FATAL_ERROR "You are using Intel compiler version 11.1, which produces incorrect results with SSE4.1 acceleration. You need to use a newer compiler (e.g. icc >= 12.0) or in worst case try a lower level of acceleration if performance is not critical.")
    endif()

    set(GMX_CPU_ACCELERATION_X86_SSE4_1 1)
    set(GMX_X86_SSE4_1 1)
    set(GMX_X86_SSE2   1)
    set(ACCELERATION_STATUS_MESSAGE "Enabling SSE4.1 SIMD Gromacs acceleration")

elseif(${GMX_CPU_ACCELERATION} STREQUAL "AVX_128_FMA")

    gmx_use_clang_as_with_gnu_compilers_on_osx()

    # AVX128/FMA on AMD is a bit complicated. We need to do detection in three stages:
    # 1) Find the flags required for generic AVX support
    # 2) Find the flags necessary to enable fused-multiply add support
    # 3) Optional: Find a flag to enable the AMD XOP instructions

    ### STAGE 1: Find the generic AVX flag
    gmx_find_cflag_for_source(CFLAGS_AVX_128 "C compiler AVX (128 bit) flag"
                              "#include<immintrin.h>
                              int main(){__m128 x=_mm_set1_ps(0.5);x=_mm_permute_ps(x,1);return 0;}"
                              ACCELERATION_C_FLAGS
                              "-mavx" "/arch:AVX")
    gmx_find_cxxflag_for_source(CXXFLAGS_AVX_128 "C++ compiler AVX (128 bit) flag"
                                "#include<immintrin.h>
                                int main(){__m128 x=_mm_set1_ps(0.5);x=_mm_permute_ps(x,1);return 0;}"
                                ACCELERATION_CXX_FLAGS
                                "-mavx" "/arch:AVX")

    ### STAGE 2: Find the fused-multiply add flag.
    # GCC requires x86intrin.h for FMA support. MSVC 2010 requires intrin.h for FMA support.
    check_include_file(x86intrin.h HAVE_X86INTRIN_H ${ACCELERATION_C_FLAGS})
    check_include_file(intrin.h HAVE_INTRIN_H ${ACCELERATION_C_FLAGS})
    if(HAVE_X86INTRIN_H)
        set(INCLUDE_X86INTRIN_H "#include <x86intrin.h>")
    endif()
    if(HAVE_INTRIN_H)
        set(INCLUDE_INTRIN_H "#include <xintrin.h>")
    endif()

    gmx_find_cflag_for_source(CFLAGS_AVX_128_FMA "C compiler AVX (128 bit) FMA4 flag"
"#include<immintrin.h>
${INCLUDE_X86INTRIN_H}
${INCLUDE_INTRIN_H}
int main(){__m128 x=_mm_set1_ps(0.5);x=_mm_macc_ps(x,x,x);return 0;}"
                              ACCELERATION_C_FLAGS
                              "-mfma4")
    gmx_find_cxxflag_for_source(CXXFLAGS_AVX_128_FMA "C++ compiler AVX (128 bit) FMA4 flag"
"#include<immintrin.h>
${INCLUDE_X86INTRIN_H}
${INCLUDE_INTRIN_H}
int main(){__m128 x=_mm_set1_ps(0.5);x=_mm_macc_ps(x,x,x);return 0;}"
                                ACCELERATION_CXX_FLAGS
                                "-mfma4")

    # We only need to check the last (FMA) test; that will always fail if the basic AVX128 test failed
    if(NOT CFLAGS_AVX_128_FMA OR NOT CXXFLAGS_AVX_128_FMA)
        message(FATAL_ERROR "Cannot find compiler flags for 128 bit AVX with FMA support. Use a newer compiler, or choose SSE4.1 acceleration (slower).")
    endif()

    ### STAGE 3: Optional: Find the XOP instruction flag (No point in yelling if this does not work)
    gmx_find_cflag_for_source(CFLAGS_AVX_128_XOP "C compiler AVX (128 bit) XOP flag"
"#include<immintrin.h>
${INCLUDE_X86INTRIN_H}
${INCLUDE_INTRIN_H}
int main(){__m128 x=_mm_set1_ps(0.5);x=_mm_frcz_ps(x);return 0;}"
                              ACCELERATION_C_FLAGS
                              "-mxop")
    gmx_find_cxxflag_for_source(CXXFLAGS_AVX_128_XOP "C++ compiler AVX (128 bit) XOP flag"
"#include<immintrin.h>
${INCLUDE_X86INTRIN_H}
${INCLUDE_INTRIN_H}
int main(){__m128 x=_mm_set1_ps(0.5);x=_mm_frcz_ps(x);return 0;}"
                                ACCELERATION_CXX_FLAGS
                                "-mxop")

    # We don't have the full compiler version string yet (BUILD_C_COMPILER),
    # so we can't distinguish vanilla from Apple clang versions, but catering for a few rare AMD
    # hackintoshes is not worth the effort.
    if (APPLE AND (${CMAKE_C_COMPILER_ID} STREQUAL "Clang" OR
                ${CMAKE_CXX_COMPILER_ID} STREQUAL "Clang"))
        message(WARNING "Due to a known compiler bug, Clang up to version 3.2 (and Apple Clang up to version 4.1) produces incorrect code with AVX_128_FMA acceleration. As we cannot work around this bug on OS X, you will have to select a different compiler or CPU acceleration.")
    endif()


    if (GMX_USE_CLANG_C_FMA_BUG_WORKAROUND)
        # we assume that we have an external assembler that supports AVX
        message(STATUS "Clang ${CMAKE_C_COMPILER_VERSION} detected, enabling FMA bug workaround")
        set(EXTRA_C_FLAGS "${EXTRA_C_FLAGS} -no-integrated-as")
    endif()
    if (GMX_USE_CLANG_CXX_FMA_BUG_WORKAROUND)
        # we assume that we have an external assembler that supports AVX
        message(STATUS "Clang ${CMAKE_CXX_COMPILER_VERSION} detected, enabling FMA bug workaround")
        set(EXTRA_CXX_FLAGS "${EXTRA_CXX_FLAGS} -no-integrated-as")
    endif()

    gmx_test_avx_gcc_maskload_bug(GMX_X86_AVX_GCC_MASKLOAD_BUG "${ACCELERATION_C_FLAGS}")

    set(GMX_CPU_ACCELERATION_X86_AVX_128_FMA 1)
    set(GMX_X86_AVX_128_FMA 1)
    set(GMX_X86_SSE4_1      1)
    set(GMX_X86_SSE2        1)

    set(ACCELERATION_STATUS_MESSAGE "Enabling 128-bit AVX SIMD Gromacs acceleration (with fused-multiply add)")

elseif(${GMX_CPU_ACCELERATION} STREQUAL "AVX_256")

    gmx_use_clang_as_with_gnu_compilers_on_osx()

    gmx_find_cflag_for_source(CFLAGS_AVX "C compiler AVX (256 bit) flag"
                              "#include<immintrin.h>
                              int main(){__m256 x=_mm256_set1_ps(0.5);x=_mm256_add_ps(x,x);return 0;}"
                              ACCELERATION_C_FLAGS
                              "-mavx" "/arch:AVX")
    gmx_find_cxxflag_for_source(CXXFLAGS_AVX "C++ compiler AVX (256 bit) flag"
                                "#include<immintrin.h>
                                int main(){__m256 x=_mm256_set1_ps(0.5);x=_mm256_add_ps(x,x);return 0;}"
                                ACCELERATION_CXX_FLAGS
                                "-mavx" "/arch:AVX")

    if(NOT CFLAGS_AVX OR NOT CXXFLAGS_AVX)
        message(FATAL_ERROR "Cannot find AVX compiler flag. Use a newer compiler, or choose SSE4.1 acceleration (slower).")
    endif()

    gmx_test_avx_gcc_maskload_bug(GMX_X86_AVX_GCC_MASKLOAD_BUG "${ACCELERATION_C_FLAGS}")

    set(GMX_CPU_ACCELERATION_X86_AVX_256 1)
    set(GMX_X86_AVX_256  1)
    set(GMX_X86_SSE4_1   1)
    set(GMX_X86_SSE2     1)

    set(ACCELERATION_STATUS_MESSAGE "Enabling 256-bit AVX SIMD Gromacs acceleration")

elseif(${GMX_CPU_ACCELERATION} STREQUAL "AVX2_256")

    # Comment out this line for AVX2 development
    message(FATAL_ERROR "AVX2_256 is disabled until the implementation has been commited.")

    gmx_use_clang_as_with_gnu_compilers_on_osx()

    gmx_find_cflag_for_source(CFLAGS_AVX2 "C compiler AVX2 flag"
                              "#include<immintrin.h>
                              int main(){__m256 x=_mm256_set1_ps(0.5);x=_mm256_fmadd_ps(x,x,x);return 0;}"
                              ACCELERATION_C_FLAGS
                              "-march=core-avx2" "-mavx2" "/arch:AVX") # no AVX2-specific flag for MSVC yet
    gmx_find_cxxflag_for_source(CXXFLAGS_AVX2 "C++ compiler AVX2 flag"
                                "#include<immintrin.h>
                                int main(){__m256 x=_mm256_set1_ps(0.5);x=_mm256_fmadd_ps(x,x,x);return 0;}"
                                ACCELERATION_CXX_FLAGS
                                "-march=core-avx2" "-mavx2" "/arch:AVX") # no AVX2-specific flag for MSVC yet

    if(NOT CFLAGS_AVX2 OR NOT CXXFLAGS_AVX2)
        message(FATAL_ERROR "Cannot find AVX2 compiler flag. Use a newer compiler, or choose AVX acceleration (slower).")
    endif()

    # No need to test for Maskload bug - it was fixed before gcc added AVX2 support

    set(GMX_CPU_ACCELERATION_X86_AVX2_256 1)
    set(GMX_X86_AVX2_256 1)
    set(GMX_X86_AVX_256  1)
    set(GMX_X86_SSE4_1   1)
    set(GMX_X86_SSE2     1)

    set(ACCELERATION_STATUS_MESSAGE "Enabling 256-bit AVX2 Gromacs acceleration")

elseif(${GMX_CPU_ACCELERATION} STREQUAL "IBM_QPX")

    try_compile(TEST_QPX ${CMAKE_BINARY_DIR}
        "${CMAKE_SOURCE_DIR}/cmake/TestQPX.c")

    if (TEST_QPX)
        message(WARNING "IBM QPX acceleration was selected. This will work, but SIMD-accelerated kernels are only available for the Verlet cut-off scheme. The plain C kernels that are used for the group cut-off scheme kernels will be slow, so please consider using the Verlet cut-off scheme.")
        set(GMX_CPU_ACCELERATION_IBM_QPX 1)
        set(ACCELERATION_STATUS_MESSAGE "Enabling IBM QPX SIMD acceleration")

    else()
        message(FATAL_ERROR "Cannot compile the requested IBM QPX intrinsics. If you are compiling for BlueGene/Q with the XL compilers, use 'cmake .. -DCMAKE_TOOLCHAIN_FILE=Platform/BlueGeneQ-static-XL-C' to set up the tool chain.")
    endif()

elseif(${GMX_CPU_ACCELERATION} STREQUAL "SPARC64_HPC_ACE")

    set(GMX_CPU_ACCELERATION_SPARC64_HPC_ACE 1)
    set(ACCELERATION_STATUS_MESSAGE "Enabling Sparc64 HPC-ACE SIMD acceleration")

elseif(${GMX_CPU_ACCELERATION} STREQUAL "REFERENCE")

    add_definitions(-DGMX_SIMD_REFERENCE_PLAIN_C)
    if(${GMX_NBNXN_REF_KERNEL_TYPE} STREQUAL "4xn")
        if(${GMX_NBNXN_REF_KERNEL_WIDTH} STREQUAL "2" OR ${GMX_NBNXN_REF_KERNEL_WIDTH} STREQUAL "4" OR ${GMX_NBNXN_REF_KERNEL_WIDTH} STREQUAL "8")
            add_definitions(-DGMX_NBNXN_SIMD_4XN -DGMX_SIMD_REF_WIDTH=${GMX_NBNXN_REF_KERNEL_WIDTH})
        else()
            message(FATAL_ERROR "Unsupported width for 4xn reference kernels")
        endif()
    elseif(${GMX_NBNXN_REF_KERNEL_TYPE} STREQUAL "2xnn")
        if(${GMX_NBNXN_REF_KERNEL_WIDTH} STREQUAL "8" OR ${GMX_NBNXN_REF_KERNEL_WIDTH} STREQUAL "16")
            add_definitions(-DGMX_NBNXN_SIMD_2XNN -DGMX_SIMD_REF_WIDTH=${GMX_NBNXN_REF_KERNEL_WIDTH})
        else()
            message(FATAL_ERROR "Unsupported width for 2xn reference kernels")
        endif()
    else()
        message(FATAL_ERROR "Unsupported kernel type")
    endif()

else()
    gmx_invalid_option_value(GMX_CPU_ACCELERATION)
endif()


gmx_check_if_changed(ACCELERATION_CHANGED GMX_CPU_ACCELERATION)
if (ACCELERATION_CHANGED AND DEFINED ACCELERATION_STATUS_MESSAGE)
    message(STATUS "${ACCELERATION_STATUS_MESSAGE}")
endif()

endmacro()
