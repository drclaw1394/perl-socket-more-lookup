use strict;
use warnings;

use Test::More;
BEGIN { use_ok('Socket::More::Lookup') };

use Socket::More::Lookup;
use Socket::More::Constants;

{
  # getaddrinfo
  my $res=getaddrinfo("www.google.com", "80", undef, my @results);
  ok $res, "Return ok";
  die gai_strerror $! unless $res;
  ok @results>0, "Results ok";

  # Expect an array of hashes for undef input
  ok ref($results[0]) eq "HASH", "Expected hash result";

  for(@results){
    #for my ($k, $v)($_->%*){
      #say STDERR "$k=>$v";
      #}
  }
}
{
  # getaddrinfo
  my $res=getaddrinfo("rmbp.local", "80", [NI_NUMERICSERV|NI_NUMERICHOST, AF_INET, SOCK_STREAM], my @results);
  ok $res, "Return ok";
  die gai_strerror $! unless $res;
  ok @results>0, "Results ok";

  use Data::Dumper;

  say STDERR Dumper \@results;
  # Expect an array of hashes for undef input
  ok ref($results[0]) eq "ARRAY", "Expected array result";

  for(@results){
    #for my ($k, $v)($_->%*){
      #say STDERR "$k=>$v";
      #}
  }
}

{
  # get name info
  #
    require  Socket;
    my $name=Socket::pack_sockaddr_in(1234, pack "C4", 127,0,0,1);
    my $err=getnameinfo($name, my $ip="", my $port="", NI_NUMERICHOST|NI_NUMERICSERV);
}

done_testing;
