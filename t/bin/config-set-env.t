#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

delete $ENV{LB_TASKS};
is(
   qx(bin/config-set-env sh -c 'echo \$LB_TASKS'),
   "./tasks\n",
   'LB_TASKS defaulted correctly',
);

done_testing;
