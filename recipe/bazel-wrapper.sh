#!/bin/bash

PREFIX_DIR=$(dirname ${BASH_SOURCE})
# Make PREDIX_DIR absolute
if [[ $(uname) == 'Linux' ]]; then
  PREFIX_DIR=$(readlink -f ${PREFIX_DIR})
else
  cd ${PREFIX_DIR}
  PREFIX_DIR=$(pwd -P)
  cd - &>/dev/null
fi

# Go one level up
PREFIX_DIR=$(dirname ${PREFIX_DIR})
# FIXME: Since migrating to gRPC 1.78.0, we are seeing spurious hangs with
# the client/server setup on macOS. Remove again if those are gone.
# `bazel --version` is answered by the client only when it is the sole argument
# (blaze.cc); adding --batch makes it an unknown startup option. No server starts.
if [[ "$*" = *"--version"* ]]; then
  $PREFIX_DIR/bin/bazel-real $*
elif [[ "$*" != *"--output_user_root"* ]]; then
  $PREFIX_DIR/bin/bazel-real --batch --output_user_root ${PREFIX_DIR}/share/bazel $*
else
  $PREFIX_DIR/bin/bazel-real --batch $*
fi
