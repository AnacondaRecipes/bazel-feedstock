#!/bin/bash

set -euxo pipefail

if [[ "${target_platform}" == osx-* ]]; then
  export LDFLAGS="${LDFLAGS} -framework IOKit"
else
  export LDFLAGS="${LDFLAGS} -lpthread -labsl_synchronization -lm"
fi

# Generate toolchain and set necessary environment variables
source gen-bazel-toolchain

# For debugging purposes, you can add
# --logging=6 --subcommands --verbose_failures
# This is though too much log output for Travis CI.
# Extract minor.patch from libprotobuf version, that is the protoc version
# The protobuf-java needs to be manually bumped if necessary
# See https://protobuf.dev/support/version-support/
export PROTOC=$BUILD_PREFIX/bin/protoc
export GRPC_JAVA_PLUGIN=$BUILD_PREFIX/bin/grpc_java_plugin
export PROTOC_VERSION=$(conda list -p $PREFIX libprotobuf | grep -v '^#' | tr -s ' ' | cut -f 2 -d ' ' | sed -E 's/^[0-9]+\.([0-9]+\.[0-9]+)$/\1/')
export PROTOBUF_JAVA_MAJOR_VERSION="4"
export BAZEL_BUILD_OPTS="--crosstool_top=//bazel_toolchain:toolchain --define=PROTOBUF_INCLUDE_PATH=${PREFIX}/include --cpu=${TARGET_CPU} --cxxopt=-std=c++17"
export BAZEL_BUILD_OPTS="${BAZEL_BUILD_OPTS} --platforms=//bazel_toolchain:target_platform --host_platform=//bazel_toolchain:build_platform --extra_toolchains=//bazel_toolchain:cc_cf_toolchain --extra_toolchains=//bazel_toolchain:cc_cf_host_toolchain --toolchain_resolution_debug='.*'"
export EXTRA_BAZEL_ARGS="--tool_java_runtime_version=21 --java_runtime_version=21"
sed -ie "s:PROTOC_VERSION:${PROTOC_VERSION}:" WORKSPACE
sed -ie "s:PROTOBUF_JAVA_MAJOR_VERSION:${PROTOBUF_JAVA_MAJOR_VERSION}:" WORKSPACE
sed -ie "s:PROTOC_VERSION:${PROTOC_VERSION}:" MODULE.bazel
sed -ie "s:PROTOBUF_JAVA_MAJOR_VERSION:${PROTOBUF_JAVA_MAJOR_VERSION}:" MODULE.bazel
sed -ie "s:PROTOC_VERSION:${PROTOC_VERSION}:" third_party/systemlibs/protobuf/MODULE.bazel
sed -ie "s:PROTOBUF_JAVA_MAJOR_VERSION:${PROTOBUF_JAVA_MAJOR_VERSION}:" third_party/systemlibs/protobuf/MODULE.bazel
sed -ie "s:\${INSTALL_NAME_TOOL}:${INSTALL_NAME_TOOL:-install_name_tool}:" src/BUILD
sed -ie "s:\${PREFIX}:${PREFIX}:" src/BUILD
sed -ie "s:\${BUILD_PREFIX}:${BUILD_PREFIX}:" third_party/grpc/BUILD
sed -ie "s:\${BUILD_PREFIX}:${BUILD_PREFIX}:" third_party/grpc-java/BUILD
sed -ie "s:\${BUILD_PREFIX}:${BUILD_PREFIX}:" third_party/systemlibs/protobuf/BUILD
sed -ie "s:\${BUILD_PREFIX}:${BUILD_PREFIX}:" third_party/ijar/BUILD
sed -ie "s:\${BUILD_PREFIX}:${BUILD_PREFIX}:" src/tools/singlejar/BUILD
sed -ie "s:TARGET_CPU:${TARGET_CPU}:" compile.sh
sed -ie "s:BUILD_CPU:${BUILD_CPU}:" compile.sh

# The bootstrap Bazel (built from scratch via javac) has no BUILD_LABEL, so
# native.bazel_version returns "" which bazel_features interprets as a dev
# version newer than any release, enabling globals like `macro` that only
# exist in Bazel 8+. This env var tells the bootstrap to report the correct version.
export BAZEL_DEV_VERSION_OVERRIDE="${PKG_VERSION}"

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
if [[ "${target_platform}" == linux-* ]]; then
  patchelf --set-rpath '$ORIGIN/../lib' $PREFIX/bin/bazel-real
fi
mkdir -p $PREFIX/share/bazel/install
mkdir -p install-archive
pushd install-archive
  unzip $PREFIX/bin/bazel-real
  export INSTALL_BASE_KEY=$(cat install_base_key)
popd
mv install-archive $PREFIX/share/bazel/install/${INSTALL_BASE_KEY}
chmod -R a+w $PREFIX/share/bazel/install/${INSTALL_BASE_KEY}
for executable in "build-runfiles" "daemonize" "linux-sandbox" "process-wrapper"; do
  if [[ "${target_platform}" == osx-* ]]; then
    ${INSTALL_NAME_TOOL} -rpath ${PREFIX}/lib '@loader_path/../../../../lib' $PREFIX/share/bazel/install/${INSTALL_BASE_KEY}/$executable
  else
    patchelf --set-rpath '$ORIGIN/../../../../lib' $PREFIX/share/bazel/install/${INSTALL_BASE_KEY}/$executable
  fi
done
# Embedded tools (e.g. zipper.bin) are at varying depths under embedded_tools/
# and link against libstdc++/libgcc_s. Fix their rpaths to point to $PREFIX/lib
# so they resolve from the host prefix rather than the build prefix.
if [[ "${target_platform}" == linux-* ]]; then
  for embedded in $(find $PREFIX/share/bazel/install/${INSTALL_BASE_KEY}/embedded_tools -type f -executable); do
    if patchelf --print-rpath "$embedded" &>/dev/null; then
      rel_depth=$(python -c "import os.path; print(os.path.relpath('$PREFIX/lib', os.path.dirname('$embedded')))")
      patchelf --set-rpath "\$ORIGIN/$rel_depth" "$embedded" 2>/dev/null || true
    fi
  done
fi

# Set timestamps to untampered, otherwise bazel will reject the modified files as corrupted.
find $PREFIX/share/bazel/install/${INSTALL_BASE_KEY} -type f | xargs touch -mt $(($(date '+%Y') + 10))10101010
chmod -R a-w $PREFIX/share/bazel/install/${INSTALL_BASE_KEY}
