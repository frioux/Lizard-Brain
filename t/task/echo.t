#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

use IPC::Open3 'open3';

my $child_pid = open3(my ($in, $out, $err), './tasks/echo');
print $in "echo station\n";
close $in;

is(do { local $/; <$out> }, "station\n", 'echos');

done_testing;
