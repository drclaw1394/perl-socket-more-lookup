use v5.36;
use AnyEvent;
use Socket::More::Resolver {prefork=>0, max_workers=>5};
use Socket::More::Lookup qw<gai_strerror>;
use Data::Dumper;

my $timer;
my $sub=sub { 
  #say Dumper @_
  say "CALLBACK-->";
};

$timer=AE::timer 0, 0.1, sub {
  getaddrinfo("rmbp2.local", 80, {}, $sub, sub {
    say "GOT ERROR: $_[0]";
    say gai_strerror($_[0]);
  });
};
my $cv=AE::cv;
$cv->recv;
