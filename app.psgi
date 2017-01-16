#!/usr/bin/env plackup

use strict;
use warnings;

use autodie;

package LizardBrain::WWW;
use Web::Simple;
use IO::Socket::IP;
use Plack::Middleware::Auth::Basic;
use Authen::Passphrase;
use Digest::SHA qw(hmac_sha1_hex);
use Plack::Request;
use String::Compare::ConstantTime;
use Encode qw(encode decode);
use URI::Escape;

die 'Set LB_PASS to a password hash'
  unless defined $ENV{LB_PASS};

my $pw = Authen::Passphrase->from_crypt($ENV{LB_PASS});

sub twilio {
  my ($self, $from, $body) = @_;

  '' => sub {
    Plack::Middleware::Auth::Basic->new(
      authenticator => sub {
        my ($username, $password, $env) = @_;

        $pw->match("u$username:p$password");
      },
    ),
  },
  '' => sub {
    return [ 405, [ 'Content-type', 'text/plain' ], [ 'Not authorized yo' ] ]
      unless $from eq $ENV{MY_CELL};

    my $sock = IO::Socket::IP->new(
       PeerHost => '127.0.0.1',
       PeerPort => 8000,
       Type     => SOCK_STREAM,
     ) or return [
       500,
       [ 'Content-type', 'text/plain' ],
       [ "Cannot construct socket - $@" ]
     ];

     # TODO: bubble up non-zero exits somehow
     print $sock encode('UTF-8', "$body");

     shutdown $sock, 1;

     local $/;
     [ 200, [ 'Content-type', 'text/plain' ], [ <$sock> ] ]
  },
}

my $secret = $ENV{LB_GH_SECRET};

sub github {
  my ($self, $env) = @_;

  my $req = Plack::Request->new($env);
  my $x_hub_signature = $req->header('X-Hub-Signature');
  my $calculated_signature = 'sha1='.  hmac_sha1_hex($req->content, $secret);

  return [
    405,
    [ 'Content-type' => 'text/plain' ],
    [ 'invalid mac yo' ],
  ] unless String::Compare::ConstantTime::equals($x_hub_signature, $calculated_signature);

  require JSON;
  my $content = JSON::decode_json($req->content);

  `git fetch`;
  `git reset --hard \@{upstream}`;
  `bin/maint/db-deploy`
    if -e 'bin/maint/db-deploy';

  return [
    200,
    [ 'Content-type' => 'text/plain' ],
    [ 'Updated!' ],
  ]
}

sub notes {
  my ($self, $path, $env, $which) = @_;

  '' => sub {
    my $pw = Authen::Passphrase->from_crypt($ENV{LB_NOTES_PASS});

    Plack::Middleware::Auth::Basic->new(
      authenticator => sub {
        my ($username, $password, $env) = @_;

        $pw->match("u$username:p$password");
      },
    ),
  },

  '' => sub {
    require File::Dropbox;
    require Tie::IxHash;

    tie my %tree, 'Tie::IxHash';
    my $tree = \%tree;
    my @stack = ($tree);

    my $dropbox = File::Dropbox->new(
       access_token  => $ENV{DROPBOX_ACCESS_TOKEN},
       root => 'dropbox',
       oauth2 => 1,
    );

    open $dropbox, '<', $which;

    while (<$dropbox>) {
      $_ = decode('UTF-8', $_);
      my ($depth, $msg) = m/^(\t*)(.+)$/;
      next unless $msg;

      pop @stack while $#stack > length $depth;
      tie my %itree, 'Tie::IxHash';
      push @stack, ( $stack[-1]{$msg} = \%itree );
    }

    $tree = $tree->{$_} for @$path;

    my $title = "Lizard Brain: /" . join q(/), @$path;
    [
      200,
      [ content_type => 'text/html; charset=utf-8' ],
      [
        encode('UTF-8', qq[<html>
          <head>
            <meta charset="utf-8">
            <title>$title</title>
          </head>
          <body>
          <ol>] .
            ( join "\n", map "<li>" . $self->_link($path, $_, $tree) . "</li>", keys %$tree) .
          '</ol>
          </body></html>'
        )
      ]
    ]
  }
}

our $root;
sub _link {
  my ($self, $path, $link, $tree) = @_;

  if ($link =~ s(^bible://)()) {
    my ($version) = $link =~ m/@(\w+)$/;
    $link =~ s/@\w+$//;
    $version ||= 'ESV';

    $link = "https://www.biblegateway.com/passage/?version=$version&search=" . uri_escape($link);
  }

  $link =~ s(^fogbugz://)(https://ziprecruiter.fogbugz.com/f/cases/);

  my $prefix = "";
  $prefix = qq(<a href="$link">[ link ]</a> )
    if $link =~ m(^https?://);

  my @keys = keys %{$tree->{$link}};
  return "$prefix" . qq(<a href="$keys[0]">$link</a>)
    if @keys == 1 && $keys[0] =~ m(^https?://);

  return "$prefix$link" unless @keys;

  my $q = join '&', map 'q=' . uri_escape_utf8($_), @$path, $link;
  return qq($prefix<a href="/$root?$q">$link</a>)
}

$|++;
sub dispatch_request {
  'GET + /twilio + ?From=&Body=' => 'twilio',
  '/github' => 'github',
  '/notes + ?@q~' => sub {
    $root = 'notes';
    shift->notes(@_, $ENV{LB_NOTES})
  },
  '/reference + ?@q~' => sub {
    $root = 'reference';
    shift->notes(@_, $ENV{LB_REFERENCE})
  },
  '/ok' => sub {
    [ 200, [ 'Content-Type', 'text/plain' ], [ "All is well\n\n" . `git rev-parse HEAD` ] ],
  },
  '' => sub {
    [ 405, [ 'Content-type', 'text/plain' ], [ 'Method not allowed' ] ]
  }
}
LizardBrain::WWW->run_if_script;

# vim: ft=perl