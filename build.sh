#!/bin/bash

cd relay
npm run build
cd ../web
npm run build
cd ..