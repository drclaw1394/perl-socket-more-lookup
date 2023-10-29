use v5.36;
use Mojo::IOLoop;
use Socket::More::Resolver::Mojo::IOLoop {prefork=>1, max_workers=>5};


#$loop->add($Socket::More::Resolver::Shared);

Mojo::IOLoop->recurring(0.4, sub {
  getaddrinfo("rmbp.local", 80, {}, sub {
    #use Data::Dumper;

    #say Dumper @_;
    say "callback";
  })
  
});

say "sTARTING LOOP";
Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
