#!/bin/bash
GLOBAL_FUNCTIONS="../../../global/pipeline/common/functions.sh"
cd $(dirname -- "$(readlink -f -- "$BASH_SOURCE")")
if [ -f "$GLOBAL_FUNCTIONS" ]; then
  # shellcheck source=/dev/null
  source "${GLOBAL_FUNCTIONS}"
else
  exit 1
fi

set -e

terragrunt_plan