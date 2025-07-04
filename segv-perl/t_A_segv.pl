#!/usr/bin/env perl

use 5.030003;
use strict;
use warnings;
use threads;
use threads::shared 1.51;
use Time::HiRes qw| usleep |;
use Test::More;
use Data::Dumper;
use IPC::Open2 ();

local $Data::Dumper::Indent = 1;
local $Data::Dumper::Terse  = 1;

our $VERSION      = 0.1;
our $ORACLE_HOME  = $ENV{ORACLE_HOME};
our $TNS_ADMIN    = $ENV{TNS_ADMIN};
our $ORA_SOURCE   = get_source( $ENV{ORA_SOURCE} );
our $ORA_SCHEMA   = get_schema( $ENV{ORA_SCHEMA} );
our $ORA_PASSWD   = get_passwd( $ENV{ORA_PASSWD} );

my $TEST_START = Time::HiRes::time();

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

THREADS_ALONE:
{
  section 'Threads stress testing';

# is threads->tid,  0,  'main-thread identified';

  for ( 1 .. 2 )
  {
    {
      my $queue = DB::Queue->new;

      is ref $queue, 'DB::Queue', 'isa DB::Queue';

      ok  ! $queue->isEnabled,          '! q->isEnabled';
      ok    $queue->enable(5),          '  q->enable(X)';
      ok    $queue->isEnabled,          '  q->isEnabled';
      ok    $queue->disable,            '  q->disable';
    }

    ok    DB::Queue->new->isDisabled,  '  q->isDisabled';
  }
}

sub thread_worker { DB::Queue::_THREAD_WORKER(@_); }

THREADS_SEGV:
{
# last THREADS_SEGV if 1;

  section 'Threads + DB->ping stress testing';

  my $onemore;    ## to be the last but used only once
  my $do_onemore = 0;

  ## <= 2 OKAY; > 2 SEGV!!! unless one $do_onemore is enabled to control disconnect order
  my $size = 3;

  sub finish_onemore
  {
    if ( $onemore && $onemore->{THRD} )
    {
    # note 'SNEEK IN ANOTHER (BEGIN)';
    # my ( $in, $ou ) = ( Thread::Queue->new, Thread::Queue->new );
    # my $thr = threads->create( \&thread_worker, $in, $ou );
    # $in->enqueue( DB::Msg::Ping->new );
    # threads->yield;
    # note 'SNEEK IN ANOTHER (END)';
    # usleep 200000;

      note 'EXIT THE-ONE-MORE thread';
    # DBI->trace(6);
      my ( $Qin, $thr ) = ( $onemore->{Q_IN}, $onemore->{THRD} );
      $Qin->enqueue( DB::Msg::Exit->new );
      sleep 1;
      $thr->join;
      note 'EXIT THE-ONE-MORE thread (joined)';
    }

    $onemore = undef;

    return
  }

  for my $loop ( 1 .. 3 )
  {
    note "START LOOP $loop";
  # sleep 4;

    {
      my $queue = DB::Queue->new;

      is ref $queue, 'DB::Queue', 'isa DB::Queue';

      ok  ! $queue->isEnabled,          '! q->isEnabled';
      ok    $queue->enable($size),      '  q->enable(X)';
      ok    $queue->isEnabled,          '  q->isEnabled';
      ok  ! $queue->ping,               '  q->ping';

      while ( $queue->ping < $size ) { $queue->run; usleep 5000 }

      is    $queue->ping, $size,  '  ALL->connected';

      if ( $do_onemore && ! $onemore )
      {
        $onemore = {};

        my ( $Qin, $Qou ) = ( Thread::Queue->new, Thread::Queue->new );
        my $thr = threads->create( \&thread_worker, $Qin, $Qou );

        $onemore->{Q_IN} = $Qin;
        $onemore->{Q_OU} = $Qou;
        $onemore->{THRD} = $thr;

        $Qin->enqueue( DB::Msg::Ping->new );

        note '+ ------------------------------------------ +';
        note '  Ping->one-more (NEW)';
        note '+ ------------------------------------------ +';
      # sleep 4;
      }
    # else
    # {
    #   note '+ ------------------------------------------ +';
    #   note '  Ping->one-more (PRE-EXISTS)';
    #   note '+ ------------------------------------------ +';
    # # sleep 4;
    # }

      note "  END LOOP $loop";
    # sleep 4;
    # note 'Manual Disable: ', $queue->disable;
      finish_onemore;
    }

    ok( DB::Queue->new->isDisabled,  '  q->isDisabled (auto-cleanup DESTROY)' );
    note qx/ps -o rss,size,pid,cmd -p $$/;
  }

  finish_onemore;
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


package DB::Queue;

use strict;
use warnings;
use threads::shared 1.51;
use Thread::Queue;
use Time::HiRes qw| usleep |;
use DBI;
use Test::More;
use Data::Dumper;

our $VERSION;
our $ENABLED;
our $TCOUNT;
our $QUEUE_IN;
our $QUEUE_OU;
our $STATUS;
our $THREADS;

our $ONETHR :shared;

BEGIN {
  $VERSION  = 0.1;
  $ONETHR   = 1;
  $ENABLED  = 0;
  $QUEUE_IN = [];
  $QUEUE_OU = [];
  $STATUS   = {};
  $THREADS  = [];

# DBI->trace(3);
}

sub CLONE {
  $ENABLED  = 0;
  $STATUS   = {};
  $THREADS  = [];
  $QUEUE_IN = [];
  $QUEUE_OU = [];
}

DESTROY { __PACKAGE__->disable; }
END     { __PACKAGE__->disable; }

sub new
{
  return bless {}, shift;
}

sub isEnabled
{
  return $ENABLED && $ENABLED > 0
}

sub isDisabled { return ! isEnabled() }

sub disable
{
  my $self = shift;

# printf "# %s->disable\n", threads->tid;

  if ( threads->tid == 0 && scalar @ $THREADS )
  {
  # printf "# DISABLE %s threads\n", scalar @ $THREADS;

    while ( scalar @ $THREADS )
    {
      my ( $qI, $qO ) = ( shift( @ $QUEUE_IN ), shift( @ $QUEUE_OU ));
      my $thr     = shift @ $THREADS;
      my $status  = delete $STATUS->{ $thr->tid };

      $qI && $qI->enqueue( DB::Msg::Exit->new );

      if ( $thr )
      {
        while ( ! $thr->is_joinable ) { usleep( 20000 ); }
        note 'join ', $thr->tid;
        $thr->join;
      }

      threads->yield;
    }

    $ENABLED = 0;
  }

  return $self->isDisabled;
}

sub enable
{
  my $self = shift;
  my $threads = shift;

  if ( $threads && $self->isDisabled )
  {
    for my $cnt ( 1 .. $threads )
    {
      my ( $Qin, $Qou ) = ( Thread::Queue->new, Thread::Queue->new );
      push @ $QUEUE_IN, $Qin;
      push @ $QUEUE_OU, $Qou;

      my $thr = threads->create( \&_THREAD_WORKER, $Qin, $Qou );
      push @ $THREADS, $thr;
      $STATUS->{ $thr->tid } = 0;

      $ENABLED++;
    }
  }

  return $self->isEnabled;
}

sub ping
{
  my $self = shift;
  my $conn = 0;

  for my $queue ( @ $QUEUE_IN )
  {
    $queue->enqueue( DB::Msg::Ping->new );
  }

  for my $state ( values % $STATUS ) { $state && $conn++ }

  return $conn;
}

sub run
{
  my $self = shift;
  my $msg;

  for my $queue ( @ $QUEUE_OU )
  {
    while ( $msg = $queue->dequeue_nb )
    {
      if ( $msg->isState )
      {
        $STATUS->{ $msg->tid } = $msg->isConnected;
        next;
      }

      warn 'unexpected: ' . ref $msg;
    }
  }

  return;
}

QUEUE_BACKEND:
{
  my $tid;
  my $queue_in;
  my $queue_ou;
  my $dbh;

  sub _THREAD_WORKER
  {
    $tid = threads->tid;
    $queue_in = shift;
    $queue_ou = shift;

  # printf "# %2d IN: %s\n", $tid, ref $queue_in;
  # printf "# %2d OU: %s\n", $tid, ref $queue_ou;

    BUSY:
    while (1)
    {
      my $msg;

      while ( defined( $msg = $queue_in->dequeue_nb ))
      {
        ## CASE - PING
        if ( $msg->isPing )
        {
        # printf "# tid-%s PING\n", $tid;
          _connect();
        # $queue_ou->enqueue( DB::Msg::Ping::ACK->new( $dbh && $dbh->ping ));
          $queue_ou->enqueue( DB::Msg::Ping::ACK->new( $dbh ? 1 : 0 ));
          next;
        }

        ## CASE - EXIT
        if ( $msg->isExit )
        {
          _disconnect();
        # $queue_ou->enqueue( DB::Msg::Ping::ACK->new( 0 ));
          last BUSY;
        }

        printf STDERR "# Unexpected %s\n", ref $msg;
      }

      usleep 50000;
    }

  # printf "# tid-%s EXIT\n", $tid;

    return 1;
  }

  sub _connect
  {
    if ( ! $dbh )
    {
      lock $ONETHR;
      printf "# CONNECT-ENTER %d\n", $tid;
      $dbh = DBI->connect( $main::ORA_SOURCE, $main::ORA_SCHEMA, $main::ORA_PASSWD );
      printf "# CONNECT-EXIT  %d\n", $tid;
    # threads->yield;
    # usleep 250000;
    }

  # threads->yield;

    return;
  }

  sub _disconnect
  {
    if ( $dbh )
    {
      lock $ONETHR;
      printf "# DISCONNECT-ENTER %d\n", $tid;
      $dbh->disconnect;
      $dbh = undef;
      printf "# DISCONNECT-EXIT  %d\n", $tid;
    # threads->yield;
    # usleep 250000;
    }

  # threads->yield;

    return;
  }
}


package DB::Msg;

use strict;
use warnings;

sub new { return bless {}, shift }
sub isExit  { return 0 }
sub isPing  { return 0 }
sub isState { return 0 }

package DB::Msg::Exit;

use strict;
use warnings;

our @ISA;
BEGIN { push @ISA, 'DB::Msg' }

sub new { return (shift)->SUPER::new }
sub isExit  { return 1 }
sub isPing  { return 0 }
sub isState { return 0 }


package DB::Msg::Ping;

our @ISA;
BEGIN { push @ISA, 'DB::Msg' }

use strict;
use warnings;

sub new { return (shift)->SUPER::new }
sub isExit  { return 0 }
sub isPing  { return 1 }
sub isState { return 0 }

package DB::Msg::Ping::ACK;

use strict;
use warnings;

our @ISA;
BEGIN { push @ISA, 'DB::Msg' }

sub new
{
  my $self = (shift)->SUPER::new;
  $self->{TID} = threads->tid;
  $self->{CONNECTED} = shift;
  return $self;
}

sub isExit  { return 0 }
sub isPing  { return 0 }
sub isState { return 1 }

sub tid         { return $_[0]->{TID} }
sub isConnected { return $_[0]->{CONNECTED} }

## vim: number expandtab tabstop=2 shiftwidth=2
## END
