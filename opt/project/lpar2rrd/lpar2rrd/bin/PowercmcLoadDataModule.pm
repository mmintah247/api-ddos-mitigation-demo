package PowercmcLoadDataModule;

use strict;
use warnings;

use Data::Dumper;
use Date::Parse;
use HTTP::Request;
use JSON;
use LWP::UserAgent;
use RRDp;
use Socket;
use Time::Local;
use Xorux_lib;

my $DEBUG = 1;
my $lpar2rrd_dir;
$lpar2rrd_dir = $ENV{"INPUTDIR"} || Xorux_lib::error("INPUTDIR is not defined")     && exit;

my $rrdtool = $ENV{RRDTOOL};

#----------------------------------------------------------------------------------------------  

sub error {
  my $e_message = shift;
  my $ret = Xorux_lib::error($e_message);
}

sub print_debug_message {
  if ( $DEBUG ) {
    my $message = shift;
    my $debug_time = localtime();
    my ($sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst) = localtime();

    $debug_time = sprintf( "%4d-%02d-%02d %02d:%02d:%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );

    my $function_message = (caller(1))[3] || "MAIN";
    if ( $function_message eq "MAIN" ) {
      $debug_time = "\n$debug_time";
    }
    $function_message =~ s/main:://;

    #print ("${debug_time}: $function_message - $message \n");
  }
}

#----------------------------------------------------------------------------------------------  

sub formate2unix {
  # CMC format
  # 2023-04-27T12:00:00.000Z
  # >>
  # UNIX format
  # 1682589600
  my $time_string = shift;

  my $unix_time;

  if ($time_string =~ /(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/){
    $unix_time = timegm(0,$5,$4,$3,$2-1,$1);
  }

  return $unix_time;
}
#----------------------------------------------------------------------------------------------  

my %os_stats = (
  "Base" => {

    "BaseMemory" =>  "base_memory",

    "BaseCores" => {
      "BaseAnyOSCores"      => "base_core_any_os",
      "BaseLinuxVIOSCores"  => "base_core_linuxvios",

      "BaseRHELCoreOSCores" => "base_core_rhel_c_os",
      "BaseRHELCores"       => "base_core_rhel",
      "BaseSLESCores"       => "base_core_sles",
      "BaseAIXCores"        => "base_core_aix",
      "BaseIBMiCores"       => "base_core_imbi",
    },
  },
  "Usage" => {
    "AverageCoreUsage" => {
      "AIX"         => "core_aix",
      "IBMi"        => "core_ibmi",

      "RHELCoreOS"  => "core_rhelcoreos",
      "RHEL"        => "core_rhel",
      "SLES"        => "core_sles",
      "OtherLinux"  => "core_other_linux",
      "VIOS"        => "core_vios",

      "Total"       => "core_total",
    },
    "AverageMemoryUsage" => {
      "AIX"             => "mem_aix",
      "IBMi"            => "mem_ibmi",

      "RHELCoreOS"      => "mem_rhelcoreos",
      "RHEL"            => "mem_rhel",
      "SLES"            => "mem_sles",
      "OtherLinux"      => "mem_other_linux",
      "VIOS"            => "mem_vios",

      "SystemOther"     => "mem_system_other",

      "Total"           => "mem_total",
    },
  }

);

sub time2unix {
  # CMC format
  # 2023-04-27T12:00:00.000Z  
  # >> 
  # UNIX format
  # 1682589600
  my $time_string = shift;
  use Time::Local;
  #print_debug_message("$time_string");

  my $unix_time;
  
  if ($time_string =~ /(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/){
    $unix_time = timegm(0,$5,$4,$3,$2-1,$1);
  }
  
  #$unix_time += 1123200 - 43200 + 86400 ;
  return $unix_time;
}


sub write_to_file {
  my $file_path     = shift;
  my $data_to_write = shift;
  
  if (! -f "$file_path") {
    qx(touch $file_path);
  }

  my $local_t = localtime();
  #print_debug_message("WRITING IN FILE: ${file_path} ");

  open(FH, '>', "$file_path") || Xorux_lib::error( " Can't open: $file_path : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH $data_to_write;
  close(FH);
}

# Next part of code was prepared to collect data directly from HMC
#-----------------------------------------------------------------------------------
# :6: POWER HMC SERVER DATA
#-----------------------------------------------------------------------------------
# THIS SECTION MUST BE LAST IN COLLECTING ORDER
#-----------------------------------------------------------------------------------
#use Power_cmc_Power_service;
#use HostCfg;
#
#my %host_hash = %{HostCfg::getHostConnections("IBM Power Systems")};
#
#my ( $protocol, $username, $password, $api_port, $host);
#
## Per HMC: collect data from all servers
## hmc_
## per server in cmc: cmc_server matches hmc_server => save
#
#my %uvmid_host;
#my %alias_uvmid;
#
#for my $alias (keys %{host_hash}){
#  my %subhash = %{$host_hash{$alias}};
#
#  $protocol = $subhash{proto};
#  $username = $subhash{username};
#  $host     = $subhash{host};
#  $api_port = $subhash{api_port};
#
#  $password = $subhash{password};
#  print "\n HMC INFORMATION CALL \n";
#  my @hmc_console_arr = @{Power_cmc_Power_service::information_call($protocol, $host, $api_port, $username, $password)};
#  my %hmc_console = %hmc_console_arr[0];
#
#  #print Dumper %hmc_console;
#  #print keys %hmc_console; 
#  my $UVMID = $hmc_console{0}{UVMID}{'content'} || "";
#  $alias_uvmid{$alias}=$UVMID;
#  print "\n------------------------UVMID---------------------------\n$UVMID\n"; 
#}
#
##print Dumper %alias_uvmid;
## what to do about dual hmc?
#for my $hmc_uuid (keys %{$data{HMCs}}){
#  my $UVMID = $data{HMCs}{$hmc_uuid}{Configuration}{UVMID};
#  my $hmc_existence_check = 0;
#  
#  for my $alias (keys %{host_hash}){
#    if (defined ($UVMID) && $alias_uvmid{$alias} eq $UVMID){
#      my %subhash = %{$host_hash{$alias}};
#  
#      $protocol = $subhash{proto};
#      $username = $subhash{username};
#      $host     = $subhash{host};
#      $api_port = $subhash{api_port};
#  
#      $password = $subhash{password};
#  
#      $hmc_existence_check = 1;
#      
#    }
#  }
#  
#  # load data from all servers on HMC
#  if (defined ($UVMID) && $UVMID){
#    # Use HMC connection data and desired metrics list
#    # returns 
#    # %collection: (*UUID => *MetricName => value)
#    print "\n DATA CALL \n";
#    $data{HMCs}{$hmc_uuid}{Configuration}{host} = $host;
#    
#    my ($collection_ref, $collection_timestamped_ref) = Power_cmc_Power_service::data_call($protocol, $host, $api_port, $username, $password);
#    
#    my %collection = %{$collection_ref};
#    my %collection_timestamped = %{$collection_timestamped_ref};
#      
#    #print "\n-------------------------------------------------------------------------\n";
#    #print Dumper %collection;
#    #print "\n-------------------------------------------------------------------------\n";
#    #print Dumper %collection_timestamped;
#    #print "\n-------------------------------------------------------------------------\n";
#    
#    for my $server_uuid (keys %{$data{Systems}}){
#      if (defined $collection{$server_uuid}){
#        for my $MetricName (keys %{$collection{$server_uuid}}){
#          $data{Systems}{$server_uuid}{Metrics}{$MetricName} = $collection{$server_uuid}{$MetricName};
#        }
#      }
#    }
#    
#    for my $server_uuid (keys %{$data{Systems}}){
#      for my $timestamp (keys %{$collection_timestamped{$server_uuid}}){
#        if (defined $collection_timestamped{$server_uuid}{$timestamp}){
#          my @metrics = ('proc_available', 'proc_installed', 'mem_available', 'mem_installed', 'base_anyoscores');
#          for my $metric (@metrics){
#            $data_hmc{Systems}{$server_uuid}{Metrics}{$timestamp}{$metric}  =  $data{Systems}{$server_uuid}{Configuration}{$metric};
#          }
#          for my $MetricName (keys %{$collection_timestamped{$server_uuid}{$timestamp}}){
#            $data_hmc{Systems}{$server_uuid}{Metrics}{$timestamp}{$MetricName} = $collection_timestamped{$server_uuid}{$timestamp}{$MetricName};
#          }
#        }
#      }
#    }
#
#  }
#  else{
#    my $name_of_checked = $data{HMCs}{$hmc_uuid}{Name};
#    print "HMC ${name_of_checked} (UUID: $hmc_uuid) is not in hosts.cfg.";
#  }
#}
#

1;
