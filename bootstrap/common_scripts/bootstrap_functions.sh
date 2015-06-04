#!/bin/bash

# Uses Git to find the top level directory so that everything can be referenced
# via absolute paths.
REPO_ROOT=$(git rev-parse --show-toplevel)


