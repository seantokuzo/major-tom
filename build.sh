#!/bin/bash
set -euo pipefail

cd relay
npm run build
cd ../web
npm run build
cd ..