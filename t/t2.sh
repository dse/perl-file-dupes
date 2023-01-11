set -o errexit
set -o pipefail
set -o nounset
shopt -s lastpipe
set -o xtrace

progdir="$(dirname "$0")"
cd "${progdir}"

rm -fr tmp || true
mkdir tmp

mkdir tmp/1 tmp/2 tmp/3 tmp/4 tmp/5 tmp/6 tmp/7 tmp/8 tmp/9 tmp/10 tmp/11 tmp/12 tmp/13
echo 'hello world' >tmp/1/hello
echo 'hello world' >tmp/2/hello #
echo 'hello world' >tmp/3/hello #
ln tmp/1/hello tmp/4/hello
ln tmp/2/hello tmp/5/hello      #
ln tmp/2/hello tmp/6/hello      #
echo 'hello cruel world' >tmp/7/hello
echo 'hello crap world.' >tmp/8/hello
echo 'hello shitty world' >tmp/9/hello
echo 'hello cruel world' >tmp/10/hello #
echo 'hello musty world' >tmp/11/hello

>&2 echo "dry run"
../bin/dupebyname -n 1 tmp/{1,2,3,4,5,6,7,8,9,10,11,12,13}
>&2 echo "dry run, verbose"
../bin/dupebyname -n -v 1 tmp/{1,2,3,4,5,6,7,8,9,10,11,12,13}
>&2 echo "dry run, verbose, verify"
../bin/dupebyname --test -n -v 1 tmp/{1,2,3,4,5,6,7,8,9,10,11,12,13}
