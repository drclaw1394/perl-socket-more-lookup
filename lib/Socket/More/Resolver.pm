package Socket::More::Resolver;
use v5.36;
no warnings "experimental";

use Data::Dumper;
#TODO Test if Socket::More::Lookup is available
#otherwise we just use socket implementation?
use constant::more DEBUG=>1;
#
use Socket::More::Lookup();
my $gai_data_pack="s s s s s/A* s/A*";

#REQID  and as above
#
my $gai_pack="s ($gai_data_pack)*";


my $p;
sub results_available;
sub process_results;
sub getaddrinfo;
my $i=0;
my %reqs;

my %pool;           # workers stored by pid
my @pool_free;      # pids (keys) of workers we can use
my $pool_max=10;
my @pool_queue;     # requests are added here


my @pairs;        # file handles for parent/child pipes
                  # preallocated with first import of this module
my $template_pid;

sub import {

  # Roll our own exporter for low memory and to preallocate pipes
  my $package=caller;
  say "CALLER IS $package";
  no strict "refs";
  *{$package."::getaddrinfo"}=\&getaddrinfo;

  
  return if @pairs;
  $^F=100; #HACK... prob need to use fcntl to set clear close_exe flag as we don't know the
  #pre allocate enough pipes for full pool
  for(1..10){
    pipe my $c_read, my $p_write;
    pipe my $p_read, my $c_write;
    # TODO:  fctl to prevent close on exec
    push @pairs,[$p_read, $p_write, $c_read, $c_write]; 
  }

  # Create the template process here. This is the first worker
    #Need to bootstrap/ create the first worker, which is used as a template
    DEBUG and say STDERR "Create worker: Bootrapping  first/template worker"; 
    my $file=__FILE__; 
    #say $file;
    my $worker;
    # Open pipes
    #
    # the max FD yet
    #pipe my $child_read, my $parent_write;
    #pipe my $parent_read, my $child_write;
    my ($parent_read, $parent_write, $child_read, $child_write)=$pairs[0]->@*;
    my $pid=fork; 
    $template_pid=$pid;

    if($pid){
      # parent
      #
      $worker=$pool{$pid}=[$pid, $parent_read, $parent_write];
      push @pool_free, $pid;
      sleep 3;
    }
    else {
      # child
      # exec an tell the process which fileno we want to communicate on
      close $parent_write;
      close $parent_read;
      my @ins=map {fileno $_->[2]} @pairs;  # Child read end
      my @outs=map {fileno $_->[3]} @pairs; # Child write end
      DEBUG and say STDERR "Create worker: exec with ins: @ins";
      DEBUG and say STDERR "Create worker: exec with outs: @outs";

      local $"=",";
      exec $^X, $file, "--in", "@ins", "--out", "@outs";
    }
  1; 
}





#If used as a module, setup the process pool

#getaddrinfo Request
#REQID FLAGS FAMILY TYPE PROTOCOL HOST PORT 

#getaddrinfo response
#FLAG/ERROR FAMILY TYPE PROTOCOL ADDR CANONNNAME 
#
use constant::more qw<WORKER_ID=0 WORKER_READ WORKER_WRITE>;
use constant::more qw<REQ_ID=0 REQ_DATA REQ_CB REQ_WORKER>;
#use constant::more qw<PIPE_P2C_READ PIPE_P2C_WRITE
use constant::more DEBUG=>1;

# Return undef when no worker available.
#   If under limit, a new worker is spawned for next run
# Return the worker struct to use otherwise
# 
sub _get_worker{
  

    # Return undef if no free workers
    if(@pool_free){
      # Worker is available, so use it
      DEBUG and say STDERR "get worker:  pool has free";
      return $pool{shift @pool_free};
    }
    else {
      DEBUG and say STDERR "get worker:  pool has NO free";
      # No free workers, do we create another?
      if(keys(%pool) < $pool_max){
        DEBUG and say STDERR "get worker:  sending to spawn new worker";
        # yes
        my @req=(-1, scalar(keys %pool));
        unshift @pool_queue, \@req; #Push to the front of the queue
      }
        return;
    }

    ##########################################################################
    # # expect an immediate return                                           #
    # my $fh=$pairs[0][0];                                                   #
    # say "Waiting for line from template";                                  #
    # my $line=<$fh>;                                                        #
    # chomp $line;                                                           #
    #                                                                        #
    # my ($req, $pid)=unpack "ss", pack "H*",$line;                          #
    # say "GOT LINE FROM TEMPLATE: $line, req: $req, pid $pid";              #
    #                                                                        #
    # #Add the worker to the pool                                            #
    # my $size=keys %pool;                                                   #
    # my $worker=$pool{$pid}=[$pid, $pairs[$size-1][0], $pairs[$size-1][1]]; #
    # push @pool_free, $pid;                                                 #
    #                                                                        #
    # sleep 1;                                                               #
    ##########################################################################
    #$worker;
}

sub pool_next{

  my $worker=_get_worker;# unless @pool_free;
  if($worker){
    my $req=shift @pool_queue;
    $reqs{$req->[REQ_ID]}=$req; #Add to outstanding

    $req->[REQ_WORKER]=$worker->[WORKER_ID];
    #my ($parent_read, $parent_write)=@$worker;
    if($req->[REQ_ID]==-1){
        # Write to template process
        my $windex=$req->[1];
        my $cread=fileno $pairs[$windex][2];
        my $cwrite=fileno $pairs[$windex][3];

        syswrite $pairs[0][1], unpack("H*", pack "sss", -1, $cread, $cwrite)."\n";
    }
    else {
      my $res=unpack "H*", pack $gai_pack, $req->[REQ_ID], $req->[REQ_DATA]->@*;
      syswrite $worker->[WORKER_WRITE], $res."\n"; # bypass buffering
    }
  }
  # Might not have a worker, by we need to handle return data
  results_available;
}



sub process_results{
  my $worker=shift;
  #Check which worker is ready to read.
  # Read the result
  #For now we wait.
  say "Process results...."; 
  my $r=$worker->[WORKER_READ];
  my $incomming=<$r>;
  chomp $incomming;
  my $bin=pack "H*", $incomming;
  my $id=unpack "s",$bin;
  #my ($id, @res)=unpack $gai_pack, pack "H*", $incomming;

  # Remove from the outstanding table
  my $entry=delete $reqs{$id};
  say Dumper $entry;
  if($id>=0){
    my (undef, @res)=unpack $gai_pack, $bin;
    if($entry and $entry->[2]){
      my @list;
      for my( $error, $family, $type, $protocol, $addr, $canonname)(@res){
        say "addr is $addr";
        if(ref($entry->[REQ_DATA]) eq "ARRAY"){
          push @list, [$error,$family,$type,$protocol, $addr, $canonname]; 
        }
        else {
          push @list, {family=>$family, type=>$type, protocol=>$protocol, addr=>$addr, canonname=>$canonname};
        }
      }
      use Data::Dumper;
      say Dumper \@list;
      $entry->[REQ_CB](\@list);
    }

    # Add the worker back to pool
    push @pool_free, $entry->[REQ_WORKER];

    # Go again
    results_available;
  }
  elsif($id==-1){
    # response from template fork
    my (undef, $pid)=unpack "ss", $bin;
    
    say "RETURN FROM TEMPLATE: new worker $pid";
  }
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

  my ($host, $port, $hints, $cb)=@_;
  
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

  # add the request to the queue and to outstanding table
  my @req=($i++, $ref, $cb);
  push @pool_queue, \@req;


  # Attempt do dispatch
  pool_next();
}






# If use as a script, we are a worker
#
unless(caller){
  package main;
  use v5.36;
  use Data::Dumper;

  # process any command line arguments for input and output FDs

  my @in_fds;
  my @out_fds;
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
  
  1 and say STDERR "TEMPLATE: ins: @in_fds";
  1 and say STDERR "TEMPLATE: outs: @out_fds";

  open my $in,  "<&=$in_fds[0]" or die $!;
  open my $out, ">&=$out_fds[0]" or die $!;

  require Socket::More::Lookup;
  #Simply loop over inputs and outputs
  say "Worker waiting for line ...";
  while(<$in>){
    say "Worker got line...";
    #parse
    # Host, port, hints
    chomp;  
    my $bin=pack "H*", $_;
    my $req_id=unpack "s", $bin;
    say "WORKER REQUEST,  ID: $req_id";
    if($req_id == -1){
      #Fork from me. 
      my $pid=fork;
      if($pid){
        #Parent
        # return message include PID of child
        syswrite $out, unpack("H*", pack "ss", $req_id, $pid)."\n";
      }
      else {
        #child
        my (undef, $in_fd, $out_fd)=unpack "sss",$bin;
        close $in;
        close $out;
        say "infd $in_fd, out_fd $out_fd";
        open $in,  "<&=$in_fd" or die $!;
        open $out, ">&=$out_fd" or die $!;
      }

    }
    else{
      #Assume a request
      my @e =unpack $gai_pack, $bin;
      #say "inputs: @e";
      my @results;
      my $port=pop @e;
      my $host=pop @e;

      my $rc=Socket::More::Lookup::getaddrinfo $host, $port, \@e, @results;
      #say "Result code :$rc ";

      if($rc!=0 and @results ==0){
        $results[0]=[$rc, -1, -1, -1, "", ""];
      }
      my $data=pack "s", $req_id;
      for(@results){
        $_->[0]= $rc;
        $data.=pack($gai_data_pack, @$_);
      }
      say Dumper $data;
      syswrite $out, unpack("H*", $data)."\n";
    }
  }
}

1;
