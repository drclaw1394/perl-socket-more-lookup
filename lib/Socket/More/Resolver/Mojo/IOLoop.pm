use v5.36;
package Socket::More::Resolver::Mojo::IOLoop;

use IO::Handle;
use Mojo::IOLoop;
use Socket::More::Resolver ();      # Do not run import, just load code.
use Export::These export_pass=>[qw<max_workers prefork>];  # Allow pass through of names

sub _add_to_loop;
# Shared object,
my $_shared;
my @watchers;


sub _preexport {
  shift; shift;
  @_;
}

sub _reexport{
  shift;
  shift;
  #my @config=grep ref, @_;
  #my %options=grep !ref, @_;
  

  Socket::More::Resolver->import(@_);
  

  $Socket::More::Resolver::Shared=1;
  _add_to_loop;

}


sub getaddrinfo{
  my $self=shift;
  &Socket::More::Resolver::getaddrinfo;
}

sub getnameinfo{
  my $self=shift;
  &Socket::More::Resolver::getnameinfo;
}

sub _add_to_loop {
  my $self = shift;
  my ( $loop ) = @_;

  # Use singleton loop if none specified
  $loop//=Mojo::IOLoop->singleton;
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
}
 
sub _remove_from_loop {
  #######################################################
  # my $self = shift;                                   #
  # my ( $loop ) = @_;                                  #
  #                                                     #
  # # Code here to undo the event handling set up above #
  #                                                     #
  # for($self->{watchers}->@*){                         #
  #   $loop->remove($_);                                #
  # }                                                   #
  # $self->{watchers}=[];                               #
  #######################################################
}


1
