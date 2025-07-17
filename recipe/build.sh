#!/bin/bash

set -euxo pipefail

if [[ "${target_platform}" == osx-* ]]; then
  export LDFLAGS="${LDFLAGS} -framework IOKit"
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