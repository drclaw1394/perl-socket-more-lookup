use v5.36;
use AnyEvent;
#use Socket::More::Resolver::AE;
use Socket::More::Resolver;
use Data::Dumper;

my $timer;
my $addr;
my $sub=sub { say Dumper @_};
$timer=AE::timer 0, 0.01, sub {
  getaddrinfo("rmbp.local", 80, {}, $sub);
};

my $cv=AE::cv;

$cv->recv;

