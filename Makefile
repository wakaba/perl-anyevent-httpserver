all:

## ------ Setup ------

WGET = wget
PERL = perl
GIT = git
PERL_VERSION = latest
PERL_PATH = $(abspath local/perlbrew/perls/perl-$(PERL_VERSION)/bin)

Makefile-setupenv: Makefile.setupenv
	$(MAKE) --makefile Makefile.setupenv setupenv-update \
	    SETUPENV_MIN_REVISION=20120910

Makefile.setupenv:
	$(WGET) -O $@ https://raw.github.com/wakaba/perl-setupenv/master/Makefile.setupenv

lperl lprove local-perl perl-version perl-exec \
pmb-install pmb-update \
: %: Makefile-setupenv
	$(MAKE) --makefile Makefile.setupenv $@

deps: pmb-install

## ------ Tests ------

PROVE = prove
PERL_ENV = PATH="$(abspath ./local/perl-$(PERL_VERSION)/pm/bin):$(PERL_PATH):$(PATH)" PERL5LIB="$(shell cat config/perl/libs.txt)"

test: test-deps test-main

test-deps: deps

test-main:
	$(PERL_ENV) $(PROVE) t/*.t
