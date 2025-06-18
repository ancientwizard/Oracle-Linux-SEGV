#!/bin/bash

## USAGE:
##  $ mkdir /<LOCATION>/.build-perl
##  $ cp auto-build-perl.sh /<LOCATION>/.build-perl/
##  $ cd /<LOCATION>/.build-perl/
##  $ ./build-perl.sh perl-5.nn.n.tar.gz

## Default Build
#MIN='-min'
REF="${1:-perl-5.40.2.tar.gz}"
OIC="${ORACLE_HOME#/usr/lib/oracle/}"
OIC="${OIC%/client64}"
BASE="${PWD%/*}"

title ()  { echo "$1"; }
abort ()  { echo ' ABRT ->> '"$*"; title 'ABORTED'; exit 1; }
info  ()  { echo ' INFO ->> '"$*"; }

announce_begin ()
{
  local PERL="${REF%.tar.gz}"
  title "BUILDING: ${PERL} ${OIC}"
  info '+ -------------------------------- +'
  info "  Building: ${PERL} ${OIC}"
  info '+ -------------------------------- +'
}

announce_end ()
{
  local PERL="${REF%.tar.gz}"
  title "COMPLETE: ${PERL} ${OIC}"
  echo
  info '+ -------------------------------- +'
  info "  Complete: ${PERL} ${OIC}"
  info '+ -------------------------------- +'
  echo
}

announce_fail ()
{
  local PERL="${REF%.tar.gz}"
  title "BUILD-FAIL: ${PERL} ${OIC}"
  echo
  info '+ -------------------------------- +'
  info "  ABORT: ${PERL} ${OIC}"
  info '+ -------------------------------- +'
  echo
}

get_perl_tar ()
{
  local URI='https://www.cpan.org'
  local LEAF='/src/5.0/'
  local PERL=$REF
  [ -f ./$PERL ] && return $? \
    || curl -k --output ./${PERL} "${URI}${LEAF}${PERL}"
}

rebuild_perl ()
{
  local PERL=$REF
  local INST="${BASE}/${PERL%.tar.gz}-oic-${OIC}${MIN}"
  local BULD="./${PERL%.tar.gz}"
  local DBUG="-DEBUGGING=-g -O0"
# local DEVL="-Dusedevel"

  [ -r $PERL ] || return $?
  [ -d $BULD ] && rm -rf $BULD
  [ -d $BULD ] || info  'Confirmed BULD '$BULD' is removed (fresh build)'
  [ -d $INST ] && rm -rf $INST
  [ -d $INST ] && abort 'Confirmed INST '$INST' exists! (ABORT)' || \
    info 'Confirmed INST '$INST' is removed. (fresh install)'

  tar xzf $PERL && \
  (
    cd $BULD && \
    sed -i "s/^optimize=''/optimize='-O0 -g'/" Configure && \
    CFLAGS="-fsanitize=address -g -fno-omit-frame-pointer" LDFLAGS="-fsanitize=address" \
    ./Configure -des -Dusethreads -Duse64bitint -Duse64bitall -Dprefix=${INST} $DEVL \
      -Alddlflags="-shared -g -O0 -L/usr/local/lib -fstack-protector-strong" \
      -Accflags="-g -O0" \
    && make install
  )
}

cpan_env ()
{
   local PERL="${REF%.tar.gz}-oic-${OIC}${MIN}"
  export PERL_LWP_SSL_VERIFY_HOSTNAME=0
  export PERL_RL_TEST_PROMPT_MENLEN=0
  export DATE_MANIP_TEST_DM5=1
  export PERL_READLINE_NOWARN=1

  export PATH=${BASE}/${PERL}/bin:/usr/sbin:/usr/bin
  echo $PATH
  which perl

  return 0
}

cpan_finish ()
{
  cpan_env

  cpan Log::Log4perl Config::Simple Term::ReadKey &&
  cpan GSSAPI DBI DBD::Oracle
}


  announce_begin  && \
##check_settings  && \
  get_perl_tar    && \
  rebuild_perl    && \
  cpan_finish     && \

announce_end || announce_fail

## vim: number expandtab tabstop=2 shiftwidth=2
## END
