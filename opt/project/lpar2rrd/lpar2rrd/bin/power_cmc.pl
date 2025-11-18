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

use PowercmcDataWrapper;
use PowercmcLoadDataModule;

use HostCfg;


my $DEBUG           = 1; # triggers function print_debug_message
my $SAVE_RESPONSES  = 1; # triggers saving of HTTP response data

my $REAL_DATA       = 1; # development purposes: simulate user environment
# $REAL_DATA evaluated as False means:
# - reading JSON files instead of HTTP requests
# - creation of timeshift to simulate activity

# Next part is customizable delay interval. API might return doubled values.
# affects usage/pools and usage/tags + credit usage table (day/week/month)
my $collection_delay  = $ENV{'CMC_COLLECTION_DELAY'}  || 1800;
my $USE_V2            = $ENV{'CMC_USE_V2'}            || 0; # decision for api endpoint and collecting subroutine
# v2 compatibility is prepared only for usage/tags

my $lpar2rrd_dir  = $ENV{'INPUTDIR'} || Xorux_lib::error("INPUTDIR is not defined")     && exit;
my $rrdtool       = $ENV{'RRDTOOL'};

my $LWP_VERSION = $LWP::VERSION || "unknown";
print "LWP::VERSION = $LWP_VERSION\n";

#==========================================================================================
# TODO:
# Move parts of code to LoadDataModule

# TODO: possible enhancements:
# Preload data, solve undefs, use max time range limit of API
# check if all RRD metrics are used while graphing

# DONE:
# separate requests
# More informative output message
# save result of all requests for development purposes

#==========================================================================================
# KEYWORDS: Power Enterprise Pool, Cloud Management Console, Hardware Management Console, 
#           Tag, System, Partition
#==========================================================================================
# CODE STRUCTURE
#==========================================================================================
# CONNECTION SPECIFICATIONS:
# REQUEST
# TIME HANDLING
#-----------------------------------------------------------------------------------
# INVENTORY TAGS
## Tag is user specified group of VIOSes/Managed Systems/HMCs/Partitions
## Tag creation: https://ibmcmc.zendesk.com/hc/en-us/articles/115001423214-Manage-Tags
## First order specifications: ID, Name, Systems, Partitions

# USAGE POOLS
## Specifications: PoolID, PoolName (per console) + CurrentRemainingCreditBalance
## Metrics: CoreMinute, MemoryMinute,
##          CoreMeteredMinutes, MemoryMeteredMinutes,
##          CoreMeteredCredits, MemoryMeteredCredits

# USAGE TAGS
# MANAGED SYSTEMS
#-----------------------------------------------------------------------------------
# SAVE DATA
# READ OR CREATE ENVIRONMENTAL JSON (STRUCTURE: CMC -> POOL_ID -> POOL_NAME)
# SERVER DATA
# RRD CREATE AND UPDATE
#==========================================================================================

my $ID;
my $UUID;
my $loc_query;

#-----------------------------------------------------------------------------------
# CONNECTION SPECIFICATIONS:
#-----------------------------------------------------------------------------------
# Script is executable from hand
#-----------------------------------------------------------------------------------

my $portal_url;
my $CMC_client_id;
my $CMC_client_secret;
my $proxy;
my $proxy_proto;

my $console_name;

my $help_string = "";
$help_string .= "Call with parameters\n";
$help_string .= "--full portal-URL CMC-client-id CMC-client-secret [proxy] \n";
$help_string .= " NOTE: optional proxy URL must be in format: http://host:port \n\n";

if (! defined $ARGV[0]) {
  print "No argument received!\n";
  print $help_string;
  exit;
}

if ($ARGV[0] eq '-h'){
  print $help_string;
  exit;
}

if ($ARGV[0] eq '--full'){
  # --full <portal-URL> <CMC-client-id> <CMC-client-secret> <proxy>

  $portal_url        = $ARGV[1] || "";
  $CMC_client_id     = $ARGV[2] || "";
  $CMC_client_secret = $ARGV[3] || "";
  $proxy             = $ARGV[4] || "";

}
elsif ($ARGV[0] eq '--portalClient'){
  # --portalClient <portal-URL> <CMC-client-id>

  # NOTE: data are saved per portal URL
  # This solution expects reasonable user
  # (this method is similar to parameter passing in HMC scripts)
  my %host_hash = %{HostCfg::getHostConnections("IBM Power CMC")};

  my $received_host    = $ARGV[1] || "";
  my $received_user    = $ARGV[2] || "";

  my $hostcfg_found = 0;
  my %subhash = ();

  foreach my $alias ( keys %host_hash ) {
    if ( $received_host eq  $host_hash{$alias}{host} && $received_user eq $host_hash{$alias}{username} ) {

      print_debug_message("Received host $received_host - CMC $alias");

      $hostcfg_found = 1;
      %subhash = %{$host_hash{$alias}};

      last;
    }
  }

  if ( ! $hostcfg_found ) {
    print "Hostcfg does not include CMC with host $received_host and user $received_user \n";
    exit;
  }

  $portal_url         = $subhash{host};
  $CMC_client_id      = $subhash{username};
  $CMC_client_secret  = $subhash{password};

  $proxy = "";
  if ( defined $subhash{proxy_url} && $subhash{proxy_url} && defined $subhash{proto} && $subhash{proto} ) {
    $proxy = "$subhash{proto}".'://'."$subhash{proxy_url}";
    $proxy_proto = "$subhash{proto}";
  }

}

#print "_____ RECEIVED: host: $portal_url username: $CMC_client_id proxy: $proxy \n" ;
$console_name = $portal_url;

print("\nCOLLECTION DELAY: ${collection_delay}\n");

#-----------------------------------------------------------------------------------

my $datadir               = "${lpar2rrd_dir}/data";
my $PEPdir                = "${datadir}/PEP2";
my $console_dir           = "${lpar2rrd_dir}/data/PEP2/$console_name";
my $consoles_file         = "${PEPdir}/console_section_id_name.json";
my $console_history_file  = "${console_dir}/history.json";

my $development_data_dir = "${console_dir}"; # development: read response JSON from here
# Testing file: purpose: minimize error during high frequency of changes sent directly to users,
#                        while keeping the ability to load saved responses in dev environment
# CMC-${console_name}-${file_name}
my $testing_file = "$development_data_dir/CMC-${console_name}-inventory_tags.json";

if ( -f "$testing_file") {
  $REAL_DATA = 0;
}

if ($proxy eq "-"){
  $proxy = "";
}

# script.pl test - - proxy test_query
if ($ARGV[0] eq "test"){
  my $testing_query     = defined $ARGV[4] ? $ARGV[4] : "";

  if ($testing_query){
    my $test_result = general_hash_request("GET", $testing_query);
  }
  else {
    print "Testing query not specified!\n";
  }
  exit;
}

if ($portal_url eq ""){
  print "Missing portal url!\n";
  print "$help_string";
  exit;
} elsif ($CMC_client_id eq ""){
  print "Missing cmc client ID!\n";
  print "$help_string";
  exit;
} elsif ($CMC_client_secret eq ""){
  print "Missing CMC client secret as an argument\n";
  print "$help_string";
  exit;
} elsif ($proxy eq ""){
  print "WARNING: Proxy was not specified.\n";
#  print "$help_string";
}

#-----------------------------------------------------------------------------------
# API rate limit
#-----------------------------------------------------------------------------------
# As script collects v2 samples, it is important to take into account CMC API request limit.
# NOTE: one user pointed out, that perf request took more than a minute.
my $request_cycle_counter = 1;

sub check_limit_to_sleep {

  print_debug_message("Checking API limit [${request_cycle_counter}/10] ");

  $request_cycle_counter++;

  my $possible_waiting_interval = 1;

  if ( $request_cycle_counter >= 10 ) {
    print_debug_message( "API limit reached - waiting ${possible_waiting_interval}s");
    sleep($possible_waiting_interval);

    $request_cycle_counter = 1;
  }

}

#-----------------------------------------------------------------------------------
# REQUEST
#
# NOTE:
# All API calls are automatically rate limited to a maximum of 10 calls per second.
#-----------------------------------------------------------------------------------

sub general_hash_request {
  my $method  = shift;
  my $query   = shift;

  print_debug_message("$method $query");

  my %data_ret = ();

  eval {
    %data_ret = general_hash_request_x($method, $query, "A");

    if ( ! %data_ret ) {
      print_debug_message("No data, next call");
      eval {
        %data_ret = general_hash_request_x($method, $query, "B");
      };
      if ($@) {
        print_debug_message("ERROR B: $@");
      }
    }
  };
  if ($@) {
    print_debug_message("ERROR A: $@");
    print_debug_message("Trying second method...");
    eval {
      %data_ret = general_hash_request_x($method, $query, "B");
    };
    if ($@) {
      print_debug_message("Second method does not work.");
    }
  }

  if ( ! %data_ret ) {
    print_debug_message("No data");
  }

  return %data_ret;
}

sub general_hash_request_x {
  my $method  = shift;
  my $url     = shift;

  my $proxy_method = shift || "A";

  my %decoded_json;

  # Api rate limit
  check_limit_to_sleep();

  print_debug_message("$method $url");

  # HTTP request (user) OR read saved JSON (development)
  if ( $REAL_DATA ) {

    my $user_agent    = LWP::UserAgent->new( 
      ssl_opts => {
        SSL_cipher_list => 'DEFAULT:!DH',
        verify_hostname => 0,
        SSL_verify_mode => 0
      }
    );

    print "START PROXY PART \n";

    #
    # There must be 2 calls:
    # old proxy || new proxy
    #
    # proxy worked with:
    #   $user_agent->proxy( ['http', 'https', 'ftp'] => $proxy );
    # in case of failure of previous load (probably different lib version [?])
    # works this kind of load:
    #   $user_agent->proxy('https', "$proxy");
    # second type resulted in timeouts later (in the same environment did the first work),
    # so it should be used as backup, because first method can result in failure
    # Failure might not happen during $user_agent->proxy()
    # Listing each LWP version is not good solution..
    #

    if ( $proxy ){ # GLOBAL variable $proxy
      # expected proxy format: http://host:port

      if ( $proxy_method eq "A") {
        print_debug_message("Method A");
        $user_agent->proxy( ['http', 'https', 'ftp'] => $proxy );
      }
      else {
        print_debug_message("Method B");
        ## PROXY "BACKUP" - use different way to send proxy proto
        if ( $proxy =~ /https\:\/\// ) {
          $user_agent->proxy('https', "$proxy");
        }
        elsif ( $proxy =~ /http\:\/\// ) {
          $user_agent->proxy('http', "$proxy");
        }
      }

    }

    print "END PROXY PART \n";

    my $request = HTTP::Request->new( $method => $url );

    $request->header( 'X-CMC-Client-Id'     => "$CMC_client_id" );
    $request->header( 'X-CMC-Client-Secret' => "$CMC_client_secret" );
    $request->header( 'Accept'              => 'application/json' );

    my $result = $user_agent->request($request);

    eval{
      %decoded_json = %{decode_json($result->{'_content'})};
    };
    if($@){
      my $error_message = "";
      $error_message .= "PROBLEM OCCURED during decode_json HASH with url $url!" ;
      $error_message .= "\n --- RESULT->_content --- \n $result->{'_content'} \n";
      print "$error_message";
      print Dumper $result->{'_headers'};

      error( "$error_message ");
      return ()
    }

  }
  else {
    # DEVELOPMENT: LOAD JSON DATA
    my $file_name = match_url_to_file($url); # returns basic filename (e.g. usage_tags.json)

    my $path_to_read = "${development_data_dir}/CMC-${console_name}-${file_name}";

    if ( ! -f $path_to_read ) {
      # in case of older dataset
      $path_to_read = "${development_data_dir}/${file_name}";
    }

    eval{
      %decoded_json = %{decode_json(file_to_string($path_to_read))};
    };

    if($@){
      # Development print only
      print "DEVELOPMENT ONLY: UNKNOWN file::>$file_name<::elif\n";
      error( "DEVELOPMENT ONLY: UNKNOWN file::>$file_name<::elif");
      %decoded_json = ();
    }

  }

  if ( $SAVE_RESPONSES ) {
    # DEVELOPMENT: SAVE RESPONSE JSON TO TMP
    my $file_name = match_url_to_file($url); # returns basic filename (e.g. usage_tags.json)

    my $response_path = "$lpar2rrd_dir/tmp/CMC-${console_name}-${file_name}";

    print_debug_message("Saving response.");

    my $json      = JSON->new->utf8;
    my $json_data = $json->encode(\%decoded_json);
    write_to_file($response_path, $json_data);
  }

  return %decoded_json;
}

#-----------------------------------------------------------------------------------
# DEBUG AND ERROR
#-----------------------------------------------------------------------------------
sub print_debug_message {
  # FORMATE:
  # time - triggering function - message
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

    print ("${debug_time}: $function_message - $message \n");
  }
}

sub error {
  my $e_message = shift;
  my $ret = Xorux_lib::error($e_message);
}
#-----------------------------------------------------------------------------------
# TIME HANDLING
# OUT: $StartTS, $EndTS
#-----------------------------------------------------------------------------------
my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst );

my $use_time = time();
my $time = $use_time;
my $Frequency = "Minute";

my $interval          = 2600;

my $oldest_timestamp = $use_time - 600000; # used for rrd creation

my $start_time = $use_time - $interval - $collection_delay;
( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($start_time);

my $StartTS = sprintf( "%4d-%02d-%02dT%02d:%02d:00Z", $year + 1900, $month + 1, $day, $hour, $min );

my $end_time = $use_time - $collection_delay;
( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($end_time);

my $EndTS = sprintf( "%4d-%02d-%02dT%02d:%02d:00Z", $year + 1900, $month + 1, $day, $hour, $min );

sub time2unix {
  PowercmcLoadDataModule::time2unix(@_);
}

sub timify_query {
  my $base_url  = shift;
  my $frequency = shift || "Minute";

  $base_url .= "?EndTS=${EndTS}&Frequency=${frequency}&StartTS=${StartTS}";

  return $base_url;
}

# general directory treatment procedure
sub dir_treat {
  my $dir_path = shift;

  print_debug_message("CHECKING DIRECTORY: ${dir_path} ");

  if (! -d "$dir_path") {
    print_debug_message("MKDIR: ${dir_path} ");
    mkdir( "$dir_path", 0755 ) || Xorux_lib::error("Cannot mkdir $dir_path: $!") && exit;
  }
}

sub write_to_file {
  print_debug_message("WRITING IN FILE: $_[0] ");
  PowercmcLoadDataModule::write_to_file(@_);
}

# general subroutine to load files
sub file_to_string {
  my $filename = shift;
  my $json;

  print_debug_message("READING FILE: ${filename} ");
  open(FH, '<', $filename) || Xorux_lib::error( " Can't open: $filename : $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  while(<FH>){
     $json .= $_;
  }

  close(FH);
  return $json;
}

sub match_url_to_file {
  my $url_called = shift;

  my %translation_marks = (
    'api/public/v1/ep/inventory/tags'               => 'inventory_tags',
    'api/public/v1/ep/usage/pools'                  => 'usage_pools',
    'api/public/v1/ep/usage/tags'                   => 'usage_tags',
    'api/public/v1/inventory/cmc/ManagedSystem'     => 'managed_system',
    'api/public/v1/inventory/cmc/ManagementConsole' => 'management_console',
    'api/public/v1/cm/usage/ManagedSystem'          => 'cm_managed_system',

    'api/public/v2/ep/inventory/tags'               => 'v2_inventory_tags',
    'api/public/v2/ep/usage/pools'                  => 'v2_usage_pools',
    'api/public/v2/ep/usage/tags'                   => 'v2_usage_tags',
    'api/public/v2/inventory/cmc/ManagedSystem'     => 'v2_managed_system',
    'api/public/v2/inventory/cmc/ManagementConsole' => 'v2_management_console',
    'api/public/v2/cm/usage/ManagedSystem'          => 'v2_cm_managed_system',
  );
  
  my $file_name;
  
  for my $mark ( keys %translation_marks ) {
    if ( $url_called =~ /$mark/ ){
      $file_name = $translation_marks{$mark};
      last;
    }
  }

  # Minute is used as default = .json
  my %frequency_marks = (
    '=Daily'   => '_daily',
    '=Weekly'  => '_weekly',
    '=Monthly' => '_monthly',
  );

  for my $mark ( keys %frequency_marks ) {
    if ( $url_called =~ /$mark/ ){
      $file_name .= $frequency_marks{$mark};
      last;
    }
  }

  $file_name .= '.json';
  
  return $file_name;
}
#-----------------------------------------------------------------------------------
# COLLECT CONSOLE DATA
#-----------------------------------------------------------------------------------
# MAIN information store, scheme below
# Most important info:
#   CMC structure
#   UUIDs + Names
#   Configuration data
# Make sure to hold only systems in pools - use tags inventory to get this connection.
# Connection is not in other responses!
# Look more into:
#   'api/public/v1/cm/usage/ManagedSystem'
#   'api/public/v1/inventory/cmc/ManagedSystem'
# these endpoints have all systems. BEWARE of loading them all into data!
my %data;

# %data_timed stores performance stats of Systems and Pools 
my %data_timed;

# %os_stats stores Systems performance data (mainly OS/cmm)
my %os_stats;

#---------------------------------------------------------------------------------------------------------
# scheme of configuration hash %data
#---------------------------------------------------------------------------------------------------------
#              => Pools       => *PoolID        => Name           => value
#                                               => Configuration  => *Name => value
#                                               => Systems        => *UUID => Name         => value
#                                               => Partitions     => *UUID => Name         => value
#
#              => Tags        => *TagID         => Name           => value
#                                               => Configuration  => *Name => value
#                                               => Systems        => *UUID => Name => value
#                                               => Partitions     => *UUID => Name => value
#
#              => Servers     => *ServerUUID    => Name           => value
#                                               => Configuration  => *Name => value
#                                               => Pools          => *PoolID       => Name => value 
#
#              => Partitions  => *PartitionUUID => Name           => value
#                                               => Configuration  => *Name => value
#                                               => Pools          => *PoolID       => Name => value  
#
#              => HMCs        => *HMCUUID       => Name           => value
#                                               => Configuration  => *Name => value
#                                               => Systems        => *UUID => Name => value
#                                               => Partitions     => *UUID => Name => value
#---------------------------------------------------------------------------------------------------------

#---------------------------------------------------------------------------------------------------------
# scheme of performance hash %data_timed
#---------------------------------------------------------------------------------------------------------
#              => Pools       => *PoolID        => Metrics        => *time   => *MetricName  => value
#
#              => Servers     => *ServerUUID    => Metrics        => *time   => *MetricName  => value     
#---------------------------------------------------------------------------------------------------------

#---------------------------------------------------------------------------------------------------------
# Wider - DATA SCHEMA:
#---------------------------------------------------------------------------------------------------------
# Console      => Pools       => *PoolID        => Name           => value
#                                               => Configuration  => *Name => value
#                                               => Metrics        => *time => *MetricName  => value
#                                               => Systems        => *UUID => Name         => value
#                                               => Partitions     => *UUID => Name         => value
#
#              => Tags        => *TagID         => Name           => value
#                                               => Configuration  => *Name => value
#                                               => Systems        => *UUID => Name => value
#                                               => Partitions     => *UUID => Name => value
#
#              => Servers     => *ServerUUID    => Name           => value
#                                               => Configuration  => *Name => value
#                                               => Metrics        => *time   => *MetricName  => value
#                                               => Pools          => *PoolID => Name         => value 
#
#              => Partitions  => *PartitionUUID => Name           => value
#                                               => Configuration  => *Name => value
#                                               => Metrics        => *Name => value
#                                               => Pools          => *PoolID 
#
#              => HMCs        => *HMCUUID       => Name           => value
#                                               => Configuration  => *Name => value
#                                               => Systems        => *UUID => Name => value
#                                               => Partitions     => *UUID => Name => value
#---------------------------------------------------------------------------------------------------------
my %translate_to_reserve = (
  "base_core_any_os"    =>  "reserve_3",  
  "base_core_linuxvios" =>  "reserve6",
  "base_core_rhcos"     =>  "reserve8",
  "base_core_rhel"      =>  "reserve_5",
  "base_core_sles"      =>  "reserve10",
  "base_core_aix"       =>  "reserve2",
  "base_core_imbi"      =>  "reserve4",
);

%os_stats = (
  "Base" => {

    "BaseMemory" =>  "base_memory",

    "BaseCores" => {
      "BaseAnyOSCores"      => "base_core_any_os",
      "BaseLinuxVIOSCores"  => "base_core_linuxvios",

      "BaseRHELCoreOSCores" => "base_core_rhcos",
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

my $pool_name;
my $data_ref = \%data;
my $os_stats_ref = \%os_stats;
my %os_usage_per_system = ();
my ($data_timed_ref, $os_usage_per_system_ref);

#-----------------------------------------------------------------------------------
# :1: INVENTORY TAGS
#-----------------------------------------------------------------------------------
# GET /ep/inventory/tags 
# https://<portal-url>/api/public/v1/ep/inventory/tags/{tag_name}
#-----------------------------------------------------------------------------------
print_debug_message("PROCESSING INVENTORY TAGS");

my $url_inventory = "https://${portal_url}/api/public/v1/ep/inventory/tags";

my %inventory_tags = general_hash_request("GET", $url_inventory);

($data_ref) = process_inventory_tags($data_ref, $os_stats_ref, \%inventory_tags, $url_inventory);

%inventory_tags = ();

%data = %{$data_ref};

#-----------------------------------------------------------------------------------
# :2: USAGE POOLS
#-----------------------------------------------------------------------------------
# GET ep/usage/pools 
# https://<portal-url>/api/public/v1/ep/usage/pools/{pool_name}
#   GET POOL NAMES: The available pool names are returned if you do not specify a pool name. 
#-----------------------------------------------------------------------------------
#  QUERY PARAMETERS: 
# StartTS: yyyy-MM-ddTHH:mm:ssZ 
# EndTS: yyyy-MM-ddTHH:mm:ssZ
# Frequency:  Minute  Hourly  Daily  Weekly  Monthly  	
#-----------------------------------------------------------------------------------
print_debug_message("PROCESSING USAGE POOLS");

my $url_usage_pools = "https://${portal_url}/api/public/v1/ep/usage/pools";

my %usage_pools = general_hash_request("GET", timify_query($url_usage_pools));

process_usage_pools();

check_tagging();

#-----------------------------------------------------------------------------------
# :3: USAGE TAGS
#-----------------------------------------------------------------------------------
# GET ep/usage/tags 
# https://<portal-url>/api/public/v1/ep/usage/tags/{tag_name}
#-----------------------------------------------------------------------------------
#  QUERY PARAMETERS: 
# StartTS: yyyy-MM-ddTHH:mm:ssZ 
# EndTS: yyyy-MM-ddTHH:mm:ssZ
# Frequency:  Minute  Hourly  Daily  Weekly  Monthly  	
#-----------------------------------------------------------------------------------
print_debug_message("PROCESSING USAGE TAGS");

my $url_usage_tags = "https://${portal_url}/api/public/v1/ep/usage/tags";

if ( $USE_V2 ) {
  $url_usage_tags = "https://${portal_url}/api/public/v2/ep/usage/tags";
  # TODO: IBMi = sum(IBMiP30, IBMiP20, IBMiP10)
}

my %usage_tags = general_hash_request("GET", timify_query($url_usage_tags));

($data_timed_ref, $os_usage_per_system_ref, $data_ref) = process_usage_tags(\%os_usage_per_system, \%data_timed, \%data, \%usage_tags, $url_usage_tags);

%usage_tags = ();

# ! CHANGE THAT:
%data                 = %{$data_ref};
%data_timed           = %{$data_timed_ref};
%os_usage_per_system  = %{$os_usage_per_system_ref};

#-----------------------------------------------------------------------------------
# :4: MANAGED SYSTEM
#-----------------------------------------------------------------------------------
print_debug_message("PROCESSING MANAGED SYSTEM");

my $url_managed_system = "https://${portal_url}/api/public/v1/inventory/cmc/ManagedSystem";

my %managed_hmc_data = general_hash_request("GET", $url_managed_system);

process_managed_system_data();

#-----------------------------------------------------------------------------------
# :5: MANAGEMENT CONSOLE
#-----------------------------------------------------------------------------------
print_debug_message("PROCESSING MANAGEMENT CONSOLE");

my $url_management_console = "https://${portal_url}/api/public/v1/inventory/cmc/ManagementConsole";
my %management_console_data;

%managed_hmc_data = general_hash_request("GET", $url_management_console);

process_management_console_data();

#-----------------------------------------------------------------------------------
# :6: CREDIT USAGE
#-----------------------------------------------------------------------------------
print_debug_message("PROCESSING CREDIT USAGE");

collect_full_range_credits();

#=========================================================================================
# SAVE DATA
#=========================================================================================
# DIRECTORIES
#-----------------------------------------------------------------------------------
print_debug_message("DIRECTORIES");

dir_treat($datadir);
dir_treat($PEPdir);
dir_treat($console_dir);

#---------------------------------------------------------------------------------------------------------
# READ OR CREATE ENVIRONMENTAL JSON (STRUCTURE: CMC -> POOL_ID -> POOL_NAME)
#---------------------------------------------------------------------------------------------------------
print_debug_message("CONSOLES JSON");
my %console_id_name;

# add file_treat?
if ( -f "$consoles_file") {
  %console_id_name = %{decode_json(file_to_string("$consoles_file"))};
  # save instead of deletion?
  delete $console_id_name{$console_name};
}

my %console_history;
if ( -f "$console_history_file") {
  %console_history = %{decode_json(file_to_string("$console_history_file"))};
}

round_and_multiply_data();

#-------------------------------------------------------------------------------------------------------------
# CONSOLE DATA FILE:
#-------------------------------------------------------------------------------------------------------------
for my $section (sort keys %data){
  # Pools, Tags, Systems, Partitions
  for my $id (keys %{$data{$section}}){

    $console_id_name{$console_name}{$section}{$id}{Name} = $data{$section}{$id}{Name};

    for my $conf_name (keys %{$data{$section}{$id}{Configuration}}){
      $console_id_name{$console_name}{$section}{$id}{Configuration}{$conf_name} = $data{$section}{$id}{Configuration}{$conf_name};
    }

    # ADDITIONAL STRUCTURE - Topology
    for my $group ('Systems', 'Partitions', 'Tags', 'Pools', 'HMCs'){
      if ($section ne $group){
        for my $managed_system (keys %{$data{$section}{$id}{$group}}){
          $console_id_name{$console_name}{$section}{$id}{$group}{$managed_system}=$data{$section}{$id}{$group}{$managed_system}
        }
      }
    }

  }
}

# CONSOLE HISTORY FILE
# TODO: extend historical data set
# data/PEP2/<console>/history.json
for my $id (keys %{$data{"Pools"}}){
  my @sys_list = keys %{$data{"Pools"}{$id}{Systems}};

  # Rename into account
  for my $uuid (@sys_list){
    $console_history{"Pools"}{$id}{Systems}{$uuid} = $data{Systems}{$uuid}{Name};
    $console_history{"Pools"}{$id}{Name} = $data{Pools}{$id}{Name};
  }
}

for my $uuid (keys %{$data{"Systems"}}){
  $console_history{"Systems"}{$uuid} = $data{Systems}{$uuid}{Name};
}


sub collect_full_range_credits {
  my $url_usage_pools = "https://${portal_url}/api/public/v1/ep/usage/pools";

  my %usage_pools;
  #my @frequencies = ("Minute", "Hourly", "Daily", "Weekly", "Monthly");
  my @frequencies = ("Daily", "Weekly", "Monthly");


  for my $frequency (@frequencies) {
    my $query = time_budget_query($use_time, $frequency);
    my $timed_url = "${url_usage_pools}?${query}";

    %usage_pools = general_hash_request("GET", $timed_url);

    make_pool_budget_data($console_name, \%usage_pools, $frequency);
  }

}

# possible sub: hash to json to file
my $json      = JSON->new->utf8;
my $json_data = $json->encode(\%console_id_name);
write_to_file($consoles_file, $json_data);

my $json_h      = JSON->new->utf8;
my $json_data_h = $json->encode(\%console_history);
write_to_file($console_history_file, $json_data_h);

# Both variables are development only
my $last_timestamp = 0;
my $time_shift = 0;

#=========================================================================================
# CREATE AND LOAD RRD
#=========================================================================================
print_debug_message("RRD: CREATE AND UPDATE");

# sets header for RRD
my %govern_timestamped_data = (
  'Pools' => [
    'cm_aix', 'cm_otherlinux',
    'cm_sles', 'cm_vios', 'cm_ibmi',
    'cm_rhel', 'cm_rhelcoreos', 'cm_total',

    'cmc_aix', 'cmc_linuxvios', 'cmc_anyos',
    'cmc_sles', 'cmc_vios', 'cmc_ibmi',
    'cmc_rhel', 'cmc_rhelcoreos', 'cmc_total',

    'cmm_aix', 'cmm_linuxvios', 'cmm_anyos',
    'cmm_sles', 'cmm_vios', 'cmm_ibmi',
    'cmm_rhel', 'cmm_rhelcoreos', 'cmm_total',

    'mm_aix', 'mm_otherlinux',
    'mm_sles', 'mm_vios', 'mm_ibmi',
    'mm_rhel', 'mm_rhelcoreos', 'mm_total',

    'mm_systemother',
    'mm_credits', 'mm_minutes',

    'reserve_1', 'reserve2',
    'reserve_3', 'reserve4',
    'reserve_5', 'reserve6',
    'reserve_7', 'reserve8',
    'reserve_9', 'reserve10',

  ],
  'Systems' => [
    'proc_available', 'proc_installed',
    'mem_available', 'mem_installed',

    'base_anyoscores',

    'utilizedProcUnits', 'totalProcUnits',
  ]
);

# sets header for RRD
my %govern_server_os = (
  'Systems' => [
    "base_memory",

    "base_core_any_os", "base_core_linuxvios",

    "base_core_rhel", "base_core_rhcos",
    "base_core_sles", "base_core_aix",
    "base_core_imbi",

    "core_aix", "core_ibmi",

    "core_rhelcoreos", "core_rhel",
    "core_sles", "core_other_linux",
    "core_vios",

    "core_total",

    "mem_aix", "mem_ibmi",

    "mem_rhelcoreos", "mem_rhel",
    "mem_sles", "mem_other_linux",
    "mem_vios",

    "mem_system_other",

    "mem_total",

    'res_1', 'res_2',
    'res_3', 'res_4',
    'res_5', 'res_6',
    'res_7', 'res_8',
    'res_9', 'res_10',
  ]
);
#-----------------------------------------------------------------------------------
# DEVELOPMENT: In case of unreal data make timeshift
# Timeshift is used to periodically load data from sample
#-----------------------------------------------------------------------------------
if (! $REAL_DATA){

  for my $section (keys %govern_timestamped_data){
    for $UUID (keys %{$data_timed{$section}}){
      my @timestamps = sort keys %{$data_timed{$section}{$UUID}{Metrics}};
      $last_timestamp = $timestamps[-1];
      print ("\n TIME DIFFERENCE:\n$timestamps[0] \n$timestamps[-1]\n");
      last;
    }
  }
  $time_shift = $use_time - $last_timestamp;

}
# two hashes: Governing:    SECTION* =>         ARRAY(header=metric names)
#             - rrd creation and order in update
#             Data: schema: SECTION* => ID* => timestamp* => metric name => value
#             - rrd update

print_debug_message("CREATE/UPDATE RRDs [1/2]");
rrd_create_procedure(\%govern_timestamped_data, \%data);
rrd_update_procedure(\%govern_timestamped_data, \%data_timed);

print_debug_message("CREATE/UPDATE RRDs [2/2]");
rrd_create_procedure(\%govern_server_os, \%data, "OS");
rrd_update_procedure(\%govern_server_os, \%os_usage_per_system, "OS");

#-----------------------------------------------------------------------------------
# :+: COLLECT SAMPLES FROM V2 API
#-----------------------------------------------------------------------------------
my %single_collect = ();
%single_collect = general_hash_request("GET", "https://${portal_url}/api/public/v2/ep/inventory/tags");
%single_collect = ();
%single_collect = general_hash_request("GET", timify_query("https://${portal_url}/api/public/v2/ep/usage/pools"));
%single_collect = ();
%single_collect = general_hash_request("GET", timify_query("https://${portal_url}/api/public/v2/ep/usage/tags"));
%single_collect = ();
%single_collect = general_hash_request("GET", "https://${portal_url}/api/public/v2/inventory/cmc/ManagedSystem");
%single_collect = ();
%single_collect = general_hash_request("GET", "https://${portal_url}/api/public/v2/inventory/cmc/ManagementConsole");
%single_collect = ();
%single_collect = general_hash_request("GET", timify_query("https://${portal_url}/api/public/v2/cm/usage/ManagedSystem"));
%single_collect = ();
%single_collect = general_hash_request("GET", timify_query("https://${portal_url}/api/public/v1/cm/usage/ManagedSystem"));


sub rrd_create_procedure {
  # use refs properly!
  my %govern_hash = %{$_[0]};
  # to create RRD use only
  my %data_hash   = %{$_[1]};
  my $OS_indication = $_[2] || "";


  for my $section (keys %govern_hash){
    my $section_rrd = $section;

    # fast fix: section for SystemOS RRDs part must be Systems_OS
    # In order to use configuration of systems to create RRDs.
    if ($OS_indication && $section eq "Systems") {
      $section_rrd = "Systems_OS";
    }

    for $UUID (keys %{$data_hash{$section}}){

      my $rrd = PowercmcDataWrapper::get_rrd_path($console_name, $section_rrd, $UUID);

      my $timestamp  = $oldest_timestamp;

      if (! -f $rrd) {
        rrdCreate($rrd, $timestamp, @{$govern_hash{$section}});
      }
    }
  }

}

sub rrd_update_procedure {
  # keep in this script or treat global variables
  my %govern_hash = %{$_[0]};
  my %data_hash   = %{$_[1]};
  my $OS_indication = $_[2] || "";


  for my $section (keys %govern_hash){
    my $section_rrd = $section;

    # fast fix: section for SystemOS RRDs part must be Systems_OS
    # In order to use configuration of systems to create RRDs.
    if ($OS_indication && $section eq "Systems") {
      $section_rrd = "Systems_OS";
    }

    for $UUID (keys %{$data_hash{$section}}){

      my $rrd = PowercmcDataWrapper::get_rrd_path($console_name, $section_rrd, $UUID);
      my $last_update_time = rrd_last_timestamp($rrd);

      print_debug_message("RRD:    ${rrd} ");
      print_debug_message("HEADER: @{$govern_hash{$section}} ");

      # DEVELOPMENT
      if (! $REAL_DATA ){
        $last_update_time -= $time_shift;
      }

      for my $timestamp (sort keys %{$data_hash{$section}{$UUID}{Metrics}}){

        if ($timestamp > $last_update_time){

          my @data_line = ();

          for my $metric (@{$govern_hash{$section}}){
            if (defined $data_hash{$section}{$UUID}{Metrics}{$timestamp}{$metric}){
              push (@data_line, $data_hash{$section}{$UUID}{Metrics}{$timestamp}{$metric});
            }
            else{
              push (@data_line, 'U');
            }
          }

          my $rrd_created_now = 0;

          if (! -f $rrd) {

            # DEVELOPMENT
            if (! $REAL_DATA){
              $timestamp += $time_shift;
            }

            rrdCreate($rrd, $timestamp, @{$govern_hash{$section}});
            $rrd_created_now = 1;
          }

          if ( !  $rrd_created_now){

            # DEVELOPMENT
            if (! $REAL_DATA){
              $timestamp += $time_shift;
            }

            my $data_string = join(":", @data_line);
            my $last_upd_timestamp = rrdUpdate($rrd, $timestamp, "$data_string");
          }
        }
      }
    }
  }
}

#=========================================================================================
# RRD CREATE AND UPDATE FUNCTIONS
#=========================================================================================
sub rrd_last_timestamp {
  my $rrd   = shift;
  my $ltime;
  my $last_rec = "";
  my $rrd_read;
  my $rrd_state;

  RRDp::start "$rrdtool";

  eval {
    RRDp::cmd qq(last "$rrd" );
    $last_rec = RRDp::read;
  };
  if ($@) {
    RRDp::end;
    return ( "" );
  }
  #print "$rrd";
  #print "\n last time: ${$last_rec}\n";
  my $last_time = ${$last_rec};
  RRDp::end;
  return ($last_time);
}

sub rrdUpdate {
  my $rrd   = shift;
  my $time  = shift;
  my $stats = shift;
  my $ltime;
  my $last_rec = "";
  my $rrd_read;
  my $rrd_state;
  my $last_time = rrd_last_timestamp($rrd);

  my $local_t = localtime();
  print_debug_message("STATS: ${time}:$stats");

  RRDp::start "$rrdtool";
  #print "$stats\n";
  #if ( Xorux_lib::isdigit($time) && Xorux_lib::isdigit($last_time) && $time > $last_time ) {
  if ( $time > $last_time ) {
    RRDp::cmd qq(update "$rrd" $time:$stats);
    my $answer = RRDp::read;
    RRDp::end;
    return ( $time );
  }

  RRDp::end;
  return ( "" );
}

sub rrdCreate {
  my $rrd     = shift;
  my $time    = shift;
  my @header = @_;

  my $local_t = localtime();
  print "${local_t} - CREATING RRD: ${rrd} - TIME:${time} - HEADER: @header \n";

  RRDp::start "$rrdtool";

  my $rrd_time = $time ;
  my $RRD_string;

  my $step    = 60;
  my $prop;
  $prop->{heartbeat}         = 1380;     # says the time interval when RRDTOOL consideres a gap in input data, usually 3 * 5 + 2 = 17mins
  $prop->{first_rra}         = 1;        # 1min
  $prop->{second_rra}        = 60;       # 1h
  $prop->{third_rra}         = 72*5;     # 5 h
  $prop->{forth_rra}         = 288*5;    # 1day
  $prop->{one_min_sample}    = 25920*5;  # 90 days
  $prop->{one_hour_sample}   = 4320*5;   # 180 days
  $prop->{five_hours_sample} = 1734*5;   # 361 days, in fact 6 hours
  $prop->{one_day_sample}    = 1080*5;   # ~ 3 years


  $RRD_string = "create $rrd --start $rrd_time --step $step ";

  for my $variable_name (@header) {
    $RRD_string .= "DS:$variable_name:GAUGE:$prop->{heartbeat}:0:10000000000 ";
  }

  $RRD_string .= "RRA:AVERAGE:0.5:$prop->{first_rra}:$prop->{one_min_sample} ";
  $RRD_string .= "RRA:AVERAGE:0.5:$prop->{second_rra}:$prop->{one_hour_sample} ";
  $RRD_string .= "RRA:AVERAGE:0.5:$prop->{third_rra}:$prop->{five_hours_sample} ";
  $RRD_string .= "RRA:AVERAGE:0.5:$prop->{forth_rra}:$prop->{one_day_sample} ";

  print "\n\n$RRD_string";
  RRDp::cmd qq($RRD_string);
#  if ( !Xorux_lib::create_check("file: $rrd, $prop->{one_min_sample}, $prop->{one_hour_sample}, $prop->{five_hours_sample}, $prop->{one_day_sample}") ) {
#    Xorux_lib::error( "create_rrd err : unable to create $rrd (filesystem is full?) at " . __FILE__ . ": line " . __LINE__ );
  RRDp::end;
  return 1;
}


sub time_budget_query {
  my $ux_end_time = shift;
  my $interval    = shift;

  print_debug_message("Interval: $interval");

  # Minute Hourly Daily Weekly Monthly

  # Minutes, for a maximum of 60 minutes
  # Hours, for a maximum of a week of time
  # Days, for a maximum of six months duration
  # Weeks, for a maximum of two years
  # Months, for a maximum of ten years

  my %interval_backtime = (
    "Daily"   => 35 *24*3600,
    "Weekly"  => 20 *7*24*3600,
    "Monthly" => 20 *31*24*3600,
  );
  my ($sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst) = gmtime($ux_end_time);

  my $EndTS = sprintf( "%4d-%02d-%02dT%02d:%02d:00Z", $year + 1900, $month + 1, $day, $hour, 0 );
  my $time_start_ux = $ux_end_time - int($interval_backtime{$interval});
  ($sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst) = gmtime($time_start_ux);

  my $StartTS;# = sprintf( "%4d-%02d-%02dT%02d:%02d:00Z", $year + 1900, $month + 1, $day, $hour, $min );

  if ( $interval eq "Daily" ) {
    $StartTS = sprintf( "%4d-%02d-%02dT%02d:%02d:00Z", $year + 1900, $month + 1, $day, 0, 0 );
  }
  elsif ( $interval eq "Weekly" ) {
    $StartTS = sprintf( "%4d-%02d-%02dT%02d:%02d:00Z", $year + 1900, $month + 1, $day, 0, 0 );
  }
  elsif ( $interval eq "Monthly" ) {
    $StartTS = sprintf( "%4d-%02d-%02dT%02d:%02d:00Z", $year + 1900, $month + 1, 1, 0, 0 );
  }

  my $query_r = "EndTS=${EndTS}&Frequency=${interval}&StartTS=${StartTS}";
  print_debug_message("QUERY: $query_r");

  return $query_r;
}


sub process_inventory_tags {
  my %data            = %{$_[0]};
  my %os_stats        = %{$_[1]};
  my %inventory_tags  = %{$_[2]};
  my $url_inventory   = $_[3];

  my $loc_query;
  print_debug_message("");


  if (defined $inventory_tags{Tags}){

    for (my $i=0; $i<scalar(@{$inventory_tags{Tags}}); $i++){
      # Partitions => [], Systems => []
      my $tag_id = $inventory_tags{Tags}[$i]{ID};
      my $tag_name = $inventory_tags{Tags}[$i]{Name};

      $data{Tags}{$tag_id}{Name} = $tag_name;

      ## TAGGED PARTITIONS
      #for (my $j=0; $j<scalar(@{$inventory_tags{Tags}[$i]{Partitions}}); $j++){
      #  my %subhash = %{$inventory_tags{Tags}[$i]{Partitions}[$j]};
      #
      #  $UUID                                              = $subhash{UUID};
      #
      #  my $pool_id = $subhash{PoolID};
      #  $data{Pools}{$pool_id}{Name}      = $subhash{PoolName};
      #
      #  $data{Pools}{$pool_id}{Partitions}{$UUID}{Name} = $subhash{Name};
      #  $data{Tags}{$tag_id}{Partitions}{$UUID}{Name}   = $subhash{Name};
      #  $data{Partitions}{$UUID}{Name}                  = $subhash{Name};
      #
      #  $data{Partitions}{$UUID}{Metrics}{proc_available}  = $subhash{ProcessorConfiguration}{AvailableProcessorUnits};
      #  $data{Partitions}{$UUID}{Metrics}{proc_installed}  = $subhash{ProcessorConfiguration}{InstalledProcessorUnits};
      #  $data{Partitions}{$UUID}{Metrics}{mem_available}   = $subhash{MemoryConfiguration}{AvailableMemory};
      #  $data{Partitions}{$UUID}{Metrics}{mem_installed}   = $subhash{MemoryConfiguration}{InstalledMemory};
      # 
      #  $data{Partitions}{$UUID}{Pools}{$pool_id}{Name}    = $subhash{PoolName};
      #  
      #}

      # TAGGED SYSTEMS
      if (defined $inventory_tags{Tags}[$i]{Systems} && scalar @{$inventory_tags{Tags}[$i]{Systems}}){
        for (my $j=0; $j<scalar(@{$inventory_tags{Tags}[$i]{Systems}}); $j++){
          my %subhash = %{$inventory_tags{Tags}[$i]{Systems}[$j]};
          #print Dumper %subhash;
          my $UUID                                         = $subhash{UUID};
          # IMPORTANT NOTE: ONLY SYSTEMS IN POOL
          # possibly could be ""
          if (defined $subhash{PoolID} && $subhash{PoolID} && $subhash{PoolName}){
            my $pool_id = $subhash{PoolID};

            $data{Pools}{$pool_id}{Name} = $subhash{PoolName};
            $data{Systems}{$UUID}{Name}  = $subhash{Name};

            $data{Pools}{$pool_id}{Systems}{$UUID}{Name} = $subhash{Name};
            $data{Systems}{$UUID}{Pools}{$pool_id}{Name} = $subhash{PoolName};

            $data{Tags}{$tag_id}{Systems}{$UUID}{Name} = $subhash{Name};
            $data{Systems}{$UUID}{Tags}{$tag_id}{Name} = $tag_name;

            $data{Systems}{$UUID}{Configuration}{proc_available}           = $subhash{ProcessorConfiguration}{AvailableProcessorUnits};
            $data{Systems}{$UUID}{Configuration}{proc_installed}           = $subhash{ProcessorConfiguration}{InstalledProcessorUnits};

            $data{Systems}{$UUID}{Configuration}{mem_available}            = $subhash{MemoryConfiguration}{AvailableMemory};
            $data{Systems}{$UUID}{Configuration}{mem_installed}            = $subhash{MemoryConfiguration}{InstalledMemory};

            $data{Systems}{$UUID}{Configuration}{base_anyoscores}          = $subhash{BaseCores}{BaseAnyOSCores} + $subhash{BaseCores}{BaseLinuxVIOSCores};

            # Probably API bug:
            # Problem in tagged systems: some of them are under 2 tags, 
            # while only one has non 0 value, while the other (same) one has 0 base memory
            if ( ! defined $data{Systems}{$UUID}{Configuration}{base_memory} ||  ! $data{Systems}{$UUID}{Configuration}{base_memory} ) {
                $data{Systems}{$UUID}{Configuration}{base_memory} = $subhash{BaseMemory};
            }

            $data{Systems}{$UUID}{Configuration}{State}  = $subhash{State};
            $data{Systems}{$UUID}{Configuration}{NumberOfLPARs}  = $subhash{NumberOfLPARs};
            for my $os (keys %{$os_stats{Base}{BaseCores}}){
              my $os_metric_name = $os_stats{Base}{BaseCores}{$os};
              $data{Systems}{$UUID}{Configuration}{$os_metric_name} = $subhash{BaseCores}{$os} || 0;
            }

          }
        }
      }
      else{
        $loc_query = $url_inventory;
        # Unimportant message + problem with default Control Plane Node tag
        #error("No tagged systems in tag $tag_name from $loc_query ");
      }

    }
  }
  else{
    $loc_query = $url_inventory;
    error("No tag data from $loc_query ");
  }

  # SUM of os bases to pool base
  for my $pool_id (keys %{$data{Pools}}) {
    # Prepare base configuration of pools
    for my $os_metric_name (keys %{$os_stats{Base}{BaseCores}}){
      $data{Pools}{$pool_id}{Configuration}{$os_metric_name} = 0;
    }


    for my $UUID (keys %{$data{Pools}{$pool_id}{Systems}}) {

      for my $os_metric_name (keys %{$os_stats{Base}{BaseCores}}){
        my $os_metric_name = $os_stats{Base}{BaseCores}{$os_metric_name};
        $data{Pools}{$pool_id}{Configuration}{$os_metric_name} += $data{Systems}{$UUID}{Configuration}{$os_metric_name};
      }

    }

  }
  return (\%data);
} # process_inventory_tags

sub process_usage_tags {
  print_debug_message("");

  my %os_usage_per_system = %{$_[0]};
  my %data_timed          = %{$_[1]};
  my %data                = %{$_[2]};
  my %usage_tags          = %{$_[3]};
  my $url_usage_tags      = $_[4];
  my $loc_query;
  my $UUID;
  # Cycle fills timestamped data from servers response
  if ( defined $usage_tags{Tags} ){
    if ( !scalar(@{$usage_tags{Tags}}) ){

      $loc_query = timify_query($url_usage_tags);
      error( "No tag data from $loc_query ");

    }

    for (my $i=0; $i<scalar(@{$usage_tags{Tags}}); $i++){
      # Partitions => [], Systems => []
      my $tag_id = $usage_tags{Tags}[$i]{ID};
      my $tag_name = $usage_tags{Tags}[$i]{Name};

      # SYSTEMS
      if (defined $usage_tags{Tags}[$i]{SystemsUsage}){

        for (my $j=0; $j<scalar(@{$usage_tags{Tags}[$i]{SystemsUsage}{Systems}}); $j++){

          my %subhash = %{$usage_tags{Tags}[$i]{SystemsUsage}{Systems}[$j]};
          $UUID = $subhash{UUID};

          # This if is IMPORTANT - make sure system is loaded to %data
          if ( defined $data{Systems}{$UUID} && defined $subhash{Usage}{Usage} ){
            for (my $k=0; $k<scalar(@{$subhash{Usage}{Usage}}); $k++){ 
              my %system_usage = %{$subhash{Usage}{Usage}[$k]};

              my $time_start = $system_usage{StartTime};
              my $timestamp = time2unix($time_start);

              for my $metric_group (keys %{$os_stats{Usage}}){
                for my $os (keys %{$os_stats{Usage}{$metric_group}}){
                  my $os_metric_name = $os_stats{Usage}{$metric_group}{$os};

                  $os_usage_per_system{Systems}{$UUID}{Metrics}{$timestamp}{$os_metric_name} = $system_usage{$metric_group}{$os};

                  if ( ( $USE_V2 ) && ( $os eq "IBMi" ) ) {
                    my $IBMiP10 = $system_usage{$metric_group}{"IBMiP10"} || 0;
                    my $IBMiP20 = $system_usage{$metric_group}{"IBMiP20"} || 0;
                    my $IBMiP30 = $system_usage{$metric_group}{"IBMiP30"} || 0;
                    $os_usage_per_system{Systems}{$UUID}{Metrics}{$timestamp}{$os_metric_name} = $IBMiP10 + $IBMiP20 + $IBMiP30;
                  }
                }
              }

              for my $os (keys %{$os_stats{Base}{BaseCores}}){
                my $os_metric_name = $os_stats{Base}{BaseCores}{$os};
                $os_usage_per_system{Systems}{$UUID}{Metrics}{$timestamp}{$os_metric_name} = $data{Systems}{$UUID}{Configuration}{$os_metric_name};
              }

              $data_timed{Systems}{$UUID}{Metrics}{$timestamp}{utilizedProcUnits} = $system_usage{AverageCoreUsage}{Total};
              $data_timed{Systems}{$UUID}{Metrics}{$timestamp}{proc_installed}    = $data{Systems}{$UUID}{Configuration}{proc_installed};
              $data_timed{Systems}{$UUID}{Metrics}{$timestamp}{base_anyoscores}   = $data{Systems}{$UUID}{Configuration}{base_anyoscores}; 
              $data_timed{Systems}{$UUID}{Metrics}{$timestamp}{mem_available}     = $data{Systems}{$UUID}{Configuration}{mem_available};
              $data_timed{Systems}{$UUID}{Metrics}{$timestamp}{mem_installed}     = $data{Systems}{$UUID}{Configuration}{mem_installed};

              $os_usage_per_system{Systems}{$UUID}{Metrics}{$timestamp}{base_memory}    = $data{Systems}{$UUID}{Configuration}{base_memory};
            }
          }
          elsif ( ! defined $data{Systems}{$UUID} && defined $subhash{Usage}{Usage} ) {
            print_debug_message("INFO: System[${UUID}] - Trying to write data for unknown system!");
          }
          elsif ( defined $data{Systems}{$UUID} && ! defined $subhash{Usage}{Usage} ) {
            print_debug_message("WARNING: System[${UUID}] has empty \"Usage\" element!");
          }
          else {
            print_debug_message("WARNING: look at System[${UUID}]!");
          }
        }
      }
    }
  }
  else{
    $loc_query = timify_query($url_usage_tags);
    error( "No tag data from $loc_query ");
  }

  return (\%data_timed, \%os_usage_per_system, \%data);
} # process_usage_tags

sub process_usage_pools {
  # From Frequency=Hourly: collect configuration
  # From Frequency=Minute: collect performance
  if (defined $usage_pools{Pools}){

    # NO DATA CATCH
    if (!scalar(@{$usage_pools{Pools}})){
      $loc_query = timify_query($url_usage_pools);
      error("No pool data from $loc_query ");
    }

    for (my $i=0; $i<scalar(@{$usage_pools{Pools}}); $i++){
      $ID = $usage_pools{Pools}[$i]{PoolID};
      # possibly could be ""
      if ($ID){ 
        $data{Pools}{$ID}{Name} = $usage_pools{Pools}[$i]{PoolName};
        $data{Pools}{$ID}{Configuration}{CurrentRemainingCreditBalance} = $usage_pools{Pools}[$i]{CurrentRemainingCreditBalance}; 
      }
    }

  }
  else{
    $loc_query = timify_query($url_usage_pools);
    error("No pool data from $loc_query ");
  }

  # TIMED DATA CYCLE: 
  # Load timed data from timed queries
  if (defined $usage_pools{Pools}){
    # ERROR CATCH OF USAGE/POOLS IN UPPER CYCLE
    for (my $i=0; $i<scalar(@{$usage_pools{Pools}}); $i++){
      $ID = $usage_pools{Pools}[$i]{PoolID};
      # possibly could be ""
      if ($ID){ 

        if (defined $usage_pools{Pools}[$i]{Usage}{Usage}){

          for (my $j=0; $j<scalar(@{$usage_pools{Pools}[$i]{Usage}{Usage}}); $j++){ 
            my %poolBox = %{$usage_pools{Pools}[$i]{Usage}{Usage}[$j]};

            my $StartTime = $poolBox{StartTime};
            my $unixStartTime = time2unix($StartTime);

            # !!! CHANGE next part: write out all needed information
            # memory minutes
            for my $lpar (keys %{$poolBox{MemoryMinutes}}){
              my $lc_lpar = lc($lpar);
              $data_timed{Pools}{$ID}{Metrics}{$unixStartTime}{"mm_$lc_lpar"} = $poolBox{MemoryMinutes}{$lpar};
            }

            # core minutes
            for my $lpar (keys %{$poolBox{CoreMinutes}}){
              my $lc_lpar = lc($lpar);
              $data_timed{Pools}{$ID}{Metrics}{$unixStartTime}{"cm_$lc_lpar"} = $poolBox{CoreMinutes}{$lpar};
            }

            # core metered minutes
            for my $lpar (keys %{$poolBox{CoreMeteredMinutes}}){
              my $lc_lpar = lc($lpar);
              $data_timed{Pools}{$ID}{Metrics}{$unixStartTime}{"cmm_$lc_lpar"} = $poolBox{CoreMeteredMinutes}{$lpar};
            }

            # core metered credits
            for my $lpar (keys %{$poolBox{CoreMeteredCredits}}){
              my $lc_lpar = lc($lpar);
              $data_timed{Pools}{$ID}{Metrics}{$unixStartTime}{"cmc_$lc_lpar"} = $poolBox{CoreMeteredCredits}{$lpar};
              #warn "\nCoreMeteredCredits: $lpar: ";
              #warn $poolBox{CoreMeteredCredits}{$lpar};
            }

            $data_timed{Pools}{$ID}{Metrics}{$unixStartTime}{mm_minutes} = $poolBox{MemoryMeteredMinutes};
            $data_timed{Pools}{$ID}{Metrics}{$unixStartTime}{mm_credits} = $poolBox{MemoryMeteredCredits};

            my @pool_total_credit = (
              'cmc_aix',
              'cmc_ibmi',
              'cmc_rhelcoreos',
              'cmc_rhel',
              'cmc_sles',
              'cmc_linuxvios',
              'mm_credits'
            );

            my $credit_sum = 0;
            my $undef_coutner = 0;

            for my $metric_to_sum (@pool_total_credit){
              $credit_sum += $data_timed{Pools}{$ID}{Metrics}{$unixStartTime}{$metric_to_sum};
            }
            #if ($undef_counter eq scalar(@pool_total_credit)){
            #  #undef
            #  $credit_sum = $data_timed{Pools}{$ID}{Metrics}{$unixStartTime}{cmc_aix};
            #}
            #print "$unixStartTime $credit_sum \n";
            for my $os_metric (keys %translate_to_reserve) {
              my $reserve_metric = $translate_to_reserve{$os_metric};
              $data_timed{Pools}{$ID}{Metrics}{$unixStartTime}{$reserve_metric} = $data{Pools}{$ID}{Configuration}{$os_metric};
            }

            $data_timed{Pools}{$ID}{Metrics}{$unixStartTime}{reserve_1} = $credit_sum;
          }
        }
        else{
          $loc_query = timify_query($url_usage_pools);
          print_debug_message("WARNING: Pool[${ID}] has empty \"Usage\" element!");
          error("ERROR: Collection is not complete! No usage pool data for poolID $ID from $loc_query ");
        }

      }
      else {
        print_debug_message("WARNING: NO PoolID!");
      }
    }
  }
  else {
    $loc_query = timify_query($url_usage_pools);
    error("ERROR: Collection is not complete! No usage pool data from $loc_query ");
  }
  # ERROR CATCH OF USAGE/POOLS IN UPPER CYCLE

} # process_usage_pools

sub process_managed_system_data {
  # work with %managed_hmc_data
  if (defined $managed_hmc_data{ManagedSystems}){
    for (my $i = 0; $i<scalar(@{$managed_hmc_data{ManagedSystems}}); $i++){

      my %one_server_data = %{$managed_hmc_data{ManagedSystems}[$i]};
      #print Dumper \%one_server_data;
      $UUID = $one_server_data{UUID};

      # This if is IMPORTANT - work only with servers in pools
      # (checked in inventory tags)
      if ($data{Systems}{$UUID}){
        $data{Systems}{$UUID}{Name} = $one_server_data{Name};

       # # PERFORMANCE FOR RRD
       # $data{Systems}{$UUID}{Metrics}{proc_installed} = $one_server_data{ProcessorConfiguration}{InstalledProcessorUnits};
       # $data{Systems}{$UUID}{Metrics}{proc_available} = $one_server_data{ProcessorConfiguration}{AvailableProcessorUnits};
       # $data{Systems}{$UUID}{Metrics}{mem_installed}  = $one_server_data{MemoryConfiguration}{InstalledMemory};
       # $data{Systems}{$UUID}{Metrics}{mem_available}  = $one_server_data{MemoryConfiguration}{AvailableMemory};

        # CONFIGURATION 
        $data{Systems}{$UUID}{Configuration}{proc_installed} = $one_server_data{ProcessorConfiguration}{InstalledProcessorUnits};
        $data{Systems}{$UUID}{Configuration}{proc_available} = $one_server_data{ProcessorConfiguration}{AvailableProcessorUnits};
        $data{Systems}{$UUID}{Configuration}{mem_installed}  = $one_server_data{MemoryConfiguration}{InstalledMemory};
        $data{Systems}{$UUID}{Configuration}{mem_available}  = $one_server_data{MemoryConfiguration}{AvailableMemory};

        $data{Systems}{$UUID}{Configuration}{State}  = $one_server_data{State};
        $data{Systems}{$UUID}{Configuration}{NumberOfLPARs}  = $one_server_data{NumberOfLPARs} || 0;
        $data{Systems}{$UUID}{Configuration}{NumberOfVIOSs}  = $one_server_data{NumberOfVIOSs} || 0;
        $data{Systems}{$UUID}{Configuration}{SystemFirmware}  = $one_server_data{SystemFirmware};

      }
      else {
        my $server_print_name   = $one_server_data{Name} || "";
        my $server_print_state  = $one_server_data{State} || "unknown state";
        print_debug_message("INFO: System[$UUID] $server_print_name (${server_print_state}) might not be tagged or in pool!");
      }
    }
  }
  else{
    $loc_query = $url_managed_system;
    error( "ERROR: Collection cannot be completed. No server data from $loc_query ");
  }
  #print Dumper \%data;

  # add configuration to every entry in timed data
  for my $pool_id (keys %{$data{Pools}}){
    my @configuration_to_sum = (
      'proc_available', 'proc_installed',
      'mem_available',  'base_memory',
      'mem_installed',  'base_anyoscores',
      'NumberOfLPARs',  'NumberOfVIOSs'
    );

    for my $confitem (@configuration_to_sum){

      $data{Pools}{$pool_id}{Configuration}{$confitem} = 0; 

      for my $UUID (keys %{$data{Pools}{$pool_id}{Systems}}){
        if ( defined $data{Systems}{$UUID}{Configuration}{$confitem} ){
          $data{Pools}{$pool_id}{Configuration}{$confitem}  += $data{Systems}{$UUID}{Configuration}{$confitem};
        }
      }
      for my $UUID (keys %{$data{Pools}{$pool_id}{Systems}}){
        if (! defined $data{Systems}{$UUID}{Configuration}{$confitem}){
          $data{Pools}{$pool_id}{Configuration}{$confitem} = '';
        }
      }
    }
  }
} # process_managed_system_data

sub process_management_console_data {
  if (defined $managed_hmc_data{HMCs} && scalar(@{$managed_hmc_data{HMCs}})){

    for (my $i = 0; $i<scalar(@{$managed_hmc_data{HMCs}}); $i++){
      my %one_hmc_data = %{$managed_hmc_data{HMCs}[$i]};

      my $hmc_uuid = $one_hmc_data{UUID};

      $data{HMCs}{$hmc_uuid}{Name} = $managed_hmc_data{HMCs}[$i]{Name};
      $data{HMCs}{$hmc_uuid}{Configuration}{UVMID} = $managed_hmc_data{HMCs}[$i]{UVMID};

      for (my $j = 0; $j<scalar(@{$one_hmc_data{ManagedSystems}}); $j++){
        $UUID = $one_hmc_data{ManagedSystems}[$j]{UUID};

        # IMPORTANT: only systems in pools
        if ($data{Systems}{$UUID}){ 
          $data{Systems}{$UUID}{HMCs}{$hmc_uuid} = $one_hmc_data{Name};
          $data{HMCs}{$hmc_uuid}{Systems}{$UUID} = $one_hmc_data{ManagedSystems}[$j]{Name};
        }
        else {
          my $system_name_print = $one_hmc_data{Name} || "";
          print_debug_message("INFO: System[${UUID}] $system_name_print was not found in any pool! Make sure it is tagged.");
        }
      }
    }
  }
  else{
    $loc_query = $url_management_console;
    error( "ERROR: Collection is not complete! No HMCs data from $loc_query ");
  }
} # process_management_console_data

sub round_and_multiply_data {
  my %rounding_rules = (
    "Systems" => {
      'mem_installed' => 1,
      'mem_available' => 1,
      'base_memory'   => 1,
    },
    "Pools" => {
      'mem_installed' => 1,
      'mem_available' => 1,
      'base_memory'   => 1,
    }

  );
  my %multipliers = (
    "Systems" => {
      'mem_installed' => 0.001,
      'mem_available' => 0.001,
      'base_memory'   => 0.001,
    },
    "Pools" => {
      'mem_installed' => 0.001,
      'mem_available' => 0.001,
      'base_memory'   => 0.001,
    }

  );

  for my $section (keys %rounding_rules){
    for my $id (keys %{$data{$section}}){  
      for my $conf_name (keys %{$multipliers{$section}}){
        my $multiplied_value = $data{$section}{$id}{Configuration}{$conf_name} * $multipliers{$section}{$conf_name};

        my $round_to = $rounding_rules{$section}{$conf_name};

        my $rounded_value = (sprintf "%.${round_to}f",$multiplied_value);

        $data{$section}{$id}{Configuration}{$conf_name} = $rounded_value;
      }
    }
  }
}

sub check_tagging {
  my @tagged_pools = keys %{$data{Pools}};
  # POOL TAGGING INTEGRITY CHECK
  my @all_pools = keys %{$data{Pools}};

  my %pool_check;
  for my $some_pool (@all_pools){
    $pool_check{$some_pool} = 0;
  }
  for my $tagged_pool (@tagged_pools){
    $pool_check{$tagged_pool} = 1;
  }

  # 2: Pool tagging check
  my @untagged_pools;
  my $tagging_problem = 0;
  for my $some_pool (keys %pool_check){
    if ($some_pool){
      if (! $pool_check{$some_pool}){
        my $p_name = $data{Pools}{$some_pool}{Name};
        $tagging_problem = 1;
        push (@untagged_pools, $p_name);
      }
    }
  }

  if ($tagging_problem){
    print "UNTAGGED POOLS: @untagged_pools \n";
    error("UNTAGGED POOLS: @untagged_pools ");
  }
}


sub make_pool_budget_data {
  my $console             = shift;
  my $datahash_reference  = shift;
  my $interval            = shift; # hourly/daily/weekly/monthly

  # Larger intervals must be collected: credit values are generally small + only 2 decimal places 
  # sum of 24 hourly != daily
  print_debug_message("MAKING POOL BUDGET");

  my %usage_pools = %{$datahash_reference};
  my %data_timed;

  if (defined $usage_pools{Pools}){
    # ERROR CATCH OF USAGE/POOLS IN UPPER CYCLE
    for (my $i=0; $i<scalar(@{$usage_pools{Pools}}); $i++){
      my $ID = $usage_pools{Pools}[$i]{PoolID};
      # possibly could be ""
      if ($ID){ 

        if (defined $usage_pools{Pools}[$i]{Usage}{Usage}){

          for (my $j=0; $j<scalar(@{$usage_pools{Pools}[$i]{Usage}{Usage}}); $j++){ 
            my %poolBox = %{$usage_pools{Pools}[$i]{Usage}{Usage}[$j]};

            my $StartTime = $poolBox{StartTime};
            my $unixStartTime = time2unix($StartTime);

            # !!! CHANGE next part: write out all needed information
            # memory minutes
            for my $lpar (keys %{$poolBox{MemoryMinutes}}){
              my $lc_lpar = lc($lpar);
              #$data_timed{$StartTime}{"mm_$lc_lpar"} = $poolBox{MemoryMinutes}{$lpar};
            }

            # core minutes
            for my $lpar (keys %{$poolBox{CoreMinutes}}){
              my $lc_lpar = lc($lpar);
              #$data_timed{$StartTime}{"cm_$lc_lpar"} = $poolBox{CoreMinutes}{$lpar};
            }

            # core metered minutes
            for my $lpar (keys %{$poolBox{CoreMeteredMinutes}}){
              my $lc_lpar = lc($lpar);
              $data_timed{$StartTime}{CoreMeteredMinutes}{$lpar} = $poolBox{CoreMeteredMinutes}{$lpar};
            }

            # core metered credits
            for my $lpar (keys %{$poolBox{CoreMeteredCredits}}){
              my $lc_lpar = lc($lpar);
              $data_timed{$StartTime}{CoreMeteredCredits}{"$lpar"} = $poolBox{CoreMeteredCredits}{$lpar};
            }

            $data_timed{$StartTime}{MemoryMeteredMinutes} = $poolBox{MemoryMeteredMinutes};
            $data_timed{$StartTime}{MemoryMeteredCredits} = $poolBox{MemoryMeteredCredits};

          }
        }
        else{
          print_debug_message("WARNING: BUDGET - Pool[${ID}] has empty \"Usage\" element!");

          #$loc_query = timify_query($url_usage_pools);
          #error("No usage pool data for poolID $ID from $loc_query ");
        }

        my $lpar2rrd_dir  = $ENV{"INPUTDIR"} || Xorux_lib::error("INPUTDIR is not defined")     && exit;
        my $pool_budget_file = "${lpar2rrd_dir}/data/PEP2/$console/CreditUsage_${interval}_${ID}.json";

        #print(sort keys $data_timed{( keys %data_timed )[0]});

        my $json      = JSON->new->utf8;
        my $json_data = $json->encode(\%data_timed);
        write_to_file($pool_budget_file, $json_data);

      }
    }
  }
} # make_pool_budget_data

exit 0;

