#!/bin/bash

set -e -o pipefail

dub build -b release --compiler=$DC
dub clean
