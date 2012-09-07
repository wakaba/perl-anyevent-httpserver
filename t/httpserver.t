#!/bin/sh
echo "1..1"
basedir=`dirname $0`/..
(PERL5LIB="`cat $basedir/config/perl/libs.txt`" perl -c $basedir/lib/httpserver.pl && echo "ok 1") || echo "not ok 1"
