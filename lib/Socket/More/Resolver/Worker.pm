package Socket::More::Resolver::Worker;
unless(caller){
  my $gai_data_pack="l> l> l> l> l>/A* l>/A*";
  my $gai_pack="($gai_data_pack)*";

  package main;
  use constant::more DEBUG=>1;
  use constant::more qw<CMD_GAI=0 CMD_GNI CMD_SPAWN CMD_KILL>;
  use v5.36;

  # process any command line arguments for input and output FDs
  my $run=1;
  my @in_fds;
  my @out_fds;
  my $use_core;#=1;#=1;
  #say "Processing ARGV";
  while(@ARGV){
    local $_=shift;  
    if(/--in/){
        @in_fds=split ",", shift;
        next;
    }
    if(/--out/){
        @out_fds=split ",", shift;
        next;
    }
  }
  
  DEBUG and say STDERR "TEMPLATE: ins: @in_fds";
  DEBUG and say STDERR "TEMPLATE: outs: @out_fds";

  # Pipes back to the API
  #
  open my $in,  "<&=$in_fds[0]" or die $!;
  open my $out, ">&=$out_fds[0]" or die $!;
  #$out->autoflush;

  #Simply loop over inputs and outputs
  DEBUG and say "Worker waiting for line ...";
  while(<$in>){
    DEBUG and say "Worker got line...";
    #parse
    # Host, port, hints
    chomp;  

    my $bin=pack "H*", $_;
    my ($cmd, $req_id)=unpack "l> l>", $bin;
    $bin=substr $bin, 8;

    DEBUG and say "WORKER $$ REQUEST,  ID: $req_id";

    my $return_out=pack "l> l>", $cmd, $req_id;
    if($cmd == CMD_SPAWN){
      #Fork from me. Presumably the template
      my $pid=fork;
      if($pid){
        #Parent
        # return message back to API with PID of offspring 
        DEBUG and say "FORKED WORKER... in parent child is $pid";
        $return_out.=pack "l>", $pid;
      }
      else {
        #child.
        DEBUG and say "FORKED WORKER... child with fds";
        my ($in_fd, $out_fd)=unpack "l> l>", $bin;
        close $in;
        close $out;
        
        DEBUG and say "infd $in_fd, out_fd $out_fd";
        open $in,  "<&=$in_fd" or die $!;
        open $out, ">&=$out_fd" or die $!;

        next; #Do not respond.
      }

    }
    elsif($cmd== CMD_GAI){
      #Assume a request
      my @e =unpack $gai_pack, $bin;
      #say "inputs: @e";
      my @results;
      my $port=pop @e;
      my $host=pop @e;
      DEBUG and say "WORKER $$ PROCESSIG GAI REQUEST, id: $req_id";
      my $rc;


      if($use_core){
        require Socket;
        my %hints=@e;
        ($rc,@results)=Socket::getaddrinfo($host,$port, \%hints);
        if($rc!=0 and @results ==0){
          $results[0]=[$rc, -1, -1, -1, "", ""];
        }
        for(@results){
          #$_->[0]= $rc;
          my $a=[$rc, $_->{hints}, $_->{family}, $_->{socktype}, $_->{protocol}, $_->{addr}, $_->{cannonname}];
          $return_out.=pack($gai_data_pack, $a);
        }
      }
      else {
        require Socket::More::Lookup;
        $rc=Socket::More::Lookup::getaddrinfo($host, $port, \@e, \@results);
        #$rc=1;
        #@results=();
        unless (defined $rc){
          $results[0]=[$!, -1, -1, -1, "", ""];
        }

        for(@results){
          $_->[0]= 0;
          $return_out.=pack($gai_data_pack, @$_);
        }
      }
    }

    elsif($cmd==CMD_GNI){
      DEBUG and say "WORKER $$ PROCESSIG GNI REQUEST, id: $req_id";
      my @e=unpack "l>/A* l>", $bin;
      if($use_core){
        require Socket;
        my($rc, $host, $service)=Socket::getnameinfo(@e);
        $return_out.=pack "l> l>/A* l>/A*",$rc, $host, $service;
      }
      else {
        require Socket::More::Lookup;
        my $rc=Socket::More::Lookup::getnameinfo($e[0],my $host="", my $service="", $e[1]);
        $return_out.=pack "l> l>/A* l>/A*",$rc, $host, $service;
      }
    }

    elsif($cmd==CMD_KILL){
      # worker needs to exit
      # 
      $run=undef;
    }

    else {
      die "Unkown command";
    }

    DEBUG and say "** BEFORE WORKER WRITE $$";
    syswrite $out, unpack("H*", $return_out)."\n" or say $!;
    DEBUG and say "** AFTER WORKER WRITE $$";

    last unless $run;
  }

  DEBUG and say "** EXITING WORKER $$";
}

1;
