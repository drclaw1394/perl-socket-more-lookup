use v5.36;
package Socket::More::Resolver::AE;
use Socket::More::Resolver ();

sub _add_to_loop;

my $_shared;
my $_timer;
my @watchers;

sub import {
  shift;
  return if $_shared;

  $_shared=1;
  $Socket::More::Resolver::Shared=$_shared;
  _add_to_loop;

}

sub _add_to_loop {

  # Code here to set up event handling on $loop that may be required
  my @fh=Socket::More::Resolver::to_watch;
  for(@fh){
    #my $fh=$_;
    my $in_fd=fileno $_;
    my $w= AE::io $in_fd, 0, sub {
          Socket::More::Resolver::process_results $in_fd;
    };
    push @watchers,$w;
  }
  
  #setup timer to monitor child existance
  #$timer=AE::timer 1, 1, \&Socket::More::Resolver::monitor_workers;
}
 
sub _remove_from_loop {
  @watchers=();
}

1;
