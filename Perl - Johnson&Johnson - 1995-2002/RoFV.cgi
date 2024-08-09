#!/usr/local/bin/perl

##################################################################
# Documentation for this routine is found ONLY on the MDC portal #
# as requested by Project Management Policies                    #
##################################################################

# rofv calculation routine
# Rule Of Five Violation

#use strict;
use File::MkTemp;
use CGI qw/:standard *table/;
use CGI::Carp 'fatalsToBrowser';
my $MAX_SIZE_UPLOAD = 1000; # K, return an 'Internal Server Error' on oversized files
$CGI::POST_MAX=1024 * $MAX_SIZE_UPLOAD;

my $DATA_DIR = '/db/www/dvl/bs/portal/data';   # Path of data directory
my $FORM_URL = 'http://btmcs2.janbe.jnj.com:85/mdc/tools/upload.html';
	
my %NAME_BUTTON = ('back' => 'Back');
my %NAME_TITLE  = ( 'error_form' => 'Error : Incomplete form',
		    'EU_BadFN' => "Error: Bad Input 'Value_FileName'", 
                    'EU_FExist' => "Error: File 'Value_FileName' exists, can not overwrite !",
		    'EU_Size' => "Error: Could not upload oversized file: 'Value_FileName'", 
                    'Upload_Succes' => 'Upload uploaded successfully!',
		    'Upload_Succes_txt' => "'Value_FileName' (Value_Size bytes, Value_Time sec) was saved" 
                  );

my $SCRIPT = '/usr/local/bin/scripts/rofv.pl -jrf ';

#####
# Main routine
#####
my $query = new CGI;
my $action   = $query->param('ac');
my $file_name;

if ($action eq 'upload') {
   print $query->header;
   print &Upload($query);
   RoFV($query);
   Remarks($query);
} else {
   if ($query->cgi_error) {
      $_ = $NAME_TITLE{'EU_Size'};
      s/Value_FileName/OverSized File/ig;
      print header(-type => 'text/html', -status => '413 POST too large');
      Error($_);
      exit;
   } else {
      print $query->redirect($FORM_URL);
   }
}
print $query->end_html;


sub RoFV
{
   my ($query) = @_;
   my (@results, @heading, @data, $dat) = ((),(),(), 0);
   my $start = 0;

   $type = $query->param('filetype');

   if ($type eq 'rno') {
      use lib "/usr/local/bin/scripts/automation";
      #use Env;
      require Modules::TMCOracle;
      &Modules::TMCOracle::SetupOracleEnv;
   }

   @results = qx{ $SCRIPT -full -table -$type $DATA_DIR/$file_name | tee $DATA_DIR/$file_name.txt };
   if ($type eq 'sdf' || $type eq 'tdt') {
      push @heading, 'COMP_ID', 'SMILES', 'INDICATOR', 'RoFV', 'CLOGP', 'CLOGP_ERR', 'AMW', 'HBA', 'HBD';
      $start = 0;
   } elsif ($type eq 'txt') {
      @heading = split(/\s+/, $results[0]);
      $start = 1;
   } elsif ($type eq 'smi') {
      $start = 0;
      push @heading, 'COMP_ID', 'SMILES', 'INDICATOR', 'RoFV', 'CLOGP', 'CLOGP_ERR', 'AMW', 'HBA', 'HBD';
   } else {
      # list of rnos
      $start = 0;
      push @heading, 'COMP_ID', 'SMILES', 'INDICATOR', 'RoFV', 'CLOGP', 'CLOGP_ERR', 'AMW', 'HBA', 'HBD';
   }
   print '<table border="1" cellpadding="5" cellspacing="0">';
   print caption({align=>'top'}, h2('RoFV results'));
   for ($x = $start; $x < scalar(@results); $x++) {
      print th([ @heading ]) if $x == $start;
      print '<TR align="CENTER" valign="TOP">';
      @data = split(/\s+/, $results[$x]);
      # following line doesnt work .. mysterious reason
      #print td({-nowrap}, [ @data ]),
      foreach $dat (@data) {
         print td({-nowrap}, $dat);
      }
      print '</tr>';
   }
   print end_table();
   print '<br><br>', "\n";
   print 'Or ', $query->a({href=>"/data/$file_name.txt"}, "download"), ' them';
   #unlink $DATA_DIR/$file_name;
}

sub Remarks
{
  my ($query) = @_;
  print '<br><br><br>', "\n";
  print '1. Result files are removed during the weekend.<br>', "\n";
  print '2. Result files are in unix txt format. <br>', "\n";
  print '&nbsp;&nbsp;&nbsp;&nbsp;Convert them with this ', $query->a({href=>"/mdc/tools/fixcrlf.exe"}, "tool"), "\n";
}

#####
# Upload routine
#####
sub Upload
{
   my ($query) = @_;
   my ($data, $file_query, $size, $buff, $time, $secs, $bytes_count);
   my @lines = ();
   $size = $bytes_count = 0;
   $_ = $file_query = $query->param('file');
   s/\w://;
   s/([^\/\\]+)$//;
   $_ = $1;
   s/\.\.+//g;
   s/\s+//g;
   $file_name = $_;
   if (! $file_name) {
      $data = $query->param('pastedData');
      if (! $data) {
         $_ = $NAME_TITLE{'EU_BadFN'};
         s/Value_FileName/No Input Data/ig;
         &Error($_);
      } else {
         chomp($data);
         @lines = split(/\r/, $data);
         $file_name = File::Spec->catfile(mktemp(tempXXXXXX));
         open(F, "+>$DATA_DIR/$file_name");
         print F @lines;
         close(F);
      }
   #} elsif (-e "$DATA_DIR/$file_name") {
   #   #$file_name = File::Spec->catfile(mktemp(tempXXXXXX));
   #   $_ = $NAME_TITLE{'EU_FExist'};
   #   s/Value_FileName/$file_name/ig;
   #   &Error($_);
   } else {
      $file_name = File::Spec->catfile(mktemp(tempXXXXXX));
      open(FILE,">$DATA_DIR/$file_name") || &Error("Error opening file $file_name for writing, error $!");
      binmode FILE;
      while ($bytes_count = read($file_query,$buff, 2096)) {
         $buff =~ s/\r\n/\n/g;
         print FILE $buff;
      }
      close(FILE);
   }
   if ((stat "$DATA_DIR/$file_name")[7] <= 0) {
      $_ = $NAME_TITLE{'EU_Size'};
      s/Value_FileName/$file_name/ig;
      &Error($_);
   } #else {
      #$time = time - $time;
      #$_ = $NAME_TITLE{'Upload_Succes_txt'};
      #s/Value_FileName/$file_name/ig;
      #s/Value_Size/$size/ig;
      #s/Value_Time/$time/ig;
      #&ResultPage($NAME_TITLE{'Upload_Succes'}, $_);
   #}
}

########################################
# HTML Present subs                    #
########################################

sub HTMLHeaderTitle {
	return &HTMLHeader($_[0]).&Title($_[0]);
}

sub HTMLHeader {
	my($head_title) = @_;
	$head_title =~ s/\<\w\w*\>/ /g;
	$head_title =~ s/\&(\w)\w+;/$1/g;
	return $query->start_html( -title => $head_title,
                                   -bgcolor => '#FFFFFF',
			           -meta => { 'robot'=>'NOINDEX, FOLLOW', 'description'=>'none', 'keywords'=>'none',
			                      'copyright' => 'MDC', 'author' => 'MDC', 'generator' => 'MDC tools' }
			         );
}

sub Title {
    return <<EOF;
<BR><BR>
<P ALIGN="Center">
  <FONT FACE="Arial, helvetica" SIZE="+2" COLOR="#336699">
     <STRONG>
       <EM>$_[0]</EM>
     </STRONG>
  </FONT>
</P>
<BR>
EOF
}

sub ResultPage {
   my($title, $text, $ac) = @_;
   $_ = &HTMLHeaderTitle($title);
   $_ .= "<TABLE WIDTH=\"80%\" ALIGN=\"CENTER\"><TR><TD ALIGN=\"CENTER\">";
   $_ .= "<FONT FACE=\"Arial\" SIZE=\"-1\">$text<P>";
   $_ .= &BackPost("",$ac);
   $_ .= "</FONT>\n</TD></TR></TABLE>";
   return $_;
}

sub Error {
    my ($errortext) = @_;
    print &HTMLHeaderTitle($errortext);
    exit;
}

########################################
# Other Subs                           #
########################################

sub BackPost {
    my($title, $ac) = @_ ;
    $title = $NAME_BUTTON{'back'} if ! $title;
    return "<CENTER><BR><BR><FORM METHOD=post><INPUT TYPE=HIDDEN Name=ac VALUE=$ac><INPUT TYPE=Submit VALUE=\" $title\" ></FORM><BR><BR></CENTER>\n";
}

