#!/usr/bin/env bash
# Runs the pull-up animation tests with Lune (https://github.com/lune-org/lune).
# Usage: cd pullup-bars && bash tests/run.sh
set -e
lune run tests/compile.luau
for scale in 0.8 1 1.25; do
	lune run tests/sim.luau "$scale"
	lune run tests/sim.luau "$scale" "" mid
done
lune run tests/tap.luau
lune run tests/bake.luau
lune run tests/shop.luau
