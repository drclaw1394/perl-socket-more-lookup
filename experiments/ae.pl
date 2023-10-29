use v5.36;
use AnyEvent;
use Socket::More::Resolver::AE {prefork=>1, max_workers=>10};
use Data::Dumper;

my $timer;
my $sub=sub { 
#say Dumper @_
say "CALLBACK-->";
};
$timer=AE::timer 0, 0.2, sub {
  getaddrinfo("rmbp.local", 80, {}, $sub);
};

my $cv=AE::cv;

$cv->recv;

