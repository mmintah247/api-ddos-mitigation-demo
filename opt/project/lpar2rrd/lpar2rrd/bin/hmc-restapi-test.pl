use strict;
use warnings;

use Data::Dumper;
use LWP::UserAgent;
use HTTP::Request;
use JSON qw(decode_json encode_json);
use Math::BigInt;
use POSIX;

use HostCfg;

my $basedir = $ENV{INPUTDIR};
require "$basedir/bin/xml.pl";

debug_log("---  Start new test ---");
my ( $host, @others ) = @ARGV;
debug_log("HOST=$host PARAMS:");
print STDERR Dumper \@others;

# OUTLINE:
# - accept CLI params: modes:
#   1: get list of servers:
#    my $managednames = `\$PERL $basedir/bin/hmc-restapi-test.pl "$host" 2>>$host_cfg_log`;
#   2: test single server:
#    my $testresult = `\$PERL $basedir/bin/hmc-restapi-test.pl "$hmc" "$server" 2>>$host_cfg_log`;
# 
# - check configuration existence
# - DEBUG/additional options:
#   - DEBUG_BAD_HMC
#   - REST_API_CMD
# - get session
# - call rest/api/uom/ManagementConsole endpoint
# - call rest/api/pcm/preferences endpoint
# - check LTM... - preconditions for perf data
#
# - FINAL: single array print [] ... That is dangerous..
#
# NOTES:
#   - my $LWPtest = $LWP::VERSION; could be checked
#   - time checks
#
#--------------------------------------------
# explicitly written out all test options
# (this info might not be clear)
# TODO: functions for each type instead of shared run
if ( defined $others[0] ) {
  if ( $others[0] eq "DEBUG_BAD_HMC" ) {
    debug_log("TEST TYPE: DEBUG_BAD_HMC");
  }
  elsif ( $others[0] eq "REST_API_CMD" ) {
    debug_log("TEST TYPE: REST_API_CMD");
  }
  else {
    debug_log("TEST TYPE: 2/2 - singleservertest - $others[0]");
  }
}
else {
  debug_log("TEST TYPE: 1/2 serverlist");
}
#--------------------------------------------


my ( $port, $proto, $login_id, $login_pwd );

#
# Debug variable for extensive connection test from CLI.
#
my $DEBUG_BAD_HMC = 0;
if ( defined $others[0] && $others[0] eq "DEBUG_BAD_HMC" ) {
  $DEBUG_BAD_HMC = 1;
}


my $hmc_configured = 0;
my $hmc_alias = "";
my @all_servers;

#--------------------------------------------
my $aix       = `uname -a|grep AIX|wc -l`;
my $perl_path = `echo \$PERL`;
chomp($aix);
chomp($perl_path);
#--------------------------------------------

my %credentials  = %{ HostCfg::getHostConnections("IBM Power Systems") };
my @host_aliases = keys %credentials;

if ( !defined( keys %credentials ) || !defined $host_aliases[0] ) {
  print "No IBM Power Systems host found. Please save Host Configuration in GUI first<br>\n";
}

foreach my $alias ( keys %credentials ) {
  my $hmc = $credentials{$alias};

  if ( $host ne $hmc->{host} ) {
    next;
  }

  $proto     = $hmc->{proto};
  $port      = $hmc->{api_port};
  $login_id  = $hmc->{username};
  $login_pwd = $hmc->{password};

  my %result_primary = connTest( $host, $port );
  my %result_secondary = ();
  # NOTE: This could be replaced later
  if ( defined $hmc->{hmc2} && $hmc->{hmc2} && $host ne $hmc->{hmc2} ) {
    %result_secondary = connTest( $hmc->{hmc2}, $port );
    if ( ! $result_primary{status} ) {
      debug_log("$host: DUAL HMC: No connection to primary host, using secondary HMC: $hmc->{hmc2}");
      $host = $hmc->{hmc2};
    }
  }

  $hmc_alias = $alias;
  $hmc_configured = 1;
}


debug_log("host:$host proto:$proto port:$port login:$login_id alias:$hmc_alias");

#-------------------------------------------------------------------------------------------

if ( $hmc_configured == 0 ) {
  print "No $host found in Host Configuration. Add your hosts to Web -> Settings -> IBM Power Systems\n";
  print STDERR "No $host found in Host Configuration. Add your hosts to Web -> Settings -> IBM Power Systems\n";
  
  debug_log("EXIT - no HMC in Host Configuration\n");
  exit(1);
}

#-------------------------------------------------------------------------------------------
#
# debug options
#
if ( $DEBUG_BAD_HMC ) {
  my $APISession = generate_session( $proto, $host, $port, $login_id, $login_pwd );
  print "API Session $host : " . substr( $APISession, 0, 80 ) . "\n";

  print "ManagedSystems $host : \n";
  my $mc1 = call_rest_api( $proto, $host, $port, $login_id, $login_pwd, $APISession, "rest/api/uom/ManagementConsole" );
  print Dumper $mc1;

  print "Preferences $host : \n";
  my $pre = call_rest_api( $proto, $host, $port, $login_id, $login_pwd, $APISession, "rest/api/pcm/preferences" );
  print Dumper $pre;

  my $logoff = logoff($APISession);

  if ($logoff) {
    print "Logoff from $host was successful $logoff\n";
  }
  else {
    print "Logoff from $host was not successful $logoff\n";
  }

  print "-----------------------------------\n";
  print "DEBUG_BAD_HMC: part one done\n Following: normal connection test run.";
  print "-----------------------------------\n";
  # Do not exit...
  #exit;
}
elsif ( defined $others[0] && $others[0] eq "REST_API_CMD" && defined $others[1] && $others[1] ne "" ) {
  my $APISession = generate_session( $proto, $host, $port, $login_id, $login_pwd );
  print "API Session $host : " . substr( $APISession, 0, 80 ) . "\n";

  my $pre;
  if ( $others[1] =~ /json/ ) {
    my $rand_json = call_rest_api_json( $proto, $host, $port, $login_id, $login_pwd, $APISession, $others[1] );
    $pre = decode_json($rand_json);
  }
  else {
    $pre = call_rest_api( $proto, $host, $port, $login_id, $login_pwd, $APISession, $others[1] );
  }
  print "Rest API response ($host) : \n";
  print Dumper $pre;
  my $logoff = logoff($APISession);

  if ($logoff) {
    print "Logoff from $host  was successful $logoff\n";
  }
  else {
    print "Logoff from $host was not successful $logoff\n";
  }

  debug_log("EXIT - REST_API_CMD\n");
  exit;
}

#-------------------------------------------------------------------------------------------

my $APISession = generate_session( $proto, $host, $port, $login_id, $login_pwd );
if ($APISession) {
  debug_log("RESULT: REST API connection OK");
}
else {
  print "$host : Cannot get session\n";
  debug_log("EXIT - no session\n");
  exit;
}

#-------------------------------------------------------------------------------------------
#
# Call Management Console
#
my $mc = call_rest_api( $proto, $host, $port, $login_id, $login_pwd, $APISession, "rest/api/uom/ManagementConsole" );

my $hmc_time = $mc->{updated};
debug_log("HMC Time : $hmc_time\n");


if (  ref($mc) eq "HASH" && defined $mc->{error}{content}{_content} &&
      ( $mc->{error}{content}{_msg} =~ /negotiation failed/ || $mc->{error}{content}{_rc} == 500 )) {

  print "$mc->{error}{content}{_msg} \n";
  print "ERROR: $mc->{error}{content}{_content} \n";

  if ( $aix ) {
    print_aix_message();
  }

  logoff($APISession);

  debug_log("EXIT - negotiation failed - rest/api/uom/ManagementConsole\n");
  exit;
}

if ( ref($mc) eq "HASH" && defined $mc->{error}{content}{_content} ) {
  print "API Error : $mc->{error}{content}{_msg} $mc->{error}{content}{_rc} $mc->{error}{content}{_request}{_uri}\n";
  print STDERR "NOK API Error : $mc->{error}{content}{_msg} $mc->{error}{content}{_rc} $mc->{error}{content}{_request}{_uri}\n";
  print STDERR "NOK API Error : Session from previous forced closed connection expired or is corrupted.\n";
}

my $version = $mc->{'entry'}{'content'}{'ManagementConsole:ManagementConsole'}{'VersionInfo'}{'Version'}{'content'};

#-------------------------------------------------------------------------------------------
#
# Call preferences, read servers
#
my $raw_pcm_preferences = call_rest_api( $proto, $host, $port, $login_id, $login_pwd, $APISession, "rest/api/pcm/preferences" );

debug_log("HMC preferences");
#print STDERR Dumper $raw_pcm_preferences;

my $pcm_preferences    = $raw_pcm_preferences->{'entry'}{'content'}{'ManagementConsolePcmPreference:ManagementConsolePcmPreference'}{'ManagedSystemPcmPreference'};
my $servers = get_server_ids( $proto, $host, $port, $login_id, $login_pwd, $APISession );

if ( !defined $servers || ( ref($servers) ne "HASH" && ref($servers) ne "ARRAY" ) ) {
  print "$host : No Servers Found. Check HMC username and password. HMC also might have been restarted right now - wait a while and try again.\n";
  print STDERR "$host : No Servers Found. Check HMC username and password. HMC also might have been restarted right now - wait a while and try again.\n";

  logoff($APISession);

  debug_log("EXIT - no servers found\n");
  exit;
}

#-------------------------------------------------------------------------------------------
#
# Check conditions for performance metrics
#
my $server_found = 0;
if ( ref($pcm_preferences) eq "HASH" ) {
  if ( $pcm_preferences->{'SystemName'}{'content'} eq $others[0] ) {
    $server_found = 1;

    push( @all_servers, $pcm_preferences->{'SystemName'}{'content'} );

    my $agg_on = $pcm_preferences->{'AggregationEnabled'}{'content'};
    my $ltm_on = $pcm_preferences->{'LongTermMonitorEnabled'}{'content'};
    my $stm_on = $pcm_preferences->{'ShortTermMonitorEnabled'}{'content'};
    my $cle_on = $pcm_preferences->{'ComputeLTMEnabled'}{'content'};
    my $eme_on = $pcm_preferences->{'EnergyMonitorEnabled'}{'content'};

    if ( $agg_on eq "false" ) {
      print "Troubleshooting: <a href=\"www.lpar2rrd.com/IBM-Power-Systems-REST-API-troubleshooting.htm\">www.lpar2rrd.com/IBM-Power-Systems-REST-API-troubleshooting.htm</a><br><br>$pcm_preferences->{'SystemName'}{'content'}<br>AggregationEnabled=$agg_on<br>Turn on AggragationEnabled on each server:<br>Server -> Performance -> Top Right Corner - Data Collection -> ON<br>";
    }
    if ( $ltm_on eq "false" ) {
      print "$host $pcm_preferences->{'SystemName'}{'content'} : LongTermMonitor is $ltm_on. Turn on data aggregation\n";
      print STDERR "NOK $host $pcm_preferences->{'SystemName'}{'content'} LongTermMonitorEnabled=$ltm_on\n";
      print STDERR "The LongTermMonitorEnabled must be on. Turn on AggregationEnabled (or just LongTermMonitor if you can)";
    }

  }
}
elsif ( ref($pcm_preferences) eq "ARRAY" && defined $others[0] ) {
  foreach my $m_server ( @{$pcm_preferences} ) {

    if ( $m_server->{'SystemName'}{'content'} !~ $others[0] ) { next; }
    $server_found = 1;

    push( @all_servers, $m_server->{'SystemName'}{'content'} );

    my $agg_on = $m_server->{'AggregationEnabled'}{'content'};
    my $ltm_on = $m_server->{'LongTermMonitorEnabled'}{'content'};
    my $stm_on = $m_server->{'ShortTermMonitorEnabled'}{'content'};
    my $cle_on = $m_server->{'ComputeLTMEnabled'}{'content'};
    my $eme_on = $m_server->{'EnergyMonitorEnabled'}{'content'};

    if ( $agg_on eq "false" ) {
      print "Troubleshooting: <a href=\"www.lpar2rrd.com/IBM-Power-Systems-REST-API-troubleshooting.htm\">www.lpar2rrd.com/IBM-Power-Systems-REST-API-troubleshooting.htm</a><br><br>$m_server->{'SystemName'}{'content'}<br>AggregationEnabled=$agg_on<br>Turn on AggragationEnabled on each server:<br>Server -> Performance -> Top Right Corner - Data Collection -> ON<br>";
      print STDERR "Troubleshooting: <a href=\"www.lpar2rrd.com/IBM-Power-Systems-REST-API-troubleshooting.htm\">www.lpar2rrd.com/IBM-Power-Systems-REST-API-troubleshooting.htm</a><br><br>$m_server->{'SystemName'}{'content'}<br>AggregationEnabled=$agg_on<br>Turn on AggragationEnabled on each server:<br>Server -> Performance -> Top Right Corner - Data Collection -> ON<br>";
    }
    if ( $ltm_on eq "false" ) {
      print "The LongTermMonitorEnabled must be on. Turn on AggregationEnabled (or just LongTermMonitor)<br><br>";
    }

    foreach my $server_id ( keys %{$servers} ) {
      my $server      = $servers->{$server_id};
      my $server_uuid = $server->{id};
      my $server_name = $server->{name};

      if ( $server_name ne $m_server->{'SystemName'}{'content'} ) {
        next;
      }

      my $raw_output = call_rest_api( $proto, $host, $port, $login_id, $login_pwd, $APISession, "rest/api/pcm/ManagedSystem/$server_uuid/RawMetrics/LongTermMonitor" );

      if ( $raw_output eq "-1" ) {
        next;
      }

      my $rand_id = ( keys %{ $raw_output->{entry} } )[0];

      my $rand_json_href = $raw_output->{entry}{$rand_id}{link}{href};
      my $rand_json      = call_rest_api_json( $proto, $host, $port, $login_id, $login_pwd, $APISession, $rand_json_href );
      my $hash_from_json = decode_json($rand_json);

      my $lparsUtil = $hash_from_json->{systemUtil}{utilSample};

      if ( ! defined $lparsUtil || $lparsUtil eq "" ) {
        print "$host $server_name : Perf Data\n";
        print STDERR "NOK $host $server_name Perf Data\n";
      }

    }
  }
}

# IN: $servers HASH ref
#
# PRINT: list of servers
#
my $local_time = strftime( "%F %X", localtime );
$hmc_time =~ s/T/ /;
( $hmc_time, undef ) = split( '\.', $hmc_time );

if ( !defined $others[0] || $DEBUG_BAD_HMC ) {
  my @srvnames;
  my $num_servers = keys %{$servers};

  if ( $num_servers != 0 ) {
    foreach my $server_id ( sort keys %{$servers} ) {
      push @srvnames, $servers->{$server_id}{name};
    }
    print encode_json( \@srvnames );

  }
  else {
    print "Cannot find any server on $host\n";
  }
}
else {
  if ( $server_found == 0 ) {
    print "No server $others[0] found on $host.\n";
  }
}

logoff($APISession);

debug_log("EXIT - standard exit\n");
exit;

#============================================================================

sub generate_session {
  my $proto     = shift;
  my $host      = shift;
  my $port      = shift;
  my $login_id  = shift;
  my $login_pwd = shift;

  my $session;
  my $error;
  my $browser = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0, SSL_verify_mode => 0, SSL_cipher_list => 'DEFAULT:!DH' }, protocols_allowed => [ 'https', 'http' ], keep_alive => 0 );
  $browser->timeout(10);
  my $url   = "$proto://$host:$port/rest/api/web/Logon";

  my $token = <<_REQUEST_;
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<LogonRequest xmlns="http://www.ibm.com/xmlns/systems/power/firmware/web/mc/2012_10/" schemaVersion="V1_0">
  <UserID kb="CUR" kxe="false">$login_id</UserID>
  <Password kb="CUR" kxe="false">$login_pwd</Password>
</LogonRequest>
_REQUEST_

  my $req = HTTP::Request->new( PUT => $url );
  $req->content_type('application/vnd.ibm.powervm.web+xml');
  $req->content_length( length($token) );
  $req->header( 'Accept' => '*/*' );
  $req->content($token);

  my $response = $browser->request($req);

  if ( $DEBUG_BAD_HMC ) {
    print STDERR "Get Session Response $host : \n";
    # Anonymize response before print: _request includes pwd
    $response->{'_request'} = {};
    print "DEBUG_BAD_HMC---session print start---\n";
    print $response;
    print "DEBUG_BAD_HMC---session print end---\n";
    print STDERR Dumper $response;
  }

  if ( $response->is_success ) {
    my $ref = XMLin( $response->content );
    $session = $ref->{'X-API-Session'}{content};
    if ( $session eq "" ) {
      print "Invalid session. Unknown error.\n";
    }
  }
  else {
    print "Session logon failure - $url\n";

    if ( defined $response->{_msg} &&  $response->{_msg} =~ /negotiation failed/ ) {
      print "NOK: $response->{_msg}\n";
      debug_log("NOK: $response->{_msg}");

      if (defined $response->{_content}) {
        print "ERROR: $response->{_content} \n";
        debug_log("ERROR: $response->{_content}");
      }

      if ( $aix ) {
        print_aix_message();
      }

      logoff($APISession);

      debug_log("EXIT - session logon failure\n");
      exit;
    }
    elsif ( defined $response->{_msg} && $response->{_msg} ne "" ){
      print "Session error: $response->{_msg}<br>\n";
      debug_log("Session error: $response->{_msg}");
    }

    if (defined $response->{_content}) {
      print "ERROR: $response->{_content} \n";
      debug_log("ERROR: $response->{_content}");
    }

    return "";
  }

  return $session;
}

sub get_server_ids {
  my $proto      = shift;
  my $host       = shift;
  my $port       = shift;
  my $login_id   = shift;
  my $login_pwd  = shift;
  my $APISession = shift;

  my $i = 0;
  my $out;
  my $name;

  my $ids;
  my $url     = 'rest/api/pcm/preferences';
  my $servers = call_rest_api( $proto, $host, $port, $login_id, $login_pwd, $APISession, $url );

  if ( defined $servers->{error} ) {
    print "Preferences data from hmc: $proto" . "://" . $host . ':' . $port . "/" . $url . "\n";
    print STDERR "NOK preferences data from hmc: $proto" . "://" . $host . "/" . $url . "\n";

    #print Dumper $servers->{error};
    return 813;
  }

  if ( !defined $servers->{entry} ) {
    print "NOK Server list not found on $url\n";
    print STDERR "NOK Server list not found on $url\n";
    return -1;
  }

  $servers = $servers->{entry}{content}{'ManagementConsolePcmPreference:ManagementConsolePcmPreference'}{ManagedSystemPcmPreference};

  if ( ref($servers) eq "HASH" ) {
    debug_log("SERVER in HASH  : $servers->{Metadata}{Atom}{AtomID}:$servers->{SystemName}{content}");
    $out->{$i}{id}   = $servers->{Metadata}{Atom}{AtomID};
    $out->{$i}{name} = $servers->{SystemName}{content};
  }
  elsif ( ref($servers) eq "ARRAY" ) {
    foreach my $hash ( @{$servers} ) {
      debug_log("SERVER in ARRAY : $hash->{Metadata}{Atom}{AtomID}:$hash->{SystemName}{content}");
      $out->{$i}{id}   = $hash->{Metadata}{Atom}{AtomID};
      $out->{$i}{name} = $hash->{SystemName}{content};
      $i++;
    }
  }

  return $out;
}

sub call_rest_api {
  my $proto      = shift;
  my $host       = shift;
  my $port       = shift;
  my $login_id   = shift;
  my $login_pwd  = shift;
  my $APISession = shift;
  my $url        = shift;
  my $error;

  my $browser = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0, SSL_verify_mode => 0, SSL_cipher_list => 'DEFAULT:!DH' }, protocols_allowed => [ 'https', 'http' ], keep_alive => 0 );
  $browser->timeout(10);

  if ( $url =~ /^rest/ ) {
    $url = "$proto://$host:$port/$url";
  }
  elsif ( $url =~ /^\/rest/ ) {
    $url = "$proto://$host:$port" . $url;
  }
  else {
    $url = $url;
  }

  if ( $url eq "" ) {
    $error->{error}{url}     = $url;
    $error->{error}{content} = "Not valid rest api command. Is the url correct? Check config";
    return $error;
  }

  my $req = HTTP::Request->new( GET => $url );
  $req->content_type('application/xml');
  $req->header( 'Accept'        => '*/*' );
  $req->header( 'X-API-Session' => $APISession );

  my $data = $browser->request($req);

  if ($data->{_rc} < 200 && $data->{_rc} >= 300){
    print "NOK: $data->{_rc} $data->{_msg}<br>\n";
    return;
  }
  elsif ( $data->{_content} =~ m/SRVE0190E/) {
    print "NOK: $data->{_rc} $data->{_msg}<br>\n";
    return;
  }

  if ( $data->is_success) {

    if ( $data->{_content} eq "" ) {
      if ( $url =~ m/LongTermMonitor/ ) {
        print "LongTermMonitor is off. This happens a few minutes after data aggregation is enabled. Wait a few minutes and try again.<br><br>\n";
      }
      return -1;
    }
    else {
      my $out;
      eval {
        $out = XMLin( $data->{_content} );
      };
      if ($@) {
        print "Corrupted XML content:\n";
        print Dumper $data->content;
        return { "corrupted_xml" => $data->content };
      }
      return $out;
    }
  }
  else {
    print "NOK: $data->{_rc} GET $url $data->{_msg}<br>\n";
    if ( $data->{_content} =~ m/user does not have the role authority to perform the request/) {

      #print "NOK IMPORTANT SETTINGS: Allow remote access via the web : GUI --> Manage User Profiles and Access --> select lpar2rrd --> modify --> user properties --> Allow remote access via the web\n";
      #print STDERR "NOK IMPORTANT SETTINGS: Allow remote access via the web : GUI --> Manage User Profiles and Access --> select lpar2rrd --> modify --> user properties --> Allow remote access via the web\n";
      return $data;
    }
    $error->{error}{content} = $data;
    return $error;
  }
}

sub call_rest_api_json {
  my $proto      = shift;
  my $host       = shift;
  my $port       = shift;
  my $login_id   = shift;
  my $login_pwd  = shift;
  my $APISession = shift;
  my $url        = shift;
  my $error;

  my $browser = LWP::UserAgent->new(
    ssl_opts => { verify_hostname => 0, SSL_verify_mode => 0, SSL_cipher_list => 'DEFAULT:!DH'},
    protocols_allowed => [ 'https', 'http' ],
    keep_alive => 0
  );

  $browser->timeout(10);

  if ( $url =~ /^rest/ ) {
    $url = "$proto://$host:$port/$url";
  }
  elsif ( $url =~ /^\/rest/ ) {
    $url = "$proto://$host:$port" . $url;
  }
  else {
    my $new_url = $url;
    $new_url =~ s/^.*\/rest/rest/g;
    $url = "$proto://$host:$port/$new_url";
  }

  my $req = HTTP::Request->new( GET => $url );
  $req->content_type('application/json');
  $req->header( 'Accept'        => '*/*' );
  $req->header( 'X-API-Session' => $APISession );

  my $data = $browser->request($req);
  if ( $data->is_success ) {
    my $out = $data->{_content};
    return $out;
  }
  else {
    print STDERR "call_rest_api_json: not successful";
    return {};
  }

}

sub logoff {
  my $session = shift;

  my $url = "${proto}://${host}:${port}/rest/api/web/Logon";

  my $browser = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0, SSL_verify_mode => 0, SSL_cipher_list => 'DEFAULT:!DH' }, keep_alive => 0 );
  $browser->timeout(10);

  my $req = HTTP::Request->new( DELETE => $url );
  $req->header( 'X-API-Session' => $session );

  my $data = $browser->request($req);
  if ( $data->is_success ) {
    return 1;
  }
  else {
    if ( $data->{_rc} == 401 ) {
      print STDERR $data->{_msg};
      return 0;
    }
    else {
      print "logoff wasn't sucessfull $data->{_rc}\n";
    }
  }
}

sub print_aix_message {
  print "Crypt-SSLeay, perl-Net_SSLeay.pm are required on AIX\n(just in case of older rpms, new yum/dnf does not require it)\n";
  my @modules = `rpm -q perl-Crypt-SSLeay perl-Net_SSLeay.pm`;
  foreach my $m (@modules) {
    chomp($m);
    print "$m";
  }
  print "\n";
  print "AIX HTTPS visit http://lpar2rrd.com/https.htm for resolving this AIX specific problem\n";
}

sub debug_log {
  my $log_message = shift || "info";
  my $host_to_print = $host || "";
  print STDERR strftime( "%F %H:%M:%S", localtime(time) ) . ": $host_to_print: HMC test: $log_message \n";
}

# NOTE: copy from host_cfg.pl, move out/share?
sub connTest {
  my $host = shift;
  my $port = shift;
  my %result;

  use IO::Socket::IP;
  my $sock;

  eval {
    local $SIG{ALRM} = sub { die 'Timed Out'; };
    alarm 10;
    $sock = new IO::Socket::IP(
      PeerAddr => $host,
      PeerPort => $port,
      Proto    => 'tcp',
      Timeout  => 3
    );

    alarm 0;
  };
  alarm 0;    # race condition protection
  if ( $@ && $@ =~ /Timed Out/ ) {
    $result{status} = 0;
    $result{msg}    = "TCP connection to $host:$port timed out after 10 seconds!";
    return %result;
  }
  elsif ($sock) {
    $result{status} = 1;
    $result{msg}    = "TCP connection to $host:$port is <span class='noerr'>OK</span>.";
    return %result;
  }
  else {
    $result{status} = 0;
    $result{msg}    = "TCP connection to $host:$port has failed! Open it on the firewall.";
    return %result;
  }
}

