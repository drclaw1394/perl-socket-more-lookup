package Socket::More::Lookup;

use 5.036000;

our $VERSION = 'v0.1.0';

require XSLoader;
XSLoader::load('Socket::More::Lookup', $VERSION);
use Export::These qw<getaddrinfo getnameinfo gai_strerror>;
1;
