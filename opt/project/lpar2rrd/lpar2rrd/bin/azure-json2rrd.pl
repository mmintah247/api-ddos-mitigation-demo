# azure-json2rrd.pl
# store Azure data

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;

use File::Copy;
use JSON;
use RRDp;
use HostCfg;
use AzureDataWrapper;
use AzureLoadDataModule;
use Xorux_lib qw(write_json);

use Data::Dumper;

defined $ENV{INPUTDIR} || warn( localtime() . ": INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg " . __FILE__ . ":" . __LINE__ ) && exit 1;

# data file paths
my $inputdir   = $ENV{INPUTDIR};
my $data_dir   = "$inputdir/data/Azure";
my $json_dir   = "$data_dir/json";
my $vm_dir     = "$data_dir/vm";
my $app_dir    = "$data_dir/app";
my $stor_dir   = "$data_dir/storage";
my $region_dir = "$data_dir/region";
my $tmpdir     = "$inputdir/tmp";

if ( keys %{ HostCfg::getHostConnections('Azure') } == 0 ) {
  exit(0);
}

unless ( -d $vm_dir ) {
  mkdir( "$vm_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $vm_dir: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $app_dir ) {
  mkdir( "$app_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $app_dir: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $region_dir ) {
  mkdir( "$region_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $region_dir: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $stor_dir ) {
  mkdir( "$stor_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $stor_dir: $!" . __FILE__ . ':' . __LINE__ );
}

my $rrdtool = $ENV{RRDTOOL};

my $rrd_start_time;

################################################################################

RRDp::start "$rrdtool";

my $rrdtool_version = 'Unknown';
$_ = `$rrdtool`;
if (/^RRDtool ([1-9]*\.[0-9]*(\.[0-9]*)?)/) {
  $rrdtool_version = $1;
}
print "RRDp    version: $RRDp::VERSION \n";
print "RRDtool version: $rrdtool_version\n";

my @files;
my $data;

opendir( DH, $json_dir ) || die "Could not open '$json_dir' for reading '$!'\n";
@files = grep /.*.json/, readdir DH;

#@files = glob( $json_dir . '/*' );
foreach my $file ( sort @files ) {

  my $has_failed = 0;
  my @splits     = split /_/, $file;

  print "\nFile processing              : $file, " . localtime();

  my $timestamp = my $rrd_start_time = time() - 4200;

  # read file
  my $json = '';
  if ( open( FH, '<', "$json_dir/$file" ) ) {
    while ( my $row = <FH> ) {
      chomp $row;
      $json .= $row;
    }
    close(FH);
  }
  else {
    warn( localtime() . ": Cannot open the file $file ($!)" ) && next;
    next;
  }

  # decode JSON
  eval { $data = decode_json($json); };
  if ($@) {
    my $error = $@;
    error("Empty perf file, deleting $json_dir/$file");
    unlink "$json_dir/$file";
    next;
  }
  if ( ref($data) ne "HASH" ) {
    warn( localtime() . ": Error decoding JSON in file $file: missing data" ) && next;
  }

  my %updates;
  my $rrd_filepath;

  #compute engine
  print "\nVirtual Machines             : pushing data to rrd, " . localtime();

  foreach my $vmKey ( keys %{ $data->{vm} } ) {
    $rrd_filepath = AzureDataWrapper::get_filepath_rrd( { type => 'vm', uuid => $vmKey } );
    unless ( -f $rrd_filepath ) {
      if ( AzureLoadDataModule::create_rrd_vm( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }
    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{vm}->{$vmKey} } ) {
        %updates = ( 'cpu_usage_percent' => $data->{vm}->{$vmKey}->{$timeKey}->{cpu_util}, 'disk_read_ops' => $data->{vm}->{$vmKey}->{$timeKey}->{read_ops}, 'disk_write_ops' => $data->{vm}->{$vmKey}->{$timeKey}->{write_ops}, 'disk_read_bytes' => $data->{vm}->{$vmKey}->{$timeKey}->{read_bytes}, 'disk_write_bytes' => $data->{vm}->{$vmKey}->{$timeKey}->{write_bytes}, 'network_in' => $data->{vm}->{$vmKey}->{$timeKey}->{received_bytes}, 'network_out' => $data->{vm}->{$vmKey}->{$timeKey}->{sent_bytes}, 'mem_free' => $data->{vm}->{$vmKey}->{$timeKey}->{freeMemory}, 'mem_used' => $data->{vm}->{$vmKey}->{$timeKey}->{usedMemory} );

        if ( AzureLoadDataModule::update_rrd_vm( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

  #region
  print "\nRegion                       : pushing data to rrd, " . localtime();

  foreach my $regionKey ( keys %{ $data->{region} } ) {
    $rrd_filepath = AzureDataWrapper::get_filepath_rrd( { type => 'region', uuid => $regionKey } );
    unless ( -f $rrd_filepath ) {
      if ( AzureLoadDataModule::create_rrd_region( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }
    if ( $has_failed != 1 ) {
      %updates = ( 'instances_running' => $data->{region}->{$regionKey}->{running}, 'instances_stopped' => $data->{region}->{$regionKey}->{stopped} );
      my $timestamp_region = time();

      if ( AzureLoadDataModule::update_rrd_region( $rrd_filepath, $timestamp_region, \%updates ) ) {
        $has_failed = 1;
      }
    }
  }

  #app services
  print "\nApp Services                 : pushing data to rrd, " . localtime();

  foreach my $appKey ( keys %{ $data->{appService} } ) {
    $rrd_filepath = AzureDataWrapper::get_filepath_rrd( { type => 'app', uuid => $appKey } );
    unless ( -f $rrd_filepath ) {
      if ( AzureLoadDataModule::create_rrd_app( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }
    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{appService}->{$appKey} } ) {
        %updates = ( 'cpu_time' => $data->{appService}->{$appKey}->{$timeKey}->{cpu_time}, 'requests' => $data->{appService}->{$appKey}->{$timeKey}->{requests}, 'read_bytes' => $data->{appService}->{$appKey}->{$timeKey}->{read_bytes}, 'write_bytes' => $data->{appService}->{$appKey}->{$timeKey}->{write_bytes}, 'read_ops' => $data->{appService}->{$appKey}->{$timeKey}->{read_ops}, 'write_ops' => $data->{appService}->{$appKey}->{$timeKey}->{write_ops}, 'received_bytes' => $data->{appService}->{$appKey}->{$timeKey}->{received_bytes}, 'sent_bytes' => $data->{appService}->{$appKey}->{$timeKey}->{sent_bytes}, 'http_2xx' => $data->{appService}->{$appKey}->{$timeKey}->{http_2xx}, 'http_3xx' => $data->{appService}->{$appKey}->{$timeKey}->{http_3xx}, 'http_4xx' => $data->{appService}->{$appKey}->{$timeKey}->{http_4xx}, 'http_5xx' => $data->{appService}->{$appKey}->{$timeKey}->{http_5xx}, 'response' => $data->{appService}->{$appKey}->{$timeKey}->{response}, 'connections' => $data->{appService}->{$appKey}->{$timeKey}->{connections}, 'filesystem_usage' => $data->{appService}->{$appKey}->{$timeKey}->{filesystem_usage} );

        if ( AzureLoadDataModule::update_rrd_app( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

   #app services
  print "\nStorage Accounts             : pushing data to rrd, " . localtime();
  foreach my $id ( keys %{ $data->{account} } ) {
    $rrd_filepath = AzureDataWrapper::get_filepath_rrd( { type => 'storage', uuid => $id } );
    unless ( -f $rrd_filepath ) {
      if ( AzureLoadDataModule::create_rrd_storage( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }
    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{account}->{$id} } ) {
        %updates = ( 
          'account_transactions' => $data->{account}->{$id}->{$timeKey}->{account_transactions}, 
          'account_ingress' => $data->{account}->{$id}->{$timeKey}->{account_ingress},
          'account_egress' => $data->{account}->{$id}->{$timeKey}->{account_egress},
          'account_suc_server_lat' => $data->{account}->{$id}->{$timeKey}->{account_suc_server_lat},
          'account_suc_e2e_lat' => $data->{account}->{$id}->{$timeKey}->{account_suc_e2e_lat},
          'account_availability' => $data->{account}->{$id}->{$timeKey}->{account_availability},
          'blob_transactions' => $data->{account}->{$id}->{$timeKey}->{blob_transactions}, 
          'blob_ingress' => $data->{account}->{$id}->{$timeKey}->{blob_ingress},
          'blob_egress' => $data->{account}->{$id}->{$timeKey}->{blob_egress},
          'blob_suc_server_lat' => $data->{account}->{$id}->{$timeKey}->{blob_suc_server_lat},
          'blob_suc_e2e_lat' => $data->{account}->{$id}->{$timeKey}->{blob_suc_e2e_lat},
          'blob_availability' => $data->{account}->{$id}->{$timeKey}->{blob_availability},
          'file_transactions' => $data->{account}->{$id}->{$timeKey}->{file_transactions}, 
          'file_ingress' => $data->{account}->{$id}->{$timeKey}->{file_ingress},
          'file_egress' => $data->{account}->{$id}->{$timeKey}->{file_egress},
          'file_suc_server_lat' => $data->{account}->{$id}->{$timeKey}->{file_suc_server_lat},
          'file_suc_e2e_lat' => $data->{account}->{$id}->{$timeKey}->{file_suc_e2e_lat},
          'file_availability' => $data->{account}->{$id}->{$timeKey}->{file_availability},
          'queue_transactions' => $data->{account}->{$id}->{$timeKey}->{queue_transactions}, 
          'queue_ingress' => $data->{account}->{$id}->{$timeKey}->{queue_ingress},
          'queue_egress' => $data->{account}->{$id}->{$timeKey}->{queue_egress},
          'queue_suc_server_lat' => $data->{account}->{$id}->{$timeKey}->{queue_suc_server_lat},
          'queue_suc_e2e_lat' => $data->{account}->{$id}->{$timeKey}->{queue_suc_e2e_lat},
          'queue_availability' => $data->{account}->{$id}->{$timeKey}->{queue_availability},
          'table_transactions' => $data->{account}->{$id}->{$timeKey}->{table_transactions}, 
          'table_ingress' => $data->{account}->{$id}->{$timeKey}->{table_ingress},
          'table_egress' => $data->{account}->{$id}->{$timeKey}->{table_egress},
          'table_suc_server_lat' => $data->{account}->{$id}->{$timeKey}->{table_suc_server_lat},
          'table_suc_e2e_lat' => $data->{account}->{$id}->{$timeKey}->{table_suc_e2e_lat},
          'used_capacity' => $data->{account}->{$id}->{$timeKey}->{used_capacity},
          'blob_capacity' => $data->{account}->{$id}->{$timeKey}->{blob_capacity},
          'blob_count' => $data->{account}->{$id}->{$timeKey}->{blob_count},
          'container_count' => $data->{account}->{$id}->{$timeKey}->{container_count},
          'file_capacity' => $data->{account}->{$id}->{$timeKey}->{file_capacity},
          'file_count' => $data->{account}->{$id}->{$timeKey}->{file_count},
          'file_share_count' => $data->{account}->{$id}->{$timeKey}->{file_share_count},
          'file_share_snapshot_count' => $data->{account}->{$id}->{$timeKey}->{file_share_snapshot_count},
          'file_share_snapshot_size' => $data->{account}->{$id}->{$timeKey}->{file_share_snapshot_size},
          'file_share_capacity_quota' => $data->{account}->{$id}->{$timeKey}->{file_share_capacity_quota},
          'table_capacity' => $data->{account}->{$id}->{$timeKey}->{table_capacity},
          'table_count' => $data->{account}->{$id}->{$timeKey}->{table_count},
          'table_entity_count' => $data->{account}->{$id}->{$timeKey}->{table_entity_count},
          'queue_capacity' => $data->{account}->{$id}->{$timeKey}->{queue_capacity},
          'queue_count' => $data->{account}->{$id}->{$timeKey}->{queue_count},
          'queue_message_count' => $data->{account}->{$id}->{$timeKey}->{queue_message_count},
        );

        if ( AzureLoadDataModule::update_rrd_storage( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

  unless ($has_failed) {
    backup_perf_file($file);
  }
}

################################################################################

sub backup_perf_file {

  my $src_file = shift;
  my $alias    = ( split( '_', $src_file ) )[1];
  my $source   = "$json_dir/$src_file";
  my $target1  = "$tmpdir/azure-$alias-perf-last1.json";
  my $target2  = "$tmpdir/azure-$alias-perf-last2.json";

  if ( -f $target1 ) {
    move( $target1, $target2 ) or die "error: cannot replace the old backup data file: $!";
  }
  move( $source, $target1 ) or die "error: cannot backup the data file: $!";
}

sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  print STDERR "$act_time: $text : $!\n";
  return 1;
}

print "\n";
