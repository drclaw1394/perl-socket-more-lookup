use v5.36;
use Data::Dumper;
use Socket::More::Resolver;

my $addr;
for(1..10){
  say "";
  say "user loop";
  getaddrinfo("www.google.com.au", 80, {}, sub {say "===USER CALLBACK===";
    #say Dumper $_[0]
    $addr=$_[0][0]{addr};
  });
}
sleep 1 while getaddrinfo();
getnameinfo($addr, 0, sub { say "GOT RESULTS FOR ADDRESS"; say Dumper $_[0]});
####################
# for(1..4){       #
#   getaddrinfo(); #
#   sleep 1;       #
# }                #
####################
say "";
say "";
say "";
say "";
say "ABOUT TO CLOSE POOL";
close_pool;
sleep 1 while getaddrinfo();
######################
# for(1..6){         #
#   say "LAST LOOP"; #
#   getaddrinfo();   #
#   sleep 1;         #
# }                  #
######################
#sleep 2 while getaddrinfo();
