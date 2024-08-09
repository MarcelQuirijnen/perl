#! /usr/local/bin/perl -w
# create TDT file
require 5.000;
require Carp;

while ($input = <STDIN>) {
  chop $input;
  @record = split(//,$input);

  $rno = join("",@record[0..7]);
  $temp = join("",@record[9..248]);
  $desc = '';
  while ($temp =~ /(\S+)(.*)/) {
     $desc .= ($1 . ' ');
     $temp = $2;
  }
  if ($desc =~ /(.*) /) {
     $desc = $1;
  }

  $csrp = join("",@record[250..263]);
  if ($csrp =~ /(\S+).*/){
     $csrp = $1;
  } else {
     $csrp = '';
  }

  #$mw = join("",@record[297..307]);
  $mw = join("",@record[309..314]);
  if ($mw =~ /(\S+).*/){
     $mw = $1;
  } else {
     $mw = '';
  }

  $mf = join("",@record[328..397]);
  if ($mf =~ /(\S+).*/){
     $mf = $1;
  } else {
     $mf = '';
  }

  $gn = join("",@record[399..455]);
  if ($gn =~ /(\S+).*/) {
     $gn = $1;
  } else {
     $gn = '';
  }

  print '$RNR<', $rno,  ">\n",
        'DESC<', $desc, ">\n",
        'GN<',   $gn,   ">\n",
        'MF<',   $mf,   ">\n",
        'MW<',   $mw,   ">\n",
        'CSRP<', $csrp, ">\n",
        "|\n";
}

