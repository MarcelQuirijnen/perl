package System::Unix::Irix;

use strict;
require Sys::Hostname;

sub new
{
  my $this = shift;
  my $class = ref($this) || $this;
  my $self = {};
  bless $self, $class;
  $self->_initialize();
  return $self;
}

# Initialize with Irix specific stuff
sub _initialize
{
  my $self = shift;

  $self->{CLUSTER} = &_is_cluster;
  $self->{LABEL} = 'Irix';
  $self->{CMD} = { EGREP       => &_which('egrep'),
                   MAILER      => &_which('Mail'),
                   QSTAT       => '',
                   DMESG       => &_which('hinv'),
                   PROCESSES   => '',
                   TOP         => &_which('top'),
                   NODEPROPS   => '',
                   FOREACHNODE => '',
                   NODEINFO    => '',
                 };
  $self->{FILES} = { SYSLOG      => '/var/adm/SYSLOG',
                     SYSMONLOG   => '',
                   };
  ($self->{HOSTNAME}, undef) = split(/\./, &Sys::Hostname::hostname, 2);
}

sub _which
{
   my $which_cmd = shift;

   chomp(my $cmd = qx { /usr/bin/which $which_cmd 2>/dev/null } || '');
   return ($cmd);
}

sub _is_cluster
{
   return 0;
}


1;

__END__

=head1 NAME

System::Unix::Irix - Irix system info

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 NOTES

=head1 SEE ALSO

L<System::Unix>, L<System::Unix::Irix>, L<System::Unix::Solaris>, L<System::Unix::Linux>

=head1 COPYRIGHT

Copyright 2004 Marcel Quirijnen.
Copyright 2004 ExxonMobil

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

