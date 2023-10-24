use v5.36;
use Mojo::IOLoop;
use Socket::More::Resolver;



#$loop->add($Socket::More::Resolver::Shared);

Mojo::IOLoop->recurring(0.01, sub {
  getaddrinfo("rmbp.local", 80, {}, sub {
    use Data::Dumper;
    say Dumper @_;
  })
  
});

say "sTARTING LOOP";
Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
