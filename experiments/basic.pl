use v5.36;
use Data::Dumper;
use Time::HiRes qw<sleep>;
use Socket::More::Resolver {prefork=>1, max_workers=>10};

my $addr;
for(1..1000){
  say "";
  say "user loop";
  getaddrinfo("rmbp.local", 80, {}, sub {
    say "===USER CALLBACK===";
    #say Dumper $_[0]
    $addr=$_[0][0]{addr};
  });
}

say "OIJSDF";
while(getaddrinfo){
  sleep 0.1;
}
