#!/usr/local/bin/perl -w

require 5.000;

use Net::FTP;
use sigtrap qw(die normal-signals error-signals);

my $SITE = 'ftp.rcsb.org';
my $DIR = '/pub/pdb/data/structures/all/pdb';
my $L_DIR = '/data/tmc/hans/GRID_SCORING/pdb';
my @files = ();

$ftp = Net::FTP->new($SITE, Debug => 0, Timeout => 240);
$ftp->login('anonymous', 'hdwinter@janbe.jnj.com');
$ftp->cwd($DIR);
@files = $ftp->ls();
$count = 0;
if (scalar(@files) != -1) {
   chdir $L_DIR;
   $ftp->type('binary');
   foreach $file (@files) {
      $count++;
      # pdb1fmv.ent.Z 
      ($pdb, $ext, undef) = split(/\./, $file, 3);
      if ($pdb =~ /pdb(.{4}).*/) {
         $dir = $1;
      } else {
         # Error, probably caused by python :-)
         print STDERR "Error : $pdb\n";
         next;
      }
      if (! -d $dir) {
         mkdir $dir, 0777;
      }
      #next if ( -e $pdb . '*');
      if ( -e "$dir/$pdb.pdb") {
         print "$count : Skipping $pdb\n";
         next;
      } else {
         print "$count : Fetching ", $pdb, "\n";
      }
      $ftp->get($file, "$dir/$file");
      $move_from = $dir . '/' . $pdb . '.' . $ext;
      $move_to = $dir . '/' . $pdb . '.pdb';
      qx { /usr/bsd/uncompress $dir/$file && mv $move_from $move_to && chown hans.tmc $move_to };
   }
} else {
   print "Bad luck this time\n";
}
$ftp->quit();
exit 0;
