#!/bin/sh
echo "1..1"
basedir=`dirname $0`/..
(perl -c $basedir/bin/staticpageserver.pl && echo "ok 1") || echo "not ok 1"
