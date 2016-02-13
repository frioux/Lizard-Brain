#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

use HTTP::Request;
use Test::WWW::Mechanize::PSGI;
use Plack::Util;

$ENV{MY_CELL} = '12345678900';
$ENV{LB_PASS} = '';

ok(my $app = Plack::Util::load_psgi('./www/cgi-bin/impulse-www'), 'App loaded');

my $ua = Test::WWW::Mechanize::PSGI->new(app => $app);
$ua->credentials('twilio', 'test');
my $r = int rand 10;
my $response = $ua->request(
  HTTP::Request->new(GET => '/twilio?From=12345678900&Body=echo+test+' . $r)
);

is($response->content, 'test ' . $r . "\n", 'Expected response');

done_testing;
