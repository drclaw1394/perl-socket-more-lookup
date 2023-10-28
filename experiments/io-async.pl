use v5.36;
use IO::Async::Loop;
use IO::Async::Timer::Periodic;

use Socket::More::Resolver::IO::Async ;#prefork=>1;

my $loop=IO::Async::Loop->new;


$loop->add($Socket::More::Resolver::Shared);

my $timer=IO::Async::Timer::Periodic->new(interval=>1, on_tick=>sub {

  getaddrinfo("rmbp.local", "80", {}, sub {
    #use Data::Dumper;
    #say Dumper @_;
    say "CALLBACK";
  })

});


$timer->start;
$loop->add($timer);

$loop->run;
