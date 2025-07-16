#!/bin/bash

cd $SRC_DIR

set -euxo pipefail

if [[ "${target_platform}" == osx-* ]]; then
  export LDFLAGS="${LDFLAGS} -framework IOKit"
  # See also https://gitlab.kitware.com/cmake/cmake/-/issues/25755
#   export CFLAGS="${CFLAGS} -fno-define-target-os-macros"
else
  export LDFLAGS="${LDFLAGS} -lpthread -labsl_synchronization -lm"
fi

# Generate toolchain and set necessary environment variables
source gen-bazel-toolchain

if [[ "${target_platform}" == "osx-64" ]]; then
  export TARGET_CPU="darwin"
fi

export BAZEL_BUILD_OPTS="--crosstool_top=//bazel_toolchain:toolchain --define=PROTOBUF_INCLUDE_PATH=${PREFIX}/include --cpu=${TARGET_CPU} --cxxopt=-std=c++17"
export BAZEL_BUILD_OPTS="${BAZEL_BUILD_OPTS} --platforms=//bazel_toolchain:target_platform --host_platform=//bazel_toolchain:build_platform --extra_toolchains=//bazel_toolchain:cc_cf_toolchain --extra_toolchains=//bazel_toolchain:cc_cf_host_toolchain --toolchain_resolution_debug='.*'"
export EXTRA_BAZEL_ARGS="--tool_java_runtime_version=21 --java_runtime_version=21"

./compile.sh

mkdir -p $PREFIX/bin/
cp ${RECIPE_DIR}/bazel-wrapper.sh $PREFIX/bin/bazel
chmod +x $PREFIX/bin/bazel
mv output/bazel $PREFIX/bin/bazel-real

# Explicitly unpack the contents of the bazel binary. This is normally done
# on demand during runtime. Then this is extracted to a random location and
# we cannot fix the RPATHs reliably.
#
# conda's binary relocation logic sadly doesn't work otherwise as
#  * The binaries are zipped into the main executable.
#  * Modifying the binaries changes their mtime and then bazel rejects them
#    as corrupted.
# if [[ "${target_platform}" == linux-* ]]; then
#   patchelf --set-rpath '$ORIGIN/../lib' $PREFIX/bin/bazel-real
# fi
# mkdir -p $PREFIX/share/bazel/install
# mkdir -p install-archive
# pushd install-archive
#   unzip $PREFIX/bin/bazel-real
#   export INSTALL_BASE_KEY=$(cat install_base_key)
# popd
# mv install-archive $PREFIX/share/bazel/install/${INSTALL_BASE_KEY}
# chmod -R a+w $PREFIX/share/bazel/install/${INSTALL_BASE_KEY}
# for executable in "build-runfiles" "daemonize" "linux-sandbox" "process-wrapper"; do
#   if [[ "${target_platform}" == osx-* ]]; then
#     ${INSTALL_NAME_TOOL} -rpath ${PREFIX}/lib '@loader_path/../../../../lib' $PREFIX/share/bazel/install/${INSTALL_BASE_KEY}/$executable
#   else
#     patchelf --set-rpath '$ORIGIN/../../../../lib' $PREFIX/share/bazel/install/${INSTALL_BASE_KEY}/$executable
#   fi
# done

# # Set timestamps to untampered, otherwise bazel will reject the modified files as corrupted.
# find $PREFIX/share/bazel/install/${INSTALL_BASE_KEY} -type f | xargs touch -mt $(($(date '+%Y') + 10))10101010
# chmod -R a-w $PREFIX/share/bazel/install/${INSTALL_BASE_KEY}