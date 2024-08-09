#!/usr/bin/env perl

=pod

=head1 NAME

	quad2int.pl

=head1 SYNOPSIS

	./quad2int.pl some_IP_address

	where
		some_IP_address	: the IP address you want to be represented by an unsigned integer

	Example:
		./quad2int.pl 10.10.0.1

=head1 AUTHOR

	Marcel Quirijnen - quirijnen.marcel@gmail.com - March 1st 2019

=head1 DESCRIPTION

	Accepts an IPv4 network address in dotted quad string format and returns a 32 bit integer representation

=head1 INSTALLATION

	How about just copy it somewhere and try it out.

=head1 MORE PERL CODE OF MINE

	https://bitbucket.org/sugarcreek/perl     - speaks for itself 
	https://bitbucket.org/sugarcreek/php/src  - looks like php, but is 80% perl (Vonage, Optanix)
	
=cut

use strict;
use warnings;
use 5.10.0;
use Carp;
use lib::IPAddress;

my ($ip_str) = @ARGV;
croak "Please specify an IP address\n" if (not defined $ip_str);

my $ip = IPAddress->new();
say 'Integer value of ', $ip_str, ' is ', $ip->quad2int($ip_str);
#say 'The IP represented by ', $ip->quad2int($ip_str), ' is ', $ip->int2quad($ip->quad2int($ip_str));
