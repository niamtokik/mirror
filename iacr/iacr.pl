#! /usr/bin/perl
######################################################################
#
######################################################################

use strict;
use warnings;

{ package _crud;
  use strict;
  use warnings;
  use LWP;

  my $_create = sub {
    my $self = shift();
    my $args = { @_ };
  };
  
  my $_read = sub {
    my $self = shift();
    my $Target = $self->{target};
    my $Method = shift();
    my $UserAgent = LWP::UserAgent->new();
    my $Request = HTTP::Request->new($Method => $Target);
    my $Result = $UserAgent->request($Request);
    return $Result;
  };

  my $_update = sub {
    my $self = shift();
    my $args = { @_ };
  };

  my $_delete = sub {
    my $self = shift();
  };

  sub new {
    my $class = shift(); 
    my $self = { target => shift() };
    bless($self, $class);
    return $self;
  }

  sub head() {
    my $self = shift();
    return $self->$_read("HEAD");
  }

  sub get() {
    my $self = shift();
    return $self->$_read("GET");
  }

  1; }

{ package _parser;
  use strict;
  use warnings;

  sub new {
    my $class = shift();
    my $self = { @_ };
    bless($self, $class);
    unless($self->{separator}) {
      $self->separator(qr(\n));
    }
    return $self;
  }

  sub parse {
    my $self = shift();
    my $data = shift();
    my $accumulator = shift();
    my %state;
    foreach my $line (split($self->{separator}, $data)) {
      foreach my $key (%{ $self->{handlers} }) {
        if ($line =~ $key) {
          $self->{handlers}->{$key}($line, $accumulator, \%state);
        }
      }
    }
    return $accumulator;
  }

  sub separator($) {
    my $self = shift();
    my $Separator = shift();
    $self->{separator} = $Separator;
    return $self;
  }

  sub handler {
    my $self = shift();
    my $Regex = shift();
    my $Callback = shift();
    $self->{handlers}->{$Regex} = $Callback; 
    return $self;
  }

  1; }


sub iacr {
  my $hash = shift();
  my $source = shift();
  my $destination = shift();
  my @iacr;

  if ($hash->{link} and $hash->{title}) {
    my $link = $hash->{link};
    my $title = $hash->{title};

    if ($hash->{pdf}) { 
      push(@iacr, 
           { source => sprintf("%s/%s.pdf", $source, $link),
             destination => sprintf("%s/%s-%s.pdf", $destination, $link, $title)
           });
    }

    if ($hash->{ps}) { 
      push(@iacr, 
           { source => sprintf("%s/%s.ps", $source, $link),
             destination => sprintf("%s/%s-%s.ps", $destination, $link, $title)
           });
    }
  }
  foreach my $i (@iacr) {
    unless (-f $i->{destination}) {
      my @split = split(qr(/+), $i->{destination});
      my @splice = splice(@split, 0, -1);
      my $dir = join("/", @splice);
      unless (-d $dir) {
        printf("mkdir %s\n", $dir);
        qx(mkdir -p $dir)
      }
      unless (-f $i->{destination}) {
        printf("download %s to %s\n", $i->{source}, $i->{destination});
        qx(curl $i->{source} -o $i->{destination});
      }
    }
  }
}

sub fetch {
  my $dest = shift();

  my $target = _crud->new("https://eprint.iacr.org/complete/")
                    ->get()->content();
  
  my @store;
  my $parsed = _parser
    ->new()
    ->handler(qr(^<dt>),      
              sub { my ($l, $a, $s) = @_; 
                    $s->{in} = 1;
                   })
    ->handler(qr(^<a\s+href=), 
              sub { my ($l, $a, $s) = @_; 
                    if ($s->{in}) {
                      if ($l =~ m!^<a\s+href=\"(/\d+/\d+)\">!x) {
                        $s->{link} = $1;
                        if ($l =~ m/\.pdf/xi) { $s->{pdf} = 1 }
                        if ($l =~ m/\.ps/xi) { $s->{ps} = 1 }
                      }
                    }
                  })
    ->handler(qr(^<dd><b>),
                 sub { my ($l, $a, $s) = @_; 
                       if ($l =~ m!<b>((\w+|\s+)+)</b>!xi) {
                         my $title = $1;
                         $title =~ s/\s+//g;
                         $title =~ s/\W+//g;
                         $s->{title} = $title;
                       }
                     })
    ->handler(qr(^<dd><em>),
              sub { my ($l, $a, $s) = @_; 
                    push(@$a, 
                         { link => $s->{link},
                            title => $s->{title},
                            pdf => $s->{pdf},
                            ps => $s->{ps} });
  
                    $s->{in} = 0; 
                    $s->{link} = "";
                    $s->{pdf} = 0;
                    $s->{ps} = 0;
                   })
    ->parse($target, \@store);

  foreach my $h (@store) {
    iacr($h, "https://eprint.iacr.org", $dest)
  }
}

sub usage {
  printf("Usage: %s mirror_directory\n", $0);
  exit(1);
}

if ($ARGV[0]) {
  fetch($ARGV[0]);
}
else {
  usage();
}
