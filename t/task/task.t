#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

use IPC::Open3 'open3';
use IO::All;

$ENV{LB_TASKS} = './tasks';
my $child_pid = open3(my ($in, $out, $err), './tasks/task');
print $in "task list\n";
close $in;

my $expected = join '', map $_->filename . "\n", io->dir('./tasks')->all;

is(do { local $/; <$out> }, $expected, 'lists tasks');

done_testing;

