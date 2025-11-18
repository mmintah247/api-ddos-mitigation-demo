use strict;
use warnings;

use Data::Dumper;
use JSON;
use Time::Local;
use FindBin;
use Xorux_lib;
use HostCfg;

use PowercmcDataWrapper;

my $lpar2rrd_dir;
$lpar2rrd_dir = $ENV{"INPUTDIR"} || Xorux_lib::error("INPUTDIR is not defined")     && exit;

my $webdir       = $ENV{WEBDIR} || warn "WEBDIR";

my $datadir       = "${lpar2rrd_dir}/data";
my $PEPdir        = "${datadir}/PEP2";
my $consoles_file = "${PEPdir}/console_section_id_name.json";

sub dir_treat {
  my $dir_path = shift;
  if (! -d "$dir_path") {
    mkdir( "$dir_path", 0755 ) || Xorux_lib::error("Cannot mkdir $dir_path: $!") && exit;
  }
}

dir_treat($datadir);
dir_treat($PEPdir);

my ( $proxy_url, $protocol, $username, $password, $api_port, $host);

my %host_hash = %{HostCfg::getHostConnections("IBM Power CMC")};

my @console_list = sort keys %host_hash;

print "Configured CMCs:\n";
print "---------------------------\n";

for my $conf_alias (@console_list){
  print " $conf_alias\n";
}

print "---------------------------\n";


# find hmc uuid match: CMC <-> configured HMCs
my %console_checker;
my %console_alias;
my $proxy_protocol;

for my $alias (keys %{host_hash}){
  print "\n\nProcessing CMC $alias\n";

  my %subhash = %{$host_hash{$alias}};

  $host     = $subhash{host};
  $username = $subhash{username};

  my $output = qx(\$PERL ${lpar2rrd_dir}/bin/power_cmc.pl --portalClient $host $username);
  #my $output = qx(\$PERL ${lpar2rrd_dir}/bin/power_cmc.pl --full $host $username $password $proxy_url);

  print $output;

  $console_checker{$host} = 1;
  $console_alias{$host} = $alias;

}
# CHECK: Create menu only for active consoles

my %console_id_name = ();
if ( -f "$consoles_file") {
  eval {
    %console_id_name = %{decode_json(file_to_string("$consoles_file"))};
  };
  if($@){
    # In user environments was several times encountered CMC load failure
    # caused by invalid JSON (e.g. missing end characters after/during migrations)
    # Workaround: if this happens now, then file is rewritten to {} (below)
    print STDERR "WARNING [workaround applied] : Problem while reading $consoles_file: $@\n";
    print "WARNING [workaround applied] : Problem while reading $consoles_file: $@\n";
    %console_id_name = ();
  }
  #print "\n CONSOLE ID NAME from $consoles_file\n";
  #print Dumper %console_id_name;
}

#print "\n CONSOLE CHECKER\n";
#print Dumper %console_checker;

for my $console_name (keys %console_id_name) {
  if ( ! defined $console_checker{$console_name} ) {
    delete $console_id_name{$console_name};
  }
  else {
    $console_id_name{$console_name}{Alias} = $console_alias{$console_name}; 
  }
}

# PRINT CONFIGURATION JSON
print "\n\nCONSOLE DATA: \n";

my $json      = JSON->new->utf8;
my $json_data = $json->encode(\%console_id_name);

print "\n\n $json_data \n\n";

qx(touch $consoles_file);
write_to_file($consoles_file, $json_data);

qx(\$PERL ${lpar2rrd_dir}/bin/power_cmc_genmenu.pl > ${lpar2rrd_dir}/tmp/menu_powercmc.json);

my $power = PowercmcDataWrapper::power_configured();

if ( defined $ENV{XORMON} && $ENV{XORMON} ) {
  if ($power){
    my $out = qx(\$PERL ${lpar2rrd_dir}/bin/cmc-json2db.pl);
    print " \n $out";
  }
}

#===================================================================
# CSV FILES: move to separate file
#===================================================================
for my $console_name (keys %console_id_name) {
  #-----------------------------------------------------------------
  # [1/4] GLOBAL CONSOLE OVERVIEW
  #-----------------------------------------------------------------

  my $cmc_csv = "cmc_${console_name}_global_overview.csv";
  $cmc_csv = PowercmcDataWrapper::get_csv_filename( "create", "global_overview", $console_name );

  my ( $ref_table_keys, $ref_table_header, $ref_table_body ) = PowercmcDataWrapper::table_pep_configuration($console_name);
  my $local_csv = PowercmcDataWrapper::make_csv( $ref_table_keys, $ref_table_header, $ref_table_body );
 
  my $csv_path = "$webdir/$cmc_csv";

  print "\n $csv_path \n";
  print "$local_csv\n\n";

  write_to_file($csv_path, $local_csv);

  #-----------------------------------------------------------------
  # [2/4] LOCAL CONSOLE OVERVIEW
  #-----------------------------------------------------------------

  ( $ref_table_keys, $ref_table_header, $ref_table_body ) = PowercmcDataWrapper::table_data_console_overview($console_name);

  $local_csv = PowercmcDataWrapper::make_csv( $ref_table_keys, $ref_table_header, $ref_table_body );
  
  $cmc_csv = "cmc_${console_name}_local_overview.csv";
  $cmc_csv = PowercmcDataWrapper::get_csv_filename( "create", "local_overview", $console_name );

  $csv_path = "$webdir/$cmc_csv";

  print "\n $csv_path \n";
  print "$local_csv \n\n";

  write_to_file($csv_path, $local_csv);

  #-----------------------------------------------------------------
  # [3/4] BASE CORES
  #-----------------------------------------------------------------

  ( $ref_table_keys, $ref_table_header, $ref_table_body ) = PowercmcDataWrapper::table_pep_base($console_name);
  $local_csv = PowercmcDataWrapper::make_csv( $ref_table_keys, $ref_table_header, $ref_table_body );
  $cmc_csv = PowercmcDataWrapper::get_csv_filename( "create", "base", $console_name);
  
  $csv_path = "$webdir/$cmc_csv";

  print "\n $csv_path \n";
  print "$local_csv\n\n";

  write_to_file($csv_path, $local_csv);

  #-----------------------------------------------------------------
  # [4/4] CREDIT CONSUMPTION
  #-----------------------------------------------------------------
  for my $pool_id (keys %{$console_id_name{$console_name}{Pools}} ){

    my @frequencies = ("Daily", "Weekly", "Monthly");

    for my $frequency (@frequencies) {
      my %frequency_rows = (
        "Daily"   => 14,
        "Weekly"  => 12,
        "Monthly" => 12,
      );

      my %frequency_name = (
        "Daily"   => "days",
        "Weekly"  => "weeks",
        "Monthly" => "months",
      );

      my $pool_name = $console_id_name{$console_name}{Pools}{$pool_id}{Name};

      #my $cmc_credit_csv = "cmc_${console_name}_pool_${pool_id}_credit_${frequency}.csv";
      my $cmc_credit_csv = PowercmcDataWrapper::get_csv_filename( "create", "credit", "$console_name", $pool_name, $frequency);
      
      # TABLE
      my ( $ref_table_keys, $ref_table_header, $ref_table_body, $tfoot_table, $num_of_rows ) = PowercmcDataWrapper::table_of_credits($frequency, $console_name, $pool_id, \%frequency_rows);
      $local_csv = "";
      $local_csv = PowercmcDataWrapper::make_csv( $ref_table_keys, $ref_table_header, $ref_table_body );
      
      $csv_path = "$webdir/$cmc_credit_csv";

      write_to_file($csv_path, $local_csv);
    }
  }
}

exit 0;

sub file_to_string {
  my $filename = shift;
  my $json;
  #print "$filename \n";
  open(FH, '<', $filename) or die $!;
  while(<FH>){
     $json .= $_;
  }
  #print "$filename \n";
  #print Dumper \%{decode_json($json)};
  close(FH);
  return $json;
}

sub write_to_file {
  my $file_path     = shift || "";
  my $data_to_write = shift;

  if ( $file_path ) {
    open(FH, '>', "$file_path") || Xorux_lib::error( " Can't open: $file_path : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print FH $data_to_write;
    close(FH);
  }
  else {
    # Invalid options:
    print "write_to_file has NO FILEPATH!";
  }
}

