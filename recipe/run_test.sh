# Test by building an example from the tutorial.
# https://github.com/bazelbuild/examples/
# https://docs.bazel.build/versions/master/tutorial/cpp.html
set -exuo pipefail
trap 'bazel shutdown 2>/dev/null || true' EXIT

cp -r ${RECIPE_DIR}/tutorial .
cd tutorial
source gen-bazel-toolchain

bazel build --logging=6 --subcommands --verbose_failures //main:hello-world \
  --platforms=//bazel_toolchain:target_platform \
  --host_platform=//bazel_toolchain:build_platform \
  --extra_toolchains=//bazel_toolchain:cc_cf_toolchain \
  --extra_toolchains=//bazel_toolchain:cc_cf_host_toolchain
