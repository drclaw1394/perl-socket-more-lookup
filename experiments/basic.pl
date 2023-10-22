use v5.36;
#use Data::Dumper;
use Socket::More::Resolver;

for(1..10){
  say "";
  say "user loop";
  use Data::Dumper;
  getaddrinfo("www.google.com.au", 80, {}, sub {say "===USER CALLBACK==="; return; say Dumper $_[0]});
}
sleep 1 while getaddrinfo();
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
