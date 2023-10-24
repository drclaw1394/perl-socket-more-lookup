use v5.36;
use IO::Async::Loop;
use IO::Async::Timer::Periodic;

use Socket::More::Resolver;

my $loop=IO::Async::Loop->new;


$loop->add($Socket::More::Resolver::Shared);

my $timer=IO::Async::Timer::Periodic->new(interval=>0.01, on_tick=>sub {

  getaddrinfo("rmbp.local", 80, {}, sub {
    use Data::Dumper;
    say Dumper @_;
  })

});


$timer->start;
$loop->add($timer);

$loop->run;
