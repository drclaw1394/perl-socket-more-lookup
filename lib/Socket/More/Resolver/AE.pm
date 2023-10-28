use v5.36;
package Socket::More::Resolver::AE;
use Socket::More::Resolver (no_export=>1);
use Export::These;

sub _add_to_loop;

my $_timer;
my @watchers;

sub _reexport{
  shift;
  shift;
  my %options=@_;
  
  Socket::More::Resolver->import;
  

  $Socket::More::Resolver::Shared=1;
  _add_to_loop;

}

sub _add_to_loop {

  # Code here to set up event handling on $loop that may be required
  my @fh=Socket::More::Resolver::to_watch;
  for(@fh){
    #my $fh=$_;
    my $in_fd=fileno $_;
    say "ADD TO LOOP in_fd $in_fd";
    my $w= AE::io $in_fd, 0, sub {
    say "ojiasdfoij";
          Socket::More::Resolver::process_results $in_fd;
    };
    push @watchers, $w;
  }
  
  #setup timer to monitor child existance
  #$timer=AE::timer 1, 1, \&Socket::More::Resolver::monitor_workers;
}
 
sub _remove_from_loop {
  @watchers=();
}

1;
