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
use Tie::IxHash;
use File::Dropbox;

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

    tie my %tree, 'Tie::IxHash';
    my $tree = \%tree;
    my @stack = ($tree);

    my $dropbox = $self->_dropbox;

    open $dropbox, '<', $ENV{LB_NOTES};

    while (<$dropbox>) {
      $_ = decode('UTF-8', $_);
      my ($depth, $msg) = m/^(\t*)(.+)$/;
      next unless $msg;

      pop @stack while $#stack > length $depth;
      tie my %itree, 'Tie::IxHash';
      push @stack, ( $stack[-1]{$msg} = \%itree );
    }

    my $show;
    $show = sub {
      my ($hash, $simplify, $fh, $offset) = @_;

      $fh ||= \*STDOUT;
      $offset ||= 0;

      my $i = 0;
      for my $key (keys %$hash) {
        my $out = "$key\n";
        $out =~ s/\[_\]\s*// if $simplify;
        my $str = ("\t" x $offset) . $out;
        $str = encode('UTF-8', $str);
        print $fh "\n" if !$offset && $i;
        print $fh $str;
        $show->($hash->{$key}, $simplify, $fh, $offset + 1) if $hash->{$key} && %{ $hash->{$key} };
        $i++
      }
    };

    my $update = sub {
      open $dropbox, '>', "$ENV{LB_NOTES}";
      $show->(shift, 0, $dropbox);
      close $dropbox;
    };

    my $dig_random = sub {
      my @path = @_;

      my $inner_tree = $tree;
      $inner_tree = $inner_tree->{$_} for @path;

      my ($choice) = shuffle(grep !m/\[X\]/, keys %$inner_tree);

      $inner_tree->{$choice =~ s/\[_\]/[X]/r } =
        delete $inner_tree->{$choice};

      $update->($tree);

      $show->({ $choice => $inner_tree->{$choice} }, 1);
    };

    chomp(my $in = $body);
    $in =~ s/^\s*//;
    $in =~ s/\s*$//;

    if ($in =~ m/^inspire\s+me$/i) {
      warn sprintf "[%d] note: inspiring\n", getppid;
      $dig_random->('Incubation', 'Inspiration')
    } elsif ($in =~ m/^beer\s+me\s+a\s+video$/i) {
      warn sprintf "[%d] note: videoing\n", getppid;
      $dig_random->('Incubation', 'Videos')
    } elsif ($in =~ m/^beer\s+me\s+a\s+song$/i) {
      warn sprintf "[%d] note: musicing\n", getppid;
      $dig_random->('Incubation', 'Music')
    } elsif ($in =~ m/^(?:q|enqueue|queue)\s+(video|song|music|inspiration|idea|drama|comedy|restaurant)\s+(.*)$/i) {
      my $key = lc $1;
      my $item = $2;
      warn sprintf "[%d] note: q'ing $item\n", getppid;
      if ($key eq 'video') {
        $key = 'Videos'
      } elsif ($key =~ m/^(?:song|music)$/) {
        $key = 'Music'
      } elsif ($key eq 'inspiration') {
        $key = 'Inspiration'
      } elsif ($key eq 'idea') {
        $key = 'Ideas'
      } elsif ($key eq 'drama') {
        $key = 'Dramas'
      } elsif ($key eq 'comedy') {
        $key = 'Comedies'
      } elsif ($key eq 'restaurant') {
        $key = 'Restaurants'
      }

      $tree->{Incubation}{$key}{"$item"} = {};

      $update->($tree);

     return [ 200, [ 'Content-type', 'text/plain' ], [ "Enqueued Item!" ] ]
    } elsif ($in =~ m/^(?:q|enqueue|queue)\s+in\s+(.*)$/i) {
      my $item = $1;
      warn sprintf "[%d] note: q in $item\n", getppid;

      $tree->{IN}{"$item"} = {};

      $update->($tree);

     return [ 200, [ 'Content-type', 'text/plain' ], [ "Enqueued Item!" ] ]
    } elsif ($in =~ m/^echo notes$/i) {
      my $str = "";
      open my $fh, '<', \$str;
      $show->($tree, 0, $str);
      return [ 200, [ 'Content-type', 'text/plain' ], [ $str ] ]
    } else {
      exit 1
    }

     [ 500, [ 'Content-type', 'text/plain' ], [ "fell through" ] ]
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

sub _dropbox {
  File::Dropbox->new(
    access_token  => $ENV{DROPBOX_ACCESS_TOKEN},
    root => 'dropbox',
    oauth2 => 1,
  )
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

    my $dropbox = $self->_dropbox;

    open $dropbox, '<', $which;

    return [
      200,
      [ 'content-type' => 'text/plain;charset=utf-8', ],
      [ <$dropbox> ]
    ] if $path && ref $path eq 'HASH' && $path->{guts};

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
      [ 'content-type' => 'text/html; charset=utf-8' ],
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
  '/notes + ?guts=' => sub {
    $root = 'notes';
    shift->notes({ guts => 1 }, $_[-1], $ENV{LB_NOTES})
  },
  '/notes + ?@q~' => sub {
    $root = 'notes';
    shift->notes(@_, $ENV{LB_NOTES})
  },
  '/js_notes' => sub {
    [
      200,
      [ content_type => 'text/html; charset=utf-8' ],
      [
        encode('UTF-8', q[<html>
          <head>
            <meta charset="utf-8">
            <title>Lizard Brain</title>
            <script src="https://code.jquery.com/jquery-1.11.3.js"></script>
            <script>
              var tree;
              $(function() {
                $.ajax({
                  url: "/notes?guts=1",
                  success: function(x) {
                    let lines = x.split(/\n/);
                    tree = new Map();
                    let stack = [tree];

                    let re = /^(\t*)(.+)$/;
                    lines.forEach(function(line) {
                      let result = re[Symbol.match](line);

                      if (!result) return;

                      let depth = result[1];
                      let msg   = result[2];

                      if (!msg) return;

                      while ( (stack.length-1) > depth.length ) {
                        stack.pop()
                      }
                      let itree = new Map();
                      stack[stack.length - 1].set(msg, itree);
                      stack.push(itree);

                    });

                    hash = decodeURI(window.location.hash)
                    hash = hash.replace(/^#/, '')
                    hash = hash.split("☃").filter(function(x) x.length)

                    renderTree(hash);
                  },
                  error: function(x) { console.log(x) }
                })
              });
              window.onpopstate = window.onpushstate = function() {
                  hash = decodeURI(window.location.hash)
                  hash = hash.replace(/^#/, '')
                  hash = hash.split("☃").filter(function(x) x.length)

                  renderTree(hash);
              };
              function renderTree(path) {
                let rtree = tree;
                path.forEach(function(x) { rtree = rtree.get(x) });

                var str = "<ol>"

                let it = rtree.keys();
                let x;
                while (x = it.next().value) {
                  i_path = []
                  i_path.push.apply(i_path, path)
                  i_path.push(x)
                  str += "<li><a href='#" + encodeURI(i_path.join("☃")) + "'>" + x + "</a></li>";
                }

                str += "</ol>";

                $('#list').html(str)
              }
            </script>
          </head>
          <body>
          <div id="list"></div>
          </body></html>
      ])
    ]
  ]
  },
  '/reference + ?@q~' => sub {
    $root = 'reference';
    shift->notes(@_, $ENV{LB_REFERENCE})
  },
  '/reference + ?guts=' => sub {
    $root = 'reference';
    shift->notes({ guts => 1 }, $_[-1], $ENV{LB_REFERENCE})
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
