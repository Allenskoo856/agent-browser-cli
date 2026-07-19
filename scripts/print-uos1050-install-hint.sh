#!/usr/bin/env bash
set -euo pipefail
echo "This repository provides UOS 1050 build workflow only."
echo "For full offline multi-package install, use the offline-media kit:"
echo "  README: docs/UOS1050-OFFLINE.md"
echo "  Workflow: Actions -> build-uos-1050"
echo
if [[ -f BUILD_INFO.txt ]]; then
  echo "Found BUILD_INFO.txt in current dir:"
  cat BUILD_INFO.txt
fi
