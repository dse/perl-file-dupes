#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset
shopt -s lastpipe
set -o xtrace

progdir="$(dirname "$0")"
cd "${progdir}"

rm -fr tmp || true
mkdir tmp

mkdir tmp/1 tmp/2 tmp/3 tmp/4 tmp/5 tmp/6 tmp/7 tmp/8 tmp/9 tmp/10
echo 'hello world' >tmp/1/1
ln tmp/1/1 tmp/2/1
ln tmp/1/1 tmp/3/1
echo 'hello world' >tmp/4/1
echo 'hello earth' >tmp/5/1
echo 'hello earth' >tmp/6/1
ln tmp/6/1 tmp/7/1
echo 'hello earth' >tmp/8/1
ln tmp/8/1 tmp/9/1
echo 'hello planet' >tmp/10/1

>&2 echo "dry run"
../bin/dupesxs -n 1 tmp/{1,2,3,4,5,6,7,8,9,10}
>&2 echo "dry run, verbose"
../bin/dupesxs -n -v 1 tmp/{1,2,3,4,5,6,7,8,9,10}
>&2 echo "dry run, verbose, verify"
../bin/dupesxs --test -n -v 1 tmp/{1,2,3,4,5,6,7,8,9,10}
