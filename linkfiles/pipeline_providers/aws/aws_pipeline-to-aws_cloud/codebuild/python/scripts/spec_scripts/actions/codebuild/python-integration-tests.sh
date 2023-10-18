#!/bin/bash
DIR=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")
COMMON_GLOBAL_FUNCTIONS="${DIR}/../../../../../common/scripts/global/pipeline/common/functions.sh"
GLOBAL_FUNCTIONS="${DIR}/../../../global/pipeline/common/functions.sh"

cd "${DIR}"
if [ -f "$COMMON_GLOBAL_FUNCTIONS" ] || [ -f "$GLOBAL_FUNCTIONS" ]; then
  # shellcheck source=/dev/null
  source "${COMMON_GLOBAL_FUNCTIONS}"
  # shellcheck source=/dev/null
  source "${GLOBAL_FUNCTIONS}"
else
  exit 1
fi

set -e

python_integration_tests