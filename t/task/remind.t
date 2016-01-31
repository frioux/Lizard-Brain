#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use File::Temp 'tempdir', 'tempfile';
use IPC::Open3 'open3';
use IO::All;

$ENV{PATH} = 't/bin:' . $ENV{PATH};
my (undef, $db_path) = tempfile();
$ENV{LB_DSN} = "dbi:SQLite:$db_path";

system 'bin/maint/db-deploy';

subtest 'to + in' => sub {
  my $dir = tempdir( CLEANUP => 1 );
  local $ENV{TMPDIR} = $dir;

  my $child_pid = open3(my ($in, $out, $err), './tasks/remind');
  print $in "remind me to jump in 2 minutes\n";
  close $in;

  like(
    do { local $/; <$out> },
    qr/job \w+ at Sun Jan 24 20:00:00 2016\n/,
    'at output',
  );

  is (
    io->file($dir . "/at-in")->all,
    "t/bin/at now + 2 minutes\nbin/lb-set-reminder-by-id bin/action-pushover jump",
    'at input',
  );
};

subtest 'at' => sub {
  my $dir = tempdir( CLEANUP => 1 );
  local $ENV{TMPDIR} = $dir;

  my $child_pid = open3(my ($in, $out, $err), './tasks/remind');
  print $in "remind me catherine is here at 6pm Sunday\n";
  close $in;

  like(
    do { local $/; <$out> },
    qr/job \w+ at Sun Jan 24 20:00:00 2016\n/,
    'at output',
  );

  is (
    io->file($dir . "/at-in")->all,
    "t/bin/at 6pm Sunday\nbin/lb-set-reminder-by-id bin/action-pushover catherine is here",
    'at input',
  );
};

done_testing;
