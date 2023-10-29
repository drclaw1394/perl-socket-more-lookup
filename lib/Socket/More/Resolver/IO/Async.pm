use v5.36;
package Socket::More::Resolver::IO::Async;
use parent qw(IO::Async::Notifier);
use IO::Async::Handle;

use Socket::More::Resolver ();   # no not run import
use Export::These export_pass=>[qw<max_workers prefork>];

# Shared object,
my $_shared;

sub new;


sub _preexport {
  shift; shift;
  @_;
}

sub _reexport {
  shift;  #package
  shift;  #target name space

  my @config=grep ref, @_;

  my %options=map %$_, @config;
  # Create a shared resolver object if it doesn't exist
  # NOTE: user is required to add to the desired run loop
  #
  unless($options{no_shared}){
      $Socket::More::Resolver::Shared= __PACKAGE__->new;
  } 

  Socket::More::Resolver->import(@_);
}


sub getaddrinfo{
  my $self=shift;
  &Socket::More::Resolver::getaddrinfo;
}

sub getnameinfo{
  my $self=shift;
  &Socket::More::Resolver::getnameinfo;
}

sub new {
  my $package=shift;
  return $_shared if $_shared;
  
  # 
  my $self=bless {}, $package;
  $self->{watchers}=[];
  $self;
}

sub _add_to_loop {
  my $self = shift;
  my ( $loop ) = @_;

  # Code here to set up event handling on $loop that may be required
  my @fh=Socket::More::Resolver::to_watch;
  my $watchers=$self->{watchers};
  for(@fh){
    my $fh=$_;
    my $w= IO::Async::Handle->new(
        read_handle=>$fh,
        on_read_ready=> sub {
          my $in_fd=fileno $fh;
          Socket::More::Resolver::process_results $in_fd;
      }
    );
    $loop->add($w);
    push @$watchers,$w;
  }
}
 
sub _remove_from_loop {
  my $self = shift;
  my ( $loop ) = @_;

  # Code here to undo the event handling set up above

  for($self->{watchers}->@*){
    $loop->remove($_); 
  }
  $self->{watchers}=[];
}


1;
