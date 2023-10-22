package Socket::More::Resolver;
use v5.36;
no warnings "experimental";

use constant::more DEBUG=>1;

use constant::more qw<CMD_GAI=0 CMD_GNI CMD_SPAWN CMD_KILL>;
use constant::more qw<WORKER_ID=0 WORKER_READ WORKER_WRITE WORKER_QUEUE WORKER_BUSY>;
use constant::more qw<REQ_CMD=0 REQ_ID REQ_DATA REQ_CB REQ_WORKER>;

use Fcntl;

my $gai_data_pack="l> l> l> l> l>/A* l>/A*";

#REQID  and as above
#
my $gai_pack="($gai_data_pack)*";

my $k=0;    # Number of Workers in 'flight' or active
            #

my $p=0;    # Worker index on return of spawn?

sub results_available;
sub process_results;
sub getaddrinfo;

my $i=0;    # Sequential ID of requests

my %reqs;   # Outstanding requests

my %pool;           # workers stored by pid
my @pool_free;      # pids (keys) of workers we can use
my $pool_max=5;
my $busy_count=0;


my @pairs;        # file handles for parent/child pipes
                  # preallocated with first import of this module

my $template_pid;
my $template_worker;

my $event_data;
my $has_event_loop;
my %fd_worker_map;

sub import {
  # options include 
  #   pool size
  #   preallocate
  #
  # Roll our own exporter for low memory and to preallocate pipes
  my $package=caller;
  Socket::More::Resolver::DEBUG and say "CALLER IS $package";
  no strict "refs";

  #TODO: NEED TO WORK WITH EXPORT LEVEL INSTEAD OF SIMPLY CALLER
  #
  *{$package."::getaddrinfo"}=\&getaddrinfo;
  *{$package."::getnameinfo"}=\&getnameinfo;
  *{$package."::close_pool"}=\&close_pool;


  
  # Don't generate pairs if they already exist
  return if @pairs;

  # Detect event system
  #pre allocate enough pipes for full pool
  for(1..$pool_max){
    pipe my $c_read, my $p_write;
    pipe my $p_read, my $c_write;
    fcntl $c_read, F_SETFD, 0;  #Make sure we clear CLOSEXEC
    fcntl $c_write, F_SETFD,0;

    push @pairs,[$p_read, $p_write, $c_read, $c_write]; 

  }

  
  # Create the template process here. This is the first worker
  #Need to bootstrap/ create the first worker, which is used as a template
  DEBUG and say STDERR "Create worker: Bootrapping  first/template worker"; 

  my ($parent_read, $parent_write, $child_read, $child_write)=$pairs[$p++]->@*;
  $k++;
  my $pid=fork; 
  $template_pid=$pid;

  if($pid){
    # parent
    #
    $template_worker=$pool{$pid}=[$pid, $parent_read, $parent_write, [], 0];
    $fd_worker_map{fileno $parent_read}=$template_worker;
    push @pool_free, $pid;

    #TODO: add a event watcher for reading from the child -> parent pipe
    # Need to detect event system, or assume the one specified
    #
    # Detection goes here
    # Then simply call internal loop
    #   AE::io $p_read, 0, \&getaddrinfosub;
    #
    if(%AnyEvent::){
      DEBUG and say "FOUND ANYEVENT";
      $has_event_loop=1;
      for(@pairs){
        my $in_fd=fileno $_->[0];
        push @$event_data, AE::io($_->[0], 0, sub {
          process_results $fd_worker_map{$in_fd};
        });
      }
    }
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
    my $file=__FILE__; 
    $file=~s|\.pm|/Worker.pm|;
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

# Return undef when no worker available.
#   If under limit, a new worker is spawned for next run
# Return the worker struct to use otherwise
# 
sub _get_worker{

    if($busy_count >= @pool_free){
      # see if we can allocate another worker
      DEBUG and say STDERR "get worker:  busy_count at >= \@pool_free";
      # No free workers, do we create another?
      if($k < $pool_max){
        DEBUG and say STDERR "get worker:  sending to spawn new worker";
        # unshift to ensure this is processed sooner
        unshift $template_worker->[WORKER_QUEUE]->@*, [CMD_SPAWN, $i++, $k];#scalar(keys %pool) ];
        $k++;
      }
    }
    
    # Round robin schedule  into existing worker pool
    my $worker_id=shift @pool_free;
    push @pool_free, $worker_id;
    $pool{$worker_id};
}


# Serialize messages to worker from queue
sub pool_next{

  # handle returns first .. TODO: This is only if no event system is being used
  results_available unless $has_event_loop;

  for(values %pool){
    DEBUG and say "POOL next for ".$_->[WORKER_ID]." busy: $_->[WORKER_BUSY], queue; $_->[WORKER_QUEUE]";
    my $ofd;
    # only process worker if  not busy and  have something to process
    next if $_->[WORKER_BUSY];
    next unless $_->[WORKER_QUEUE]->@*;

    $_->[WORKER_BUSY]=1;
    $busy_count++;

    my $req=shift $_->[WORKER_QUEUE]->@*;
    $req->[REQ_WORKER]=$_->[WORKER_ID];
    
    $reqs{$req->[REQ_ID]}=$req; #Add to outstanding


    # Header
    my $out=pack "l> l>", $req->[REQ_CMD], $req->[REQ_ID];

    # Body
    if($req->[REQ_CMD]==CMD_SPAWN){
        # Write to template process
        DEBUG and say ">> SENDING CMD_SPWAN TO WORKER: $req->[REQ_WORKER]";
        my $windex=$req->[2];
        my $cread=fileno $pairs[$windex][2];
        my $cwrite=fileno $pairs[$windex][3];

        $out.=pack("l> l>", $cread, $cwrite);
        $ofd=$pairs[0][1];
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
          $out.=pack $gai_pack, $_->{flags}//0, $_->{family}//0, $_->{type}//0, $_->{protocol}//0, $_->{host}, $_->{port};
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



sub process_results{
  my $worker=shift;
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
    my $entry=delete $reqs{$id};
    
    # Mark the returning worker as not busy
    #
    #$pool{$entry->[REQ_WORKER]}[WORKER_BUSY]=0;
    $worker->[WORKER_BUSY]=0;
    $busy_count--;

    if($cmd==CMD_GAI){
      DEBUG and say "<< GAI return from worker $entry->[REQ_WORKER]";
      my @res=unpack $gai_pack, $bin;
      if($entry and $entry->[REQ_CB]){
        my @list;
        for my( $error, $family, $type, $protocol, $addr, $canonname)(@res){
          say "$entry->[REQ_DATA]";
          if(ref($entry->[REQ_DATA]) eq "ARRAY"){
            push @list, [$error,$family,$type,$protocol, $addr, $canonname]; 
          }
          else {
            push @list, {family=>$family, type=>$type, protocol=>$protocol, addr=>$addr, canonname=>$canonname};
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
      unshift @pool_free, $pid;
      my ($parent_read, $parent_write, $child_read, $child_write)=$pairs[$p++]->@*;
      my $worker=$pool{$pid}=[$pid, $parent_read, $parent_write, [], 0];
      $fd_worker_map{fileno $parent_read}=$worker;

      DEBUG and say "<< SPAWN RETURN FROM TEMPLATE $entry->[REQ_WORKER]: new worker $pid";
    }
    elsif($cmd == CMD_KILL){
      my $id=$entry->[REQ_WORKER];
      DEBUG and say "<< KILL RETURN FROM WORKER: $id : $worker->[WORKER_ID]";
      delete $pool{$id};
      @pool_free=grep $_ != $id, @pool_free;
    }

    pool_next if $has_event_loop;
}

sub results_available {
  my $timeout=shift//0;
  DEBUG and say "CHECKING IF ReSULTS AVAILABLE";
  # Check if any workers are ready to talk 
  my $bits="";
  for(values %pool){
    vec($bits,  fileno($_->[WORKER_READ]),1)=1;
  }

  my $count=select $bits, undef, undef, $timeout;

  if($count>0){
    #say "COUNT: $count";
    for(values %pool){
      if(vec($bits, fileno($_->[WORKER_READ]), 1)){
        process_results $_;
      }
    }
  }
  $count;
}

sub getaddrinfo{
  if( @_ !=0){


    my ($host, $port, $hints, $cb)=@_;

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
    my $req=[CMD_GAI, $i++, $hints, $cb, $worker->[WORKER_ID]];
    push $worker->[WORKER_QUEUE]->@*, $req;
  }

  pool_next;
  #return true if outstanding requests
  scalar %reqs;
}

sub getnameinfo{
  my ($addr, $flags, $cb)=@_;
    my $worker=_get_worker;
    my $req=[CMD_GNI, $i++, [$addr, $flags], $cb, $worker->[WORKER_ID]];
    push $worker->[WORKER_QUEUE]->@*, $req;
    pool_next;
    scalar %reqs;
  
}



sub close_pool {
  # all worker pids, with template last
  my @pids=grep $_ != $template_pid, @pool_free;#keys %pool;
  #push @pids, $template_pid;

  #generate messages to close
  for(@pids){
    my $worker=$pool{$_};
    my $req=[CMD_KILL, $i++, [], undef, $_];
    push $worker->[WORKER_QUEUE]->@*, $req;
    pool_next;
  }
  #unshift @pool_queue, [CMD_KILL, $i++,[], undef, $_] for reverse @pids;
  #
}


###############################################################################################
# # If use as a script, we are a worker                                                       #
# #                                                                                           #
# unless(caller){                                                                             #
#                                                                                             #
#   package main;                                                                             #
#   use v5.36;                                                                                #
#                                                                                             #
#   # process any command line arguments for input and output FDs                             #
#   my $run=1;                                                                                #
#   my @in_fds;                                                                               #
#   my @out_fds;                                                                              #
#   #say "Processing ARGV";                                                                   #
#   while(@ARGV){                                                                             #
#     local $_=shift;                                                                         #
#     if(/--in/){                                                                             #
#         @in_fds=split ",", shift;                                                           #
#         next;                                                                               #
#     }                                                                                       #
#     if(/--out/){                                                                            #
#         @out_fds=split ",", shift;                                                          #
#         next;                                                                               #
#     }                                                                                       #
#   }                                                                                         #
#                                                                                             #
#   Socket::More::Resolver::DEBUG and say STDERR "TEMPLATE: ins: @in_fds";                    #
#   Socket::More::Resolver::DEBUG and say STDERR "TEMPLATE: outs: @out_fds";                  #
#                                                                                             #
#   # Pipes back to the API                                                                   #
#   #                                                                                         #
#   open my $in,  "<&=$in_fds[0]" or die $!;                                                  #
#   open my $out, ">&=$out_fds[0]" or die $!;                                                 #
#   #$out->autoflush;                                                                         #
#                                                                                             #
#   require Socket::More::Lookup;                                                             #
#   #Simply loop over inputs and outputs                                                      #
#   Socket::More::Resolver::DEBUG and say "Worker waiting for line ...";                      #
#   while(<$in>){                                                                             #
#     Socket::More::Resolver::DEBUG and say "Worker got line...";                             #
#     #parse                                                                                  #
#     # Host, port, hints                                                                     #
#     chomp;                                                                                  #
#                                                                                             #
#     my $bin=pack "H*", $_;                                                                  #
#     my ($cmd, $req_id)=unpack "l> l>", $bin;                                                #
#     $bin=substr $bin, 8;                                                                    #
#                                                                                             #
#     Socket::More::Resolver::DEBUG and say "WORKER $$ REQUEST,  ID: $req_id";                #
#                                                                                             #
#     my $return_out=pack "l> l>", $cmd, $req_id;                                             #
#     if($cmd == Socket::More::Resolver::CMD_SPAWN){                                          #
#       #Fork from me. Presumably the template                                                #
#       my $pid=fork;                                                                         #
#       if($pid){                                                                             #
#         #Parent                                                                             #
#         # return message back to API with PID of offspring                                  #
#         Socket::More::Resolver::DEBUG and say "FORKED WORKER... in parent child is $pid";   #
#         $return_out.=pack "l>", $pid;                                                       #
#         #syswrite $out, unpack("H*", pack "sss", $cmd, $req_id, $pid)."\n";                 #
#       }                                                                                     #
#       else {                                                                                #
#         #child.                                                                             #
#         Socket::More::Resolver::DEBUG and say "FORKED WORKER... child with fds";            #
#         my ($in_fd, $out_fd)=unpack "l> l>", $bin;                                          #
#         close $in;                                                                          #
#         close $out;                                                                         #
#                                                                                             #
#         Socket::More::Resolver::DEBUG and say "infd $in_fd, out_fd $out_fd";                #
#         open $in,  "<&=$in_fd" or die $!;                                                   #
#         open $out, ">&=$out_fd" or die $!;                                                  #
#                                                                                             #
#         next; #Do not respond.                                                              #
#       }                                                                                     #
#                                                                                             #
#     }                                                                                       #
#     elsif($cmd== Socket::More::Resolver::CMD_GAI){                                          #
#       #Assume a request                                                                     #
#       my @e =unpack $gai_pack, $bin;                                                        #
#       #say "inputs: @e";                                                                    #
#       my @results;                                                                          #
#       my $port=pop @e;                                                                      #
#       my $host=pop @e;                                                                      #
#       Socket::More::Resolver::DEBUG and say "WORKER $$ PROCESSIG GAI REQUEST, id: $req_id"; #
#       my $rc=Socket::More::Lookup::getaddrinfo($host, $port, \@e, \@results);               #
#       #say "Result code :$rc ";                                                             #
#                                                                                             #
#       if($rc!=0 and @results ==0){                                                          #
#         $results[0]=[$rc, -1, -1, -1, "", ""];                                              #
#       }                                                                                     #
#       #my $data=pack "s s", $cmd,$req_id;                                                   #
#       for(@results){                                                                        #
#         $_->[0]= $rc;                                                                       #
#         $return_out.=pack($gai_data_pack, @$_);                                             #
#       }                                                                                     #
#       #syswrite $out, unpack("H*", $data)."\n";                                             #
#     }                                                                                       #
#     elsif($cmd==Socket::More::Resolver::CMD_KILL){                                          #
#       # worker needs to exit                                                                #
#       #                                                                                     #
#       $run=undef;                                                                           #
#     }                                                                                       #
#     else {                                                                                  #
#       die "Unkown command";                                                                 #
#     }                                                                                       #
#                                                                                             #
#     Socket::More::Resolver::DEBUG and say "** BEFORE WORKER WRITE $$";                      #
#     syswrite $out, unpack("H*", $return_out)."\n" or say $!;                                #
#     Socket::More::Resolver::DEBUG and say "** AFTER WORKER WRITE $$";                       #
#                                                                                             #
#     last unless $run;                                                                       #
#   }                                                                                         #
#                                                                                             #
#   Socket::More::Resolver::DEBUG and say "** EXITING WORKER $$";                             #
# }                                                                                           #
###############################################################################################

1;
