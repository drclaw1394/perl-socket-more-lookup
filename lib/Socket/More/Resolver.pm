package Socket::More::Resolver;
use v5.36;
no warnings "experimental";

use constant::more DEBUG=>0;

use constant::more qw<CMD_GAI=0   CMD_GNI   CMD_SPAWN   CMD_KILL>;
use constant::more qw<WORKER_ID=0 WORKER_READ   WORKER_WRITE  WORKER_CREAD WORKER_CWRITE WORKER_QUEUE  WORKER_BUSY>;
use constant::more qw<REQ_CMD=0   REQ_ID  REQ_DATA  REQ_CB  REQ_WORKER>;

use Fcntl;

my $gai_data_pack="l> l> l> l> l>/A* l>/A*";

#REQID  and as above
#
my $gai_pack="($gai_data_pack)*";



sub results_available;
sub process_results;
sub getaddrinfo;

my $i=0;    # Sequential ID of requests

my $in_flight=0;

#my %reqs;   # Outstanding requests

my %pool;           # workers stored by pid
my @pool_free;      # pids (keys) of workers we can use
my $pool_max=4;


my @pairs;        # file handles for parent/child pipes
                  # preallocated with first import of this module

my $template_pid;

our $Shared;

my %fd_worker_map;




sub import {
  # options include 
  #   pool size
  #   preallocate
  #
  my $_p=shift;
  my %options=@_;
  
  unless($options{no_export}){
    # Roll our own exporter for low memory and to preallocate pipes
    # NEED TO WORK WITH EXPORT LEVEL INSTEAD OF SIMPLY CALLER
    my $package=caller $Exporter::ExportLevel;
    Socket::More::Resolver::DEBUG and say "CALLER IS $package";
    no strict "refs";

    #
    *{$package."::getaddrinfo"}=\&getaddrinfo;
    *{$package."::getnameinfo"}=\&getnameinfo;
    *{$package."::close_pool"}=\&close_pool;
  }
  
  # Don't generate pairs if they already exist
  return if @pairs;

  $pool_max=($options{max_workers}//4);

  #pre allocate enough pipes for full pool
  for(1..$pool_max){
    pipe my $c_read, my $p_write;
    pipe my $p_read, my $c_write;
    fcntl $c_read, F_SETFD, 0;  #Make sure we clear CLOSEXEC
    fcntl $c_write, F_SETFD,0;

    push @pairs,[0, $p_read, $p_write, $c_read, $c_write, [], 0]; 
  }

  
  # Create the template process here. This is the first worker
  #Need to bootstrap/ create the first worker, which is used as a template
  DEBUG and say STDERR "Create worker: Bootrapping  first/template worker"; 
  spawn_template();

  # Prefork
  if(1 or $options{prefork}){ 
    for(1..($pool_max-1)){
        unshift $pairs[0][WORKER_QUEUE]->@*, [CMD_SPAWN, $i++, $_];
        $in_flight++;
    }
  }


  1; 
}





#If used as a module, setup the process pool

#getaddrinfo Request
#REQID FLAGS FAMILY TYPE PROTOCOL HOST PORT 

#getaddrinfo response
#FLAG/ERROR FAMILY TYPE PROTOCOL ADDR CANONNNAME 
#

# Return undef when no worker available.
#   If under limit, a new worker is spawned for next run
# Return the worker struct to use otherwise
# 
sub _get_worker{

    my $worker;
    my $fallback;
    my $unspawned;
    my $index;
    my $busy_count=0;
    state $robin=1;
    for(1..$#pairs){
      $index=$_;
      $worker=$pairs[$index];
      if($worker->[WORKER_BUSY]){
          if($worker->[WORKER_ID]){
            $busy_count++;
            # Fully spawned an working on a request
          }
          else {
            # half spawned, this has at least 1 message
            # if all other workers are busy we use the first one of these we come accros
            #say "found using $index as fallback";
            $fallback//=$index;
          }
      }
      else {
        # Not busy
        #
        if($worker->[WORKER_ID]){
          # THIS IS THE WORKER WE WANT
          #say "found non busy worker";
          return $worker;
        }
        else{
          # Not spawned.  Use first one we come accross if we need to spawn
          #say "found using $index as unspawned";
          $unspawned//=$index;
        }
      }
    }

    #  Use the about to be spawned worker
    return $pairs[$fallback] if defined $fallback;

    # Here we actaully need to spawn a worker
    
    my $template_worker=spawn_template(); #ensure template exists
  
    if($busy_count < (@pairs-1)){
      
      #say "Busy count  less...Spawning";
      unshift $template_worker->[WORKER_QUEUE]->@*, [CMD_SPAWN, $i++, $unspawned];
      $index=$unspawned;
      $in_flight++;
    }
    else{
      #say "Busy count greater or equal too worker count";
      $index=$robin++;
      $robin=1 if $robin >=@pairs;
    }

    #say "worker index: $index";    
    $pairs[$index][WORKER_BUSY]=1;
    $pairs[$index];

}


# Serialize messages to worker from queue
sub pool_next{

  # handle returns first .. TODO: This is only if no event system is being used
  results_available unless $Shared;

  for(@pairs){
    DEBUG and say "POOL next for ".$_->[WORKER_ID]." busy: $_->[WORKER_BUSY], queue; $_->[WORKER_QUEUE]";
    my $ofd;
    # only process worker is initialized  not busy and  have something to process
    next unless $_->[WORKER_ID];
    next if $_->[WORKER_BUSY];
    next unless $_->[WORKER_QUEUE]->@*;

    $_->[WORKER_BUSY]=1;

    #my $req=shift $_->[WORKER_QUEUE]->@*;
    my $req=$_->[WORKER_QUEUE][0];
    $req->[REQ_WORKER]=$_->[WORKER_ID];
    
    #$reqs{$req->[REQ_ID]}=$req; #Add to outstanding


    # Header
    my $out=pack "l> l>", $req->[REQ_CMD], $req->[REQ_ID];

    # Body
    if($req->[REQ_CMD]==CMD_SPAWN){
        # Write to template process
        DEBUG and say ">> SENDING CMD_SPWAN TO WORKER: $req->[REQ_WORKER]";
        my $windex=$req->[2];
        my $cread=fileno $pairs[$windex][WORKER_CREAD];
        my $cwrite=fileno $pairs[$windex][WORKER_CWRITE];

        $out.=pack("l> l>", $cread, $cwrite);
        $ofd=$pairs[0][WORKER_WRITE];
    }
    elsif($req->[REQ_CMD]==CMD_GAI) {
      # getaddrinfo request
      DEBUG and say ">> SENDING CMD_GAI TO WORKER: $req->[REQ_WORKER]";
      if(ref $req->[REQ_DATA] eq "ARRAY"){
        $out.=pack $gai_pack, $req->[REQ_DATA]->@*;
      }
      else {
        # assume a hash
        for($req->[REQ_DATA]){
          $out.=pack $gai_pack, $_->{flags}//0, $_->{family}//0, $_->{socktype}//0, $_->{protocol}//0, $_->{host}, $_->{port};
        }
      }

      $ofd=$_->[WORKER_WRITE];
    }
    elsif($req->[REQ_CMD]==CMD_GNI){
      DEBUG and say ">> SENDING CMD_GNI TO WORKER: $req->[REQ_WORKER]";
      $out.=pack "l>/A* l>", $req->[REQ_DATA]->@*;
      $ofd=$_->[WORKER_WRITE];

    }
    elsif($req->[REQ_CMD]== CMD_KILL){
      DEBUG and say ">> Sending CMD_KILL to worker: $req->[REQ_WORKER]";
      $ofd=$_->[WORKER_WRITE];
    }
    else {
      die "UNkown command in pool_next";
    }

    DEBUG and say ">> WRITING WITH FD $ofd";
    syswrite $ofd, unpack("H*", $out)."\n"; # bypass buffering

  }
}


# Accepts either the worker struct (array) ref or the
# file descriptor of the worker read (parent) end
sub process_results{
  my $fd_or_struct=shift;
  my $worker;
  if(ref $fd_or_struct){
    $worker=$fd_or_struct;
  }
  else{
    $worker=$fd_worker_map{$fd_or_struct};
  }
  say "PROCESS RESULTS";
  #Check which worker is ready to read.
  # Read the result
  #For now we wait.
  my $r=$worker->[WORKER_READ];
  local $_=<$r>;
    chomp;
    my $bin=pack "H*", $_;

    my ($cmd, $id)=unpack "l> l>", $bin;
    $bin=substr $bin, 8;  #two lots of shorts

    # Remove from the outstanding table
    my $entry=shift $worker->[WORKER_QUEUE]->@*;
    $in_flight--;
    #my $entry=delete $reqs{$id};
    
    # Mark the returning worker as not busy
    #
    #$pool{$entry->[REQ_WORKER]}[WORKER_BUSY]=0;
    $worker->[WORKER_BUSY]=0;

    if($cmd==CMD_GAI){
      DEBUG and say "<< GAI return from worker $entry->[REQ_WORKER]";
      my @res=unpack $gai_pack, $bin;
      if($entry and $entry->[REQ_CB]){
        my @list;
        for my( $error, $family, $type, $protocol, $addr, $canonname)(@res){
          #say "$entry->[REQ_DATA]";
          if(ref($entry->[REQ_DATA]) eq "ARRAY"){
            push @list, [$error,$family,$type,$protocol, $addr, $canonname]; 
          }
          else {
            push @list, {family=>$family, socktype=>$type, protocol=>$protocol, addr=>$addr, canonname=>$canonname};
          }
        }
        $entry->[REQ_CB](\@list);
      }


    }
    elsif($cmd==CMD_GNI){
      DEBUG and say "<< GNI return from worker $entry->[REQ_WORKER]";
      my ($error, $host, $port)=unpack "l> l>/A* l>/A*", $bin;
      if($entry and $entry->[REQ_CB]){
          $entry->[REQ_CB]([$error, $host, $port]);
      }

    }
    elsif($cmd==CMD_SPAWN){
      # response from template fork. Add the worker to the pool
      # 
      my $pid=unpack "l>", $bin;
      my $index=$entry->[2];  #
      unshift @pool_free, $index;
      my $worker=$pairs[$index];
      $worker->[WORKER_ID]=$pid;
      # turn on the worker by clearing the busy flag
      $worker->[WORKER_BUSY]=0;
      $fd_worker_map{fileno $worker->[WORKER_READ]}=$worker;

      DEBUG and say "<< SPAWN RETURN FROM TEMPLATE $entry->[REQ_WORKER]: new worker $pid";
    }
    elsif($cmd == CMD_KILL){
      my $id=$entry->[REQ_WORKER];
      DEBUG and say "<< KILL RETURN FROM WORKER: $id : $worker->[WORKER_ID]";
      #delete $pool{$id};
      @pool_free=grep $pairs[$_]->[WORKER_ID] != $id, @pool_free;
    }

    pool_next if $Shared;
}

sub results_available {
  my $timeout=shift//0;
  DEBUG and say "CHECKING IF ReSULTS AVAILABLE";
  # Check if any workers are ready to talk 
  my $bits="";
  for(@pairs){
    vec($bits,  fileno($_->[WORKER_READ]),1)=1 if $_->[WORKER_ID];
  }

  my $count=select $bits, undef, undef, $timeout;

  if($count>0){
    #say "COUNT: $count";
    for(@pairs){
      if($_->[WORKER_ID] and vec($bits, fileno($_->[WORKER_READ]), 1)){
        process_results $_;
      }
    }
  }
  $count;
}

sub getaddrinfo{
  say "";
  say "GETADDRINFO====";
  if( @_ !=0){


    my ($host, $port, $hints, $on_result, $on_error)=@_;

    # Ensure hints is array ref
    #die "hints must be array" unless ref($hints) eq "ARRAY";
    # Ensure sane values for transmit
    my $ref=[];
    if(ref($hints) eq "ARRAY"){
      push @$hints, $host, $port;
    }
    else {
      $hints->{host}=$host;
      $hints->{port}=$port;
    }


    # add the request to the queue and to outstanding table
    my $worker=_get_worker;
    my $req=[CMD_GAI, $i++, $hints, $on_result, $worker->[WORKER_ID]];
    push $worker->[WORKER_QUEUE]->@*, $req;
    $in_flight++;
  }

  pool_next;
  #return true if outstanding requests
  $in_flight;
}

sub getnameinfo{
  my ($addr, $flags, $on_result)=@_;
    my $worker=_get_worker;
    my $req=[CMD_GNI, $i++, [$addr, $flags], $on_result, $worker->[WORKER_ID]];
    push $worker->[WORKER_QUEUE]->@*, $req;
    $in_flight++;
    pool_next;
    #scalar %reqs;
    $in_flight;
}

sub close_pool {

  my @indexes=1..$#pairs;
  push @indexes, 0;

  #generate messages to close
  for(@indexes){
    my $worker=$pairs[$_];
    my $req=[CMD_KILL, $i++, [], undef, $_];
    push $worker->[WORKER_QUEUE]->@*, $req;
    $in_flight++;
    pool_next;
  }
}

# return the parent side reading filehandles. This is what is needed for event loops
sub to_watch {
    map $_->[WORKER_READ], @pairs;
}

sub monitor_workers {
  use POSIX ":sys_wait_h"; 
      # See if any children have exited or been killed.
      # Reap them
      # Re spawn them
      my $pid;
      do{ 
        $pid=waitpid -1, WNOHANG;
        if($pid>0){
          # Found a dead worker Respawn, 
          # Scan the pending requests previously allocated
          my $dead=$fd_worker_map{$pid};
          
          # remove from pool
          #delete $pool{$pid};

          # TODO: what if it was the template process?           
          $dead

        }
      } while ($pid>0);
}

sub cleanup_worker {
  #remove from pool

  # Remove from free

  # Work with outstanding messages
}

sub spawn_worker {
  # Iterate through slots to find a defunct worker
  
  # if the templates process is defunct spawn it as a special case

}

sub spawn_template {
  # This should only be called when modules is first loaded, or when an
  # external force has killed the template process
  my $worker=$pairs[0];
  return $worker if $worker->[WORKER_ID];

  my $pid=fork; 
  if($pid){
    # parent
    #
    $worker->[WORKER_ID]=$pid;
    #$pool{$pid}=$worker;
    $fd_worker_map{fileno $worker->[WORKER_READ]}=$worker;
    push @pool_free, 0;
    $worker;

  }
  else {
    # child
    # exec an tell the process which fileno we want to communicate on
    close $worker->[WORKER_READ];
    close $worker->[WORKER_WRITE];
    my @ins=map {fileno $_->[WORKER_CREAD]} @pairs;  # Child read end
    my @outs=map {fileno $_->[WORKER_CWRITE]} @pairs; # Child write end
    DEBUG and say STDERR "Create worker: exec with ins: @ins";
    DEBUG and say STDERR "Create worker: exec with outs: @outs";
    my $file=__FILE__; 
    $file=~s|\.pm|/Worker.pm|;
    local $"=",";
    exec $^X, $file, "--in", "@ins", "--out", "@outs";
  }
}
1;
