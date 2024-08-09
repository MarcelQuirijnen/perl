package System::Unix::Linux;

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

# Initialize with Linux specific stuff
sub _initialize
{
  my $self = shift;

  $self->{CLUSTER} = &_is_cluster;
  $self->{LABEL} = 'Linux';
  ($self->{HOSTNAME}, undef) = split(/\./, &Sys::Hostname::hostname, 2);
  $self->{CMD} = { EGREP       => &_which('egrep'),
                   MAILER      => &_which('Mail'),
                   QSTAT       => ($self->{CLUSTER}) ? '/usr/local/bin/qstat' : '',
                   DMESG       => &_which('dmesg'),
                   PROCESSES   => ($self->{CLUSTER}) ? '/usr/local/bin/processes' : '',
                   TOP         => &_which('top'),
                   NODEPROPS   => ($self->{CLUSTER}) ? '/usr/local/bin/nodeProps' : '',
                   FOREACHNODE => ($self->{CLUSTER}) ? '/nodes/scripts/foreachnode' : '',
                   NODEINFO    => ($self->{CLUSTER}) ? '/nodes/scripts/nodeInfo' : '',
                 };
  $self->{FILES} = { SYSLOG      => '/var/log/messages',
                     SYSMONLOG   => '/var/log/sysmond.log',
                   };
  $self->{VAR}->{TOP_OFFSET} = 10;
  $self->{PARAM}->{TOP} = '-n 1';
}

sub _which
{
   my $which_cmd = shift;

   chomp(my $cmd = qx { /usr/bin/which $which_cmd 2>/dev/null } || '');
   return ($cmd);
}

sub _is_cluster
{
   # Isn't there a better way of doing this ?
   # could easily emulated using mount or mkdir
   # Suggestions are welcome, except mentioning hardcoded hostnames :-), alltough this is just as bad
   return ( -d '/nodes/scripts' ) ? 1 : 0;
}


1;

__END__

=head1 NAME

System::Unix::Linux - Linux system info

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

