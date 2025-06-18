#!/usr/bin/env perl

use 5.030003;
use strict;
use warnings;
use threads;
use threads::shared 1.51;
use Thread::Semaphore;
use Time::HiRes qw| usleep |;
use Test::More;
use Data::Dumper;
use IPC::Open2 ();
use DBD::Oracle

local $Data::Dumper::Indent = 1;
local $Data::Dumper::Terse  = 1;

our $VERSION      = 0.1;
our $ORACLE_HOME  = $ENV{ORACLE_HOME};
our $TNS_ADMIN    = $ENV{TNS_ADMIN};
our $ORA_SOURCE   = get_source( $ENV{ORA_SOURCE} );
our $ORA_SCHEMA   = get_schema( $ENV{ORA_SCHEMA} );
our $ORA_PASSWD   = get_passwd( $ENV{ORA_PASSWD} );

my $TEST_START = Time::HiRes::time();

{
    my $DO_CONNECT:shared;
    my $DO_EXIT:shared;
    my $READY:shared;

    BEGIN {
        $DO_CONNECT = $ENV{NO_CONNECT} || $ENV{NO_DB}
            ? 0 : 1;
        $DO_EXIT    = Thread::Semaphore->new(0);
        $READY      = Thread::Semaphore->new(0);

        $SIG{__DIE__} = sub {
            my $msg = shift;
            note sprintf 'Thread ID: %d (DIE) %s', threads->tid, $msg;
            threads->exit(1);
        };

        $SIG{__WARN__} = sub {
            my $msg = shift;
            note sprintf 'Thread ID: %d (WARN) %s', threads->tid, $msg;
        };

        $SIG{INT} = sub {
            my $msg = shift;
            note sprintf 'Thread ID: %d (INT) %s', threads->tid, $msg;
            threads->exit(1);
        };

        $SIG{TERM} = sub {
            my $msg = shift;
            note sprintf 'Thread ID: %d (TERM) %s', threads->tid, $msg;
            threads->exit(1);
        };
    }

    END {
        note sprintf 'Thread ID: %d (END)', threads->tid;
    }

    sub do_exit     { $DO_EXIT->up(shift) }
    sub all_ready
    {
        my $count = shift;
        threads->yield;
        note sprintf 'READY = %d, THREADS=%d', $$READY, $count;
        $READY->down($count);
    }

    sub DB_WORKER
    {
        my $thread_id = threads->tid;
        my $dbh;

        note "Thread ID: $thread_id (ready to serve)";

        if ( $DO_CONNECT )
        {
            note "Thread ID: $thread_id (connecting to DB)";
            $dbh = DBI->connect( $ORA_SOURCE, $ORA_SCHEMA, $ORA_PASSWD,
                { RaiseError => 1, AutoCommit => 0 })
                or die "Could not connect to database: $DBI::errstr";

            $dbh->ping or die "Could not ping database: $DBI::errstr";
        }

        $READY->up;

        if ( $DO_EXIT->down )
        {
            note sprintf "Thread ID: $thread_id (exiting) EXIT=%d RDY=%d", $$DO_EXIT, $$READY;
        }

        # Simulate some work
        # usleep(1000000); # Sleep for 1 second

        if ( $dbh )
        {
            note "Thread ID: $thread_id (disconnecting from DB)";
            $dbh->disconnect;
        }

        return 1;
    }
}


sub section
{
  my $msg = shift;
  note '+ --------------------------------------------- +';
  note " $msg";
  note '+ --------------------------------------------- +';
  return;
}

sub abort
{
  my $msg = shift;
  printf STDERR "\n";
  printf STDERR "# + --------------------------------------------- +\n";
  printf STDERR "#   %s\n", $msg;
  printf STDERR "# + --------------------------------------------- +\n";
  printf STDERR "\n";
  note sprintf 'Completed in %5.3fs', Time::HiRes::time() - $TEST_START;
  done_testing();
  exit 1;
}

ORACLE_SETUP:
{
  section 'ORACLE Settings Configured';

  ok    $ORACLE_HOME,   'ORACLE_HOME is-set';
  ok -d $ORACLE_HOME,   'ORACLE_HOME found';
  ok    $TNS_ADMIN,     'TNS_ADMIN is-set';
  ok -d $TNS_ADMIN,     'TNS_ADMIN found';
  ok    $ORA_SOURCE,    'ORA_SOURCE detected' or abort 'SETUP: export ORA_SOURCE="Oracle DB identifier"';
  ok    $ORA_SCHEMA,    'ORA_SCHEMA detected' or abort 'SETUP: export ORA_SCHEMA="Oracle DB SCHEMA"';
  ok    $ORA_PASSWD,    'ORA_PASSWD detected' or abort 'SETUP: export ORA_PASSWD="Oracle DB PASSWORD"';
}

PERL_NOTICE:
{
  section 'PERL - runtime';

  my $perl_path;

  ok(( open my $_f, '-|', 'which perl' ), '(which perl)->open');
  ok(( $perl_path = <$_f> ), 'read path' );
  ok $_f->close,  'f->close';

  chomp $perl_path;

  ok    $perl_path, $perl_path;
  ok -x $perl_path, "-x $perl_path";

  note qx|perl -V|;
}

LAUNCH:
{
  section 'Launching Threads';

  my $loop = 3;
  my $thread_count = 5;

  for my $pass ( 1 .. $loop )
  {
    my @threads = ();

    ok $pass, sprintf 'Loop %d', $pass;

    for ( 1 .. $thread_count )
    {
        my $thread = threads->create(\&DB_WORKER);
        push @threads, $thread;
    }

    all_ready( $thread_count );
    do_exit( $thread_count );

    foreach my $thread (@threads) {
        my $result = $thread->join();
        ok $result, sprintf 'Thread completed successfully tid=%d', $thread->tid;
    }

    note sprintf 'Threads: %d', scalar(@threads);
  }
}

note sprintf 'Completed in %5.3fs', Time::HiRes::time() - $TEST_START;
done_testing();

## SUBS && QUEUE

sub run_cmd
{
  my $cmd = shift;
  my $val = '';

  eval {
    IPC::Open2::open2( my $I, my $O, $cmd );
    $val = <$I>;
    $O->close;
    $I->close;
  };

  return $val;
}

sub get_source
{
  return shift # ||
  # run_cmd qq|perl -MTG::Cmd::Auth -e 'printf "%s", (TG::Cmd::Auth->new->get_tgdb_rw)[0]' |;
}

sub get_schema
{
  return shift # ||
  # run_cmd qq|perl -MTG::Cmd::Auth -e 'printf "%s", (TG::Cmd::Auth->new->get_tgdb_rw)[1]' |;
}

sub get_passwd
{
  return shift # ||
  # run_cmd qq|perl -MTG::Cmd::Auth -e 'printf "%s", (TG::Cmd::Auth->new->get_tgdb_rw)[2]' |;
}

## vim: expandtab noet ts=4 sw=4 sts=4 ft=perl :
## END
