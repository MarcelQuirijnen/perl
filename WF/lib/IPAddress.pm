package IPAddress;

use strict;
use warnings;
use 5.10.0;
use Carp qw(croak);
#use Data::Dumper qw(Dumper);

=pod

=head1 IPAddress

=over 3

=item What

This module accepts an IPv4 network address in dotted quad string format and returns a 32 bit integer representation.

=item Why

Requested as a job application test.

=item Who

Marcel Quirijnen - quirijnen.marcel@gmail.com - Mar 1st 2019

=back

=cut

# Constructor
sub new
{
   ## not doing anything interesting in here
   ## new is expected only to create and return a blessed reference
   my ($class, @args) = @_;
   ## do something with @args
   return bless {}, $class;
}

# Given an IP, returns int representation
sub quad2int()
{
   my ($self, $ip_str) = @_;

   ## Did you specify an IP?
   if (not defined $ip_str) {
      croak "I need an IP address. Really.\n";
   }

   ## every IPv4 has 4x8 bits separated by dots. Let's confirm that
   ## not interested in handling IPv6
   my @octets = split(/\./, $ip_str);
   croak "Invalid IP. A network address requires 4 numbers separated by dots." if scalar(@octets) != 4;

   ## don't want any signed numbers, floating point nos or scientic notation sillyness
   foreach(@octets) {
      croak "Invalid IP. No alpanumeric tricks please. See -->$_<--" if !/^\d+$/;
   }

   ## make sure we don't interpret individual numeric parts as octal numbers (very different IP address)
   my @quads = map { $_ + 0 } @octets;   ## s/^0+//g could work as well

   my $num = ($quads[0]<<24) + ($quads[1]<<16) + ($quads[2]<<8) + $quads[3];
   return $num
}

# Given an int representing an IP, returns the corresponding dotted-quad
# written to prove correctness of the above quad2int - solely for my peace of mind - hence no error checking
sub int2quad()
{
   my ($self, $ip_int) = @_;
   croak("IPAddress::int2quad() - Not implemented.\n");  # comment out to test/use

   my $result = ''; 
   
   for (24,16,8,0){
      $result .= (($ip_int >> $_)  & 255)  . '.';
   }
   chop $result; # Delete extra trailing dot
   return $result;
}

1;
