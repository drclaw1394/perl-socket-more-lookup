# Before 'make install' is performed this script should be runnable with
# 'make test'. After 'make install' it should work as 'perl Socket-More-Lookup.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use warnings;

use Test::More;
BEGIN { use_ok('Socket::More::Lookup') };

use Socket;
use Socket::More::Lookup;
use Socket::More::Constants;

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

{
  # getaddrinfo
  my $res=Socket::More::Lookup::getaddrinfo("www.google.com", "80", undef, my @results);
  ok $res, "Return ok";
  die gai_strerror $! unless $res;
  ok @results>0, "Results ok";
  for(@results){
    #for my ($k, $v)($_->%*){
      #say STDERR "$k=>$v";
      #}
  }
}

{
  # get name info
      my $name=pack_sockaddr_in(1234, pack "C4", 127,0,0,1);
      my $err=Socket::More::Lookup::getnameinfo($name, my $ip="", my $port="", NI_NUMERICHOST|NI_NUMERICSERV);
}
done_testing;
