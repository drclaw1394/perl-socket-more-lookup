package Socket::More::Resolver;
use v5.36;

use Socket::More::Lookup();

#If used as a module, setup the process pool

#getaddrinfo Request
#REQID FLAGS FAMILY TYPE PROTOCOL HOST PORT 

#getaddrinfo response
#FLAG/ERROR FAMILY TYPE PROTOCOL ADDR CANONNNAME 
use constant::more qw<WORKER_ID=0 WORKER_READ WORKER_WRITE>;
use constant::more qw<REQ_ID=0 REQ_DATA REQ_CB REQ_WORKER>;

my $gai_data_pack="N N N N N/A* N/A*";

#REQID  and as above
#
my $gai_pack="N ($gai_data_pack)*";

use Export::These qw<getaddrinfo>;
my $i=0;
my %reqs;

my %pool;
my @pool_free;
my $pool_max=2;
my @pool_queue;

my $p;
sub results_available;

sub _create_worker {
#say "CREATING WORKER";
  return if keys(%pool) > $pool_max;
  my $file=__FILE__; 
  #say $file;
  my $worker;
  # Open pipes
  #
  $^F=10; #HACK... prob need to use fcntl to set clear close_exe flag as we don't know the
          # the max FD yet
  pipe my $child_read, my $parent_write;
  pipe my $parent_read, my $child_write;

  my $pid=fork; 

  if($pid){
    # parent
    #
    $worker=$pool{$pid}=[$pid, $parent_read, $parent_write];
    push @pool_free, $worker;
  }
  else {
    # exec an tell the process which fileno we want to communicate on
    close $parent_write;
    close $parent_read;
    exec $^X, $file, "--in", fileno($child_read), "--out", fileno($child_write);
  }
  #$worker;
}

sub pool_next{

  # Do we have any work to do?
  return unless @pool_queue;

  my $worker;
  _create_worker unless @pool_free;

  $worker=shift @pool_free;
  # do we have a worker free?
  return unless $worker;

  #say "Pool next ok";

  my $req=shift @pool_queue;
  $req->[REQ_WORKER]=$worker->[WORKER_ID];
  #my ($parent_read, $parent_write)=@$worker;
  my $res=unpack "H*", pack $gai_pack, $req->[REQ_ID], $req->[REQ_DATA]->@*;
  syswrite $worker->[WORKER_WRITE], $res."\n"; # bypass buffering
  results_available;
}



sub process_results{
  my $worker=shift;
  #Check which worker is ready to read.
  # Read the result
  #For now we wait.
  my $r=$worker->[WORKER_READ];
  my $incomming=<$r>;
  chomp $incomming;
  my ($id, @res)=unpack $gai_pack, pack "H*", $incomming;
  my $entry=delete $reqs{$id};
  if($entry and $entry->[2]){
    my @list;
    for my( $error, $family, $type, $protocol, $addr, $canonname)(@res){
      #say "addr is $addr";
      if(ref($entry->[REQ_DATA]) eq "ARRAY"){
        push @list, [$error,$family,$type,$protocol, $addr, $canonname]; 
      }
      else {
        push @list, {family=>$family, type=>$type, protocol=>$protocol, addr=>$addr, canonname=>$canonname};
      }
    }
    $entry->[REQ_CB](\@list);
  }

  # Add the worker back to pool
  push @pool_free, $pool{$entry->[REQ_WORKER]};
  # restart 
  #__SUB__->();
}

sub results_available {
#say "CHECKING IF ReSULTS AVAILABLE";
  # Check if any workers are ready to talk 
  my $bits="";
  for(values %pool){
    vec($bits,  fileno($_->[WORKER_READ]),1)=1;
  }

  my $count=select $bits, undef, undef, 0;
  if($count>0){
    #say "COUNT: $count";
    for(values %pool){
      if(vec($bits, fileno($_->[WORKER_READ]),1)){
        # ready to read
        #say "READY TO PROCESS";
        process_results $_;
      }
    }
  }
}

sub getaddrinfo{
  if( @_ ==0){
    return results_available;
  }

  my ($host,$port,$hints,$cb)=@_;
  
  # Ensure hints is array ref
  #die "hints must be array" unless ref($hints) eq "ARRAY";
  
  # Ensure sane values for transmit
  my $ref=[];
  if(ref($hints) eq "ARRAY"){
    $ref->[0]=$hints->[0]//0;
    $ref->[1]=$hints->[1]//0;
    $ref->[2]=$hints->[2]//0;
    $ref->[3]=$hints->[3]//0;
    $ref->[4]=$host;
    $ref->[5]=$port;
  }
  else {
    $ref->[0]=$hints->{flags}//0;
    $ref->[1]=$hints->{family}//0;
    $ref->[2]=$hints->{type}//0;
    $ref->[3]=$hints->{protocol}//0;
    $ref->[4]=$host;
    $ref->[5]=$port;

  }

  #@$hints=6;

  my @req=($i++, $ref, $cb);
  push @pool_queue, $reqs{$req[REQ_ID]}=\@req;
  pool_next();
}






# If use as a script, we are a worker
#
unless(caller){
  package main;
  use v5.36;

  # process any command line arguments for input and output FDs

  my $in_fd;
  my $out_fd;
  #say "Processing ARGV";
  while(@ARGV){
    local $_=shift;  
    if(/--in/){
        $in_fd=shift;
        next;
    }
    if(/--out/){
        $out_fd=shift;
        next;
    }
  }

  $in_fd=fileno(STDIN) unless defined $in_fd;
  $out_fd=fileno(STDOUT) unless defined $out_fd;

  #open filehandles
  #say "Child resolver with $in_fd, $out_fd";
  #open my $another, "<", __FILE__;
  #say fileno $another;
  open my $in,  "<&=$in_fd" or die $!;
  open my $out, ">&=$out_fd" or die $!;

  require Socket::More::Lookup;
  #Simply loop over inputs and outputs
  #say "Processing in";
  while(<$in>){
    #say "line...";
    #parse
    # Host, port, hints
    chomp;  
    my ($req_id, @e)=unpack $gai_pack, pack "H*", $_;
    #say "inputs: @e";
    my @results;
    my $port=pop @e;
    my $host=pop @e;

    my $rc=Socket::More::Lookup::getaddrinfo $host, $port, \@e, @results;
    #say "Result code :$rc ";
    
    if($rc!=0 and @results ==0){
      $results[0]=[$rc, -1, -1, -1, "", ""];
    }
    my $data=pack "N", $req_id;
    for(@results){
      $_->[0]= $rc;
      $data.=pack($gai_data_pack, @$_);
    }
    syswrite $out, unpack("H*", $data)."\n";
  }
}

1;
