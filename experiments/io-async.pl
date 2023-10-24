use v5.36;
use IO::Async::Loop;
use IO::Async::Timer::Periodic;
require Socket::More::Resolver;
my $loop=IO::Async::Loop->new;

Socket::More::Resolver->import;
#######################
# event_loop=>sub {   #
#     say "CALLBACK"; #
# };                  #
#######################
my $timer=IO::Async::Timer::Periodic->new(interval=>1, on_tick=>sub {
  getaddrinfo("rmbp.local", 80, {}, sub {
    use Data::Dumper;
    say Dumper @_;
  })
});

$timer->start;
$loop->add($timer);


#IO::Async::Handle->new(
#handle=>

$loop->run;
