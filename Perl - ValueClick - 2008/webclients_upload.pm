package webclients_upload;

use strict;
use CGI;
use DBI;

sub new {
  my ($this,$web,$data) = @_;
  my $class = ref($this) || $this;
  my $self = { web => $web, data => $data };
  bless $self, $class;

  return $self;
}

sub go{

  my ($self) = @_;
  my $web = $self->{web};
  my $data = $self->{data};

$self->doupload() if ( $web->{params}->{filename} );

print qq{

<script type="text/javascript" language="JavaScript">

function check_file_ext() {
  var ext = document.upload.filename.value;
  ext = ext.substring(ext.length-3,ext.length);
  ext = ext.toLowerCase();
  if (ext != 'csv') {
    alert('You selected a .' + ext + ' file; Please select a .csv file.');
    return false;
  } else {
    return true;
  }
}

function ValidateForm()
{
   if (document.upload.filename.value.length == 0 || document.upload.filename.value == null) {
          alert('Pick a file.');
          document.upload.filename.focus();
          return false;
   }
   return true;
}

</script>
</head>
<body>
<form method="post" action="mod.cgi" name=myform 
      action="https://<% $ENV{'HTTP_HOST'} %>/v4/webclients_upload.cgi"
      enctype="multipart/form-data"
      onsubmit="return ValidateForm();">
<input type=hidden name=modid value="$self->{data}->{modid}">
<input type="file" accept="*.csv" name="filename" size="80" onchange="check_file_ext();"><br>
<input type="submit" value="Upload">
</form>
};

return;
}

sub doupload {
  my ($self) = @_;
  my $web = $self->{web};

print "Uploading data...<br>";

my $query = new CGI;
my $filename = $query->param('filename');

# some browsers pass the whole path to the file, instead of just the filename
# so strip off the crap
$filename =~ s/.*[\/\\](.*)/$1/;

# use file handle directly
my $upload_filehandle = $query->upload('filename');
my @csv_content = <$upload_filehandle>;

# first line is fieldnames
my $field_line = shift(@csv_content);
chomp($field_line);
# my @fields = split(/,/, $field_line);
# have to hardcode fields, cause first line field spec in .csv file is not accepted by mysql.
my @fields = (
   'log_date', 'team', 'staff', 'id', 'campaign', 'advertiser', 'type', 'hosting', 'restriction', 
   'status', 'non_qualified', 'disqualifiers', 'total_quota', 'monthly_quota', 'daily_quota', 
   'bill_rate', 'total_leads', 'daily_leads', 'daily_revenu'
);

my $database = "webclients";
my $table = "adv_daily_rev";

my $sql = "REPLACE INTO $database.$table ("      .
	         join( ',', @fields)       .
	      ") VALUES ("                 .
	         join(',', ('?')x @fields) .
	      ")";

my $noof_fields = scalar(@fields);
my $cnt_ok = my $cnt_nok = 0;
my $ttt=0;

foreach my $csv_line (@csv_content) {
   chomp($csv_line);
   $csv_line =~ s/\r$//g;          # remove DOS related crap
   $csv_line =~ s/^\"(.*)\"$/$1/;  # remove first and last ", so we can split on /","/
   
   my @vals = split(/\",\"/, $csv_line);
   if (scalar(@vals) == $noof_fields) {
       $web->{db}->do($sql,@vals);
   } else {
   	  print STDERR "Line skipped due to not enough/too many data fields.\n" .
   	               "Noof data fields = " . scalar(@vals) . " (need $noof_fields)\n" .
   	               "Errornous data line : \n<$csv_line>\n";
   	  $cnt_nok++;
   }
#   if ($dbh->errstr) {
#      print STDERR "Error msg : $dbh->errstr";
#      $cnt_nok++;
#   } else {
   	  $cnt_ok++;
#   }
}

print "<br>$cnt_ok records of $filename has been successfully uploaded.<br>" if $cnt_ok;
print "<br>$cnt_nok records of $filename were not OK. Check Apache log for details.<br>" if $cnt_nok;

}
1;
