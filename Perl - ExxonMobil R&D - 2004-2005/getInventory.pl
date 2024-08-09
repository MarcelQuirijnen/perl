#!/usr/bin/perl

use strict;

my @libs;
my $LibDelimeter=","; # record seeporator for inventoy of libirary
my %poolPLIDS;
my @pools;
my %reportByPool; # hash of strings for pool rebports, keys are pool names
my %poolAvailToatals;
my $hostname=$ENV{HOSTNAME};
my $fullPool="full";
my $secsPerDay=86400;


my $report="Arkeia Tape Library Summary for host:$hostname\n\n";
#### GET LIBRARYS #############
sub getLibs () {
  open (cmd,"arkc -library -list|");
  my $line;
  while ($line=<cmd>) {
    chomp $line;
    #print "$line\n";
    my $name;
    (undef,$name)=split ("=",$line,2);
    #print "Found Library NAME=$name\n";
    push @libs,$name;
    }
  close cmd;
  }
#### List Lapes In Library #####
sub doInventory () {
  my $i;
  my @results;
  foreach $i (@libs) {
    my @item;
    open (cmd,"arkc -library -list -D name=[$i]|");
    my $line;
      while ($line=<cmd>) {
        chomp $line;
        #print "$line\n";
        push @item,$line;
      }
    close cmd;
    my $oneLine=join ($LibDelimeter,@item);
    push @results,$oneLine
    }
  return @results;
  }
#### Get the pools
sub getPools  {
  my @pools;
  open (cmd,"arkc -pool -list|");
  my $line;
    while ($line=<cmd>) {
    chomp ($line);
    my (undef,$pool)=split ("=",$line,2);
    push @pools,$pool;
    
  }
  close cmd;
  return @pools;
}
#### Print the poolnames ######
sub printPools  {
  my @tmpPools=@_;
  my $i;
  foreach $i (@tmpPools) {
    print "POOL=$i PLID=".$poolPLIDS{$i}."\n";
  }
}
#### Print pool hash with plids #
sub printPoolsHash  {
  my $i;
  foreach $i (keys %poolPLIDS) {
    print "POOL=$i PLID=".$poolPLIDS{$i}."\n";
  }
}

#### Print hash #
sub printHash  {
  my $hash;
  $hash=shift @_;
  my $i;
  foreach $i (keys %$hash) {
    print "Key=$i Value=".$$hash{$i}."\n";
  }
}

#### Get The Pool PLIDs for the Pools
sub getPoolPLIDS {
  my @tmpPools=@_;
  my @PLIDS;
  my %poolPLIDS;
  my $i;
  foreach $i (@tmpPools) {
    my $line;
    open (cmd,"arkc -pool -list -D name=[$i]|");
    while ($line=<cmd>) {
      chomp ($line);
      if ($line =~ /^PLID=/ ) {
        my (undef,$plid)=split ("=",$line,2);
        push @PLIDS,$plid;
	#put the pool id in a hash with the pool name as the key
        ##$poolPLIDS{$i}=$plid;
        $poolPLIDS{$plid}=$i;
        #print "Created hash key:$i, with value $plid\n"
      }
    }
  close cmd;
  }
  ##return @PLIDS;
  return %poolPLIDS;
}
#### GET Tape detail ##########
sub getTapeDetail {
  my $tapeName=shift;
  my %tape;
  ## Set default settings for age, expires
  $tape{"expires"}="expired";
  $tape{"age"}="expired";
  my $tapeInfo;
  my $rspace; #remaining space on tape
  my $tspaceUsed; # total space used on tape
  my $expires; #date tape expires
  my $status;
  my $stat;
  my $myPool;
  my $lastWrite;

  open (FH,"arkc -tape -list -D name=$tapeName|");  
  while (<FH>) {
    chomp;
    my $line=$_;

    if ($line=~/^REMAIN_SPACE=(.*)$/) {
        $rspace=$1;#$line."\t";
       #print "rspace=$rspace\n";

        }

    elsif ($line=~/^TOTAL_SPACE=(.*)$/) {
        $tspaceUsed=$1;
        }

    elsif ($line=~/^RDATE=(.*)$/) {
        $expires=$1;
        }

    elsif ($line=~/ST_CONTENT=(.*)$/) {
        (undef,$status)=split '_',$1,2;
        $stat=substr $status,0,6;
        }

    elsif ($line=~/PLID=(.*)$/) {
        $myPool=$poolPLIDS{"$1"};
        if (! $myPool) { $myPool="-Undef";}
        }
    elsif ($line=~/LAST_WRITTEN=(.*)$/) {
        $lastWrite=$1;
        }
  }
  close FH;

  if ($expires) {
    my $date="expired";
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($expires);
    $year+=1900;
    $mon+=1;
    $date=sprintf ('%02d/%02d', $mon, $mday);
    $date.="/$year";
    #$date.=sprintf ('%02d:%02d:%02d', $hour,$min,$sec);
    #$date="$mon/$mday/$year $hour:$min:$sec";
    $tape{"expires"}=$date;
    }
  if ($lastWrite) {
    my $date="expired";
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($lastWrite)
;
    $year+=1900;
    $mon+=1;
    $date=sprintf ('%02d/%02d', $mon, $mday);
    $date.="/$year";
    #$date.=sprintf ('%02d:%02d:%02d', $hour,$min,$sec);
    #$date="$mon/$mday/$year $hour:$min:$sec";
    $tape{"age"}=$date;
    }      
  $tape{"status"}=$stat;
  $tape{"pool"}=$myPool;
  $tape{"rspace"}=$rspace;
  $tape{"uspace"}=$tspaceUsed;
  $tape{"name"}=$tapeName;
  return %tape
}
#### MAIN ######################

@pools=getPools();
%poolPLIDS=getPoolPLIDS(@pools);
#printHash(\%reportByPool);

#printPoolsHash();
getLibs();
my @inventory=doInventory();
# at this point $poolPLIDS{poolname}=$plid
# @libs contains the name of the libaries
# $inventory[0] is inventory of first libary


my $lib;
my $libCount=-1;
foreach $lib (@inventory) {
  ++$libCount;
  my $tmp;
  foreach $tmp (@pools) {
    #make the Report Header
    $reportByPool{$tmp}="SUMMARY FOR Library:$libs[$libCount] POOL: $tmp\n"; #make the Report Header
    $reportByPool{$tmp}.=sprintf ('%-7s', "Status");
    $reportByPool{$tmp}.=sprintf ('%-15s', "Name");
    $reportByPool{$tmp}.=sprintf ('%-5s', "Slot");
    $reportByPool{$tmp}.=sprintf ('%-12s',"Last_Write");
    $reportByPool{$tmp}.=sprintf ('%-11s', "Exp_Date");
    $reportByPool{$tmp}.=sprintf ('%13s', "   Used_Space");
    $reportByPool{$tmp}.=sprintf ('%13s', "  Avail_Space");
    $reportByPool{$tmp}.="\n";
    # set pool avail bytes to 0
    $poolAvailToatals{$tmp}=0;
  }


  #seperate heder/slot info
  my ($header,$slotUsage)=split ("$LibDelimeter<ITEM>$LibDelimeter",$lib,2);  
  #print "HEADER=".$header."\n\n";
  # wack off trailing <\ITEM>
  ($slotUsage,undef)=split (/<\/ITEM>$/,$slotUsage);
  # get slots
  my @slots=split(/<\/ITEM>$LibDelimeter<ITEM>/,$slotUsage);
  my $i;

  my @Search= ( "STATUS", "SLOT", "VOLTAG", "LABEL", "CONTENT", "TPID", "IOE_NUM", "FORM_FACTOR", "REAL_TPID" );
 
  foreach $i (@slots) {
      #print "line =$i\n";
      my %slot;
      my $j;
      foreach $j (@Search) {
        my $val="";
        if ($i=~ s/$j=(.*?)$LibDelimeter//) {
          $val=$1;
          $slot{$j}=$val;   
          #print "$j=$val\n";
          $val=undef;
        }
      }
    if (defined  $slot{LABEL} ) {
      # 1. We have a tape in the slot, get the details
      #print $slot{LABEL}."\n\n";
      my %tape=getTapeDetail($slot{LABEL});
      #printHash \%tape;
      # add to the report by pool
      $reportByPool{$tape{pool}}.=sprintf ('%-7s', $tape{status});
      $reportByPool{$tape{pool}}.=sprintf ('%-15s', $tape{name});
      $reportByPool{$tape{pool}}.=sprintf ('%-5s', $slot{SLOT});
      $reportByPool{$tape{pool}}.=sprintf ('%-12s', $tape{age});
      $reportByPool{$tape{pool}}.=sprintf ('%-11s', $tape{expires});
      $reportByPool{$tape{pool}}.=sprintf ('%13s', "$tape{uspace}k");
      $reportByPool{$tape{pool}}.=sprintf ('%13s', "$tape{rspace}k");
      $reportByPool{$tape{pool}}.="\n";
      if ($tape{status} ne  "FULL" ) { # add to avail in pool space
        $poolAvailToatals{$tape{pool}}+=$tape{rspace};
        }
      else { $poolAvailToatals{$tape{pool}}+=0; }

    }
    #print "line=$i\n\n";
  }

  # SUMARIZE fREE space
  my $key;
  foreach $key (keys %reportByPool) {
    $reportByPool{$key}.=sprintf ('%77s',"AVAIL WRITING SPACE IN POOL: $poolAvailToatals{$key}k\n");
  }
  
  #Print the report
  my $key;
  foreach $key (keys %reportByPool) {
    $report.=$reportByPool{$key};
    $report.="\n\n";
  }
  #printHash(\%poolAvailToatals);

}

print $report."\n\n";
      
exit 0;



