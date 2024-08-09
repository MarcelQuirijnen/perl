package System::Unix;

use strict;

our $VERSION = '1.0.0';

# Map from $^O values to implement the classes.
my %os_class = (
     linux   => "Linux",
     solaris => "Solaris",
     sunos   => "SunOS",
     hpux    => "HPUX",
     irix    => "Irix",
     aix     => "AIX",
);

sub _os_class
{
    # Perl already knows what platform this is, so use it in case it's not spcified
    my($OS) = shift || $^O;

    my $class = __PACKAGE__ . '::' . $os_class{$OS};
    no strict 'refs';
    unless (%{"$class\::"}) {
        eval "require $class";
        die $@ if $@;
    }
    $class;
}

sub new
{
    my($class, $os) = @_;

    # let the object itself find out what os this is .. I don't care
    _os_class($os)->new;
}

1;

__END__

=head1 NAME

System::Unix - Generic Unix system info

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 NOTES

=head1 SEE ALSO

L<System::Unix>, L<System::Unix::Irix>, L<System::Unix::Solaris>, L<System::Unix::Linux>

=head1 COPYRIGHT

Copyright 2004 Marcel Quirijnen.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
