use v5.36;
use AnyEvent;
use Socket::More::Resolver::AE;
use Socket::More::Resolver;
use Data::Dumper;

my $timer;
my $sub=sub { 
#say Dumper @_
say "CALLBACK-->";
};
$timer=AE::timer 0, 0.1, sub {
  getaddrinfo("rmbp23.local", 80, {}, $sub);
};

my $cv=AE::cv;

$cv->recv;

