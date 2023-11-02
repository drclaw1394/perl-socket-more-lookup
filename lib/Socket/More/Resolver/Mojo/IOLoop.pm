use v5.36;
package Socket::More::Resolver::Mojo::IOLoop;

use IO::Handle;
use Mojo::IOLoop;

our @watchers;


sub {
  my ( $loop ) = @_;

  # Use singleton loop if none specified
  $loop//=Mojo::IOLoop->singleton;
  $Socket::More::Resolver::Shared=1;
  # Code here to set up event handling on $loop that may be required
  my @fh=Socket::More::Resolver::to_watch;
  my $watchers=$self->{watchers};
  for(@fh){
    my $fh=$_;
    my $in_fd=fileno $fh;
    my $w=IO::Handle->new_from_fd($in_fd, "r");
    $loop->reactor->io($w, sub {
          Socket::More::Resolver::process_results $in_fd;
      }
    )->watch($w,1,0);
    push @$watchers, $w;
  }


  # Add timer/monitor here
  
  # set clean up routine here
}
