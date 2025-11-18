package DatabasesAlerting;

use strict;
use warnings;

use RRDp;
use Xorux_lib;
use Data::Dumper;
use MIME::Base64 qw(encode_base64 decode_base64);
use DatabasesWrapper;

my %alerted_metrics = (
  'STATUS'    => "Database_status",
  'AVAILABLE' => "AVAILABLE",
  'LOG_SPACE' => "LOG_SPACE",
  'UNUSED'    => "UNUSED",
  'USED'      => "USED",
  'ACTIVE'    => "ACTIVE",
  'IDLE'      => "IDLE",
  'SIZE'      => "SIZE",
  'RELATIONS' => "RELATIONS",
);

#  'AVAILABLE' => "Available space",
#  'LOG_SPACE' => "Log space",
#  'UNUSED'    => "Unused space",
#  'USED'      => "Used space",
#  'ACTIVE'    => "Active sessions",
#  'IDLE'      => "Idle sessions",
#  'SIZE'      => "Database size",


my %alerted_metrics_r = (
  '' => "",
  '' => "",
  '' => "",
  '' => "",
);

my %metric_type = (
  'AVAILABLE'   => "GRAPH",
  'LOG_SPACE'   => "GRAPH",
  'UNUSED'      => "GRAPH",
  'USED'        => "GRAPH",
  'ACTIVE'      => "GRAPH",
  'IDLE'        => "GRAPH",
  'SIZE'        => "GRAPH",
  'STATUS'      => "PLAIN",
  'RELATIONS'   => "SUBMETRIC",

);

my %status_enum = (
  'STATUS' => {
    '0' => "DOWN",
    '1' => "UP",
  },
);

my $inputdir   = $ENV{INPUTDIR};
my $tmpdir     = "$inputdir/tmp";
my $data_dir   = "$inputdir/data";
my $realcfgdir = "$inputdir/etc";
my $cfgdir     = "$inputdir/etc/web_config";
my $log        = "$inputdir/logs/alert_history.log";


my %ALERTS;         # hash holding alerting configuration
my %EMAIL_GROUPS;   # hash holding e-mail groups
my %CONFIG;         # hash holding configuration


my %grp_checker;

sub check_config {
  my $hw_type  = shift;
  my $alias    = shift;
  my $data_ref = shift;
  my %data     = %{$data_ref};
  my %alertable_data;
  my @instances;
  my @values;
  my $alert_bool = 0;

#warn ".....................................................................................";
#
#warn "Alerting";
#warn "INCOMING DATA>>>>>>>>>>>>>>>>>>>>>";
#warn "hw_type: $hw_type alias: $alias";
#warn Dumper $data_ref;
#warn ">>>>>>>>>>>>>>>>>>>>>";

  if ( !%ALERTS or !%EMAIL_GROUPS or !%CONFIG){
    init_alerting_globals();
    return unless (%ALERTS and %CONFIG);
    return unless ($ALERTS{$hw_type}{$alias});
  }

  #warn "Alerts";
  #warn Dumper \%ALERTS;

  %alertable_data = %data;


  my $alertable_instances = can_alert($hw_type, $alias, \%alertable_data);
  #warn "Alertable instances";
  #warn Dumper $alertable_instances;
  if ($alertable_instances) {
    alert($hw_type, $alias, $alertable_instances, \%ALERTS );

    #warn "GOT HERE";

    for my $metric ( keys %{$alertable_instances} ) {
      for my $instance ( keys %{ $alertable_instances->{$metric} } ) {
        create_alert_file($hw_type, $alias, $instance, "repeat", $metric );
      }
    }
  }

  #after alert I should reset all checkers
  #what state Iam I at when I alert?
  #resets: exclude > no checkers to reset,
  #        repeat  > remove the file and create a new one right away so the counter resets,
  #        peak    > remove the file/s
  #May want to create sub for reseting file? //probably isnt needed as it would be used only in repeat reset
  #reset_alert();
}

sub can_alert {
  my $hw_type        = shift;
  my $alias          = shift;
  my $alert_data_ref = shift;
  my %alert_data     = %{$alert_data_ref};
  my %alertable_instances;
  my $def_repeat = defined $CONFIG{REPEAT_DEFAULT}    ? $CONFIG{REPEAT_DEFAULT}    : 10;
  my $def_peak   = defined $CONFIG{PEAK_TIME_DEFAULT} ? $CONFIG{PEAK_TIME_DEFAULT} : 10;

  #warn '$hw_type $alias';
  #warn "$hw_type $alias";
  #warn Dumper \%ALERTS;
  foreach my $instance (keys %{$ALERTS{$hw_type}{$alias}}){
    foreach my $whole_metric ( keys %{ $ALERTS{$hw_type}{$alias}{$instance} } ) {
      my @sp = split( /\_\_/, $whole_metric );
      my $metric    = $sp[0];
      my $submetric = ($sp[$#sp] and $sp[$#sp] ne $metric) ? $sp[$#sp] : "";
      #warn Dumper \@sp;
      #next if ( !defined $alerted_metrics{ $metric } );

      my $metric_full = $alerted_metrics{ $metric };  #mertric full name
      my $exclude     = (defined $ALERTS{$hw_type}{$alias}{$instance}{$whole_metric}[0]{exclude} and $ALERTS{$hw_type}{$alias}{$instance}{$whole_metric}[0]{exclude} ne "") ? $ALERTS{$hw_type}{$alias}{$instance}{$whole_metric}[0]{exclude} : "empty";
      my $repeat      = (defined $ALERTS{$hw_type}{$alias}{$instance}{$whole_metric}[0]{repeat}  and $ALERTS{$hw_type}{$alias}{$instance}{$whole_metric}[0]{repeat}  ne "") ? $ALERTS{$hw_type}{$alias}{$instance}{$whole_metric}[0]{repeat}  : $def_repeat;
      my $peak        = (defined $ALERTS{$hw_type}{$alias}{$instance}{$whole_metric}[0]{peak}    and $ALERTS{$hw_type}{$alias}{$instance}{$whole_metric}[0]{peak}    ne "") ? $ALERTS{$hw_type}{$alias}{$instance}{$whole_metric}[0]{peak}    : $def_peak;
      my $limit       = $ALERTS{$hw_type}{$alias}{$instance}{$whole_metric}[0]{limit};
      next unless (defined $metric_full and defined $limit);
      #exclude > repeat > peak
      if (check_exclude($exclude) ) {
        #warn "aasd";
        #warn Dumper $alert_data_ref;
        foreach my $instance ( keys %{ $alert_data{$metric_full} } ) {
          next unless($ALERTS{$hw_type}{$alias}{$instance});
          #warn "----------------------$instance<<<<<<<<<<<<<< $metric_type{$whole_metric}";
          if (defined $metric_type{$metric} and $metric_type{$metric} eq "GRAPH" ) {
            my $current_value = $alert_data{$metric_full}{$instance}{metric_value};
            if (check_peak($hw_type, $alias, $current_value, $instance, $peak, $limit, $whole_metric ) and check_repeat($hw_type, $alias, $repeat, $instance, $whole_metric ) ) {
              $alertable_instances{$metric}{$instance}{metric_value} = $current_value;
              $alertable_instances{$metric}{$instance}{email_group}  = $ALERTS{$hw_type}{$alias}{$instance}{$metric}[0]{mailgrp};
              next;
            }
          }
          elsif ( defined $metric_type{$metric} and $metric_type{$metric} eq "PLAIN" ) {
            my $current_value = $alert_data{$metric_full}{$instance}{metric_value};
            if (( $current_value == $limit ) and check_repeat($hw_type, $alias, $repeat, $instance, $whole_metric ) ) {
              $alertable_instances{$metric}{$instance}{metric_value} = $current_value;
              $alertable_instances{$metric}{$instance}{email_group}  = $ALERTS{$hw_type}{$alias}{$instance}{$metric}[0]{mailgrp};
              next;
            }
          }
          elsif ( defined $metric_type{$metric} and $metric_type{$metric} eq "SUBMETRIC" ) {
            my $current_value = $alert_data{$metric_full}{$instance}{$submetric}{metric_value};
            if (( $current_value >= $limit ) and check_repeat($hw_type, $alias, $repeat, $instance, $metric ) ) {
              $alertable_instances{$metric}{$instance}{$submetric}{metric_value} = $current_value;
              $alertable_instances{$metric}{$instance}{$submetric}{email_group}  = $ALERTS{$hw_type}{$alias}{$instance}{$whole_metric}[0]{mailgrp};
            }
          }
        }
      }
    }
  }
  #warn "alertable instances";
  #warn Dumper \%alertable_instances;
  return %alertable_instances ? \%alertable_instances : {};
}

sub alert {
  my $hw_type        = shift;
  my $alias          = shift;
  my $alert_data_ref = shift;
  my %alert_data     = %{$alert_data_ref};
  my $lpar_name      = "$alias";
  my $last_type      = "filler";
  my $server_name    = "filler";
  my $unit           = "";
  my $ltime_string   = localtime(time);
  my $graph_base     = "$tmpdir";
  my @graph_paths;

  #warn "ALERTS\n";
  #warn Dumper \%alerts;
  #warn "ALERT DATA\n";
  #warn Dumper \%alert_data;
  #  print Dumper \@emails;
  
  for my $metric ( keys %alert_data ) {

    #warn $metric;
    #my $util = "";
    #my $alert_type_text = "$metric";
    my $metric_short = $alerted_metrics_r{$metric};

    my $mess_metric = $metric;
    $mess_metric =~ s/_/ /g;
    my $subject      = "LPAR2RRD: $mess_metric alert for $hw_type: $alias";
    my $message_text = "$ltime_string: $mess_metric alert for:\n $hw_type: $alias";
    my $instances = "";
    my $submetrics = "";
    my $graph_bool   = 0;
    my $email_group;
    for my $instance ( keys %{ $alert_data{$metric} } ) {
      $instances .= "$instance,";
      if ( $metric_type{$metric} eq "SUBMETRIC" ) {
        my $submetric_message;
        my $emails_tbs;
        my $value;
        for my $submetric ( keys %{ $alert_data{$metric}{$instance} } ) {
          $value = "$alert_data{$metric}{$instance}{$submetric}{metric_value}";
          $submetric_message   = " \n Instance: $instance\n Tablespace: $submetric Value: $value";
          $submetrics .= "$submetric,";
          $emails_tbs = get_group_members( $alert_data{$metric}{$instance}{$submetric}{email_group} );
        }
        #warn "EMAILS TB TBS\n";
        #warn Dumper $emails_tbs;
        if ( defined $emails_tbs and $emails_tbs->[0] ) {
          my $time = gmtime(time);
          system(qq(echo "$time; $metric; Instance; $hw_type; $instance; $submetrics\n" >> $log));
          sendmail( $emails_tbs, $subject, $submetric_message, $lpar_name, "util", $last_type, "alert_type_text", $server_name, \@graph_paths, $graph_bool, $unit );
        }
      }else{
        my $value;
        if ( $metric_type{$metric} eq "GRAPH" ) {
          $value = $alert_data{$metric}{$instance}{metric_value};
          $graph_bool = 1;
          my $graph_path = "$graph_base/alert-$instance-$alias-$metric_short.png";
          create_graph( $instance, $alias, $hw_type, $metric, $graph_path, $inputdir, "$inputdir/bin", '$line', 1 );
          push( @graph_paths, $graph_path );
        }else {# ( $metric_type{$metric} eq "PLAIN" ) {
          $value = $status_enum{$metric}{ $alert_data{$metric}{$instance}{metric_value} };
        }
        $message_text .= " \n Instance: $instance \n Metric: $metric Value: $value";
      }
    $email_group = !defined $email_group ? $alert_data{$metric}{$instance}{email_group} : $email_group;
    }
    my $emails = get_group_members( $email_group );
    #warn "EMAILS\n";
    #warn Dumper $emails;
    #warn '$emails, $subject, $message_text, $lpar_name, "util", $last_type, "alert_type_text", $server_name, \@graph_paths, $graph_bool, $unit'; 
    #warn "$emails, $subject, $message_text, $lpar_name, util, $last_type, alert_type_text, $server_name, graph_paths, $graph_bool, $unit";
    if ( defined $emails and $emails->[0] ) {
      my $time = gmtime(time);
      system(qq(echo "$time; $metric; Alias; $hw_type; $alias; $instances\n" >> $log));

      sendmail( $emails, $subject, $message_text, $lpar_name, "util", $last_type, "alert_type_text", $server_name, \@graph_paths, $graph_bool, $unit );
    }
    if ( $CONFIG{TRAP} and $CONFIG{TRAP} ne "" ) {
      snmp_trap_alarm( $CONFIG{TRAP}, $alias, "$metric", \%alert_data );
    }
    foreach my $graph (@graph_paths) {
      unlink($graph);
    }
  }
}

sub sendmail {
  my $mailto          = shift;
  my $subject         = shift;
  my $text            = shift;
  my $lpar            = shift;
  my $util            = shift;
  my $last_type       = shift;
  my $alert_type_text = shift;
  my $managed         = shift;
  my $graph_paths_ref = shift;
  my $email_graph     = shift;
  my $unit            = shift;
  my $FS_checker      = shift;
  my $message_body;
  my @att_files;
  my @att_names;

  my $mailfrom = "";

  $lpar =~ s/\&\&1/\//g;

  $message_body .= "$text\n";
  if ( exists $CONFIG{'WEB_UI_URL'} && $CONFIG{'WEB_UI_URL'} ne '' ) {
    $message_body .= "\n\nCheck it out in the LPAR2RRD UI: $CONFIG{'WEB_UI_URL'}\n";
  }
  $message_body .= "\n\n";

  if ( isdigit($email_graph) && $email_graph > 0 ) {
    my @graph_paths = @{$graph_paths_ref};

    foreach my $graph_path (@graph_paths) {
      my $graph_name = DatabasesWrapper::basename( $graph_path, "/" );
      push @att_files, $graph_path;
      push @att_names, "$lpar:$graph_name";
    }
  }

  foreach my $email ( @{$mailto} ) {
    chomp $email;
    print "Alert emailing : $alert_type_text $last_type: $subject $mailto\n";
    #warn "CURRENT EMAIL";
    #warn "$email\n";

    Xorux_lib::send_email( $email, $mailfrom, $subject, $message_body, \@att_files, \@att_names );
    last;
  }
  foreach my $f_path (@att_files) {
    if ( -f $f_path ) {
      unlink($f_path);
    }
  }
  return 0;
}

sub check_exclude {
  my $exclude_time = shift;
  my ( $sec, $min, $hour ) = ( gmtime(time) );

  if ( !$exclude_time or $exclude_time eq 'empty' ) {
    return 1;
  }

  my @split_exc = split( /-/, $exclude_time );

  if ( $split_exc[0] < $hour and $hour < $split_exc[1] ) {
    return 0;
  }
  else {
    return 1;
  }
}

sub check_repeat {
  my $alias        = shift;
  my $repeat       = shift;
  my $instance     = shift;
  my $metric_short = shift;

  my $file = "$data_dir/$alias/Alerts/repeat-alert-$instance-$metric_short.txt";
  if ( -f $file ) {
    my $modtime   = ( stat($file) )[9];
    my $time_diff = time - $modtime;
    $repeat = $repeat * 60;
    if (($time_diff >= $repeat - 120) ) {
      unlink($file);
      return 1;
    }
    else {
      return 0;
    }
  }
  else {
    return 1;
  }
}

sub create_alert_file {
  my $hw_type  = shift;
  my $alias    = shift;
  my $instance = shift;
  my $type     = shift;
  my $metric   = shift;

  unless ( -d "$data_dir/$hw_type/$alias/Alerts" ) {
    mkdir( "$data_dir/$hw_type/$alias/Alerts", 0755 ) || warn("Cannot mkdir $data_dir/$hw_type/$alias/Alerts $!") && exit 1;
  }

  my $file     = "$data_dir/$hw_type/$alias/Alerts/$type-alert-$instance-$metric.txt";

  open my $fh, '>', $file;
  print $fh "1\n";
  close $fh;
}

sub check_peak {
  my $hw_type          = shift;
  my $alias            = shift;
  my $metric_value     = shift;
  my $instance         = shift;
  my $peak             = shift;
  my $limit            = shift;
  my $metric_short     = shift;
  my $metric           = $alerted_metrics{$metric_short};
  my $instance_checker = 0;

  ##There could be a problem with one value hittig 15/15 minutes and the other being 10/15 and if I remove both file checkers  when alerting
  ##on the first one the second peak could get lost, but if I dont there may be mail spam and I alredy went the long route to get rid of it
  #warn "metric_value, limit, peak: $metric_value $limit $peak ";
  my $file = "$data_dir/$hw_type/$alias/Alerts/peak-alert-$instance-$metric_short.txt";
  if ( -f $file ) {
    if ( $metric_value > $limit ) {
      my $modtime   = ( stat($file) )[9];
      my $time_diff = time - $modtime;
      $peak = $peak * 60;
      if ( $time_diff >= $peak - 120 ) {
        $instance_checker = 1;
      }
      else {
        $instance_checker = 0;
      }
    }
    else {
      unlink($file);
      $instance_checker = 0;
    }
  }
  else {
    if ( $metric_value >= $limit ) {
      open my $fh, '>', $file;
      print $fh "1\n";
      close $fh;
      $instance_checker = 0;
    }
    else {
      $instance_checker = 0;
    }
  }

  if ($instance_checker) {
    return 1;
  }
  else {
    return 0;
  }
}

sub create_graph {
  my $host        = shift;
  my $server      = shift;
  my $lpar        = shift;
  my $metric      = shift;
  my $graph_path  = shift;
  my $basedir     = shift;
  my $bindir      = shift;
  my $line        = shift;
  my $email_graph = shift;
  my $type        = shift;
  my $perl        = $ENV{PERL};

  my $lpar_url = $lpar;
  $lpar_url =~ s/\//&&1/g;
  my $server_url = $server;
  $lpar_url   =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
  $server_url =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;

  print "Graph creation : $host:$server:$lpar\n";

  $ENV{'QUERY_STRING'} = "host=$host&server=$server&lpar=$lpar&item=$host"."_$server"."__"."$metric"."_a_FF0000&time=d&type_sam=d&detail=1";

  #print "calling grapher: $perl $bindir/detail-graph-cgi.pl alarm $graph_path 1 > $log\n";
  print "QUERY_STRING   : $ENV{'QUERY_STRING'}\n";

  #print "$perl $bindir/detail-graph-cgi.pl alarm $graph_path $email_graph";
  `$perl $bindir/detail-graph-cgi.pl alarm $graph_path $email_graph`;

  #  # only LOG, not the picture
  #  if ( -f $log ) {
  #    open( FH, "< $log" );
  #    foreach my $line (<FH>) {
  #      print "$line";
  #    }
  #    close(FH);
  #    unlink($log);
  #  } ## end if ( -f $log )

  return 1;
}

sub snmp_trap_alarm {
  my $trap_host       = shift;
  my $managed         = shift;
  my $metric          = shift;
  my $alert_data_ref  = shift;
  my $util            = shift;
  my $utillim         = shift;
  my $ltime_str       = shift;
  my $last_type       = shift;
  my $alert_type_text = shift;

  my %alert_data       = %{$alert_data_ref};
  my $SNMP_PEN         = "40540";
  my $PRE              = "1.3.6.1.4.1.40540";
  my $community_string = "public";

  #  if ( exists $inventory_alert{GLOBAL}{'COMM_STRING'} && $inventory_alert{GLOBAL}{'COMM_STRING'} ne '' ) {
  #    $community_string = $inventory_alert{GLOBAL}{'COMM_STRING'};
  #  }
  #
  #  if ( defined $ENV{LPAR2RRD_SNMPTRAP_COMUNITY} ) {
  #    $community_string = $ENV{LPAR2RRD_SNMPTRAP_COMUNITY}
  #  }

  #print "Alert SNMP TRAP: $last_type=$lpar:$managed:$lpar utilization=$util\n";
  # this command sends canonical SNMP names
  # `snmptrap -v 1 -c $community_string $trap_host XORUX-MIB::lpar2rrdSendTrap '' 6 7 '' XORUX-MIB::lpar2rrdHmcName s '$host' XORUX-MIB::lpar2rrdServerName s '$host' XORUX-MIB::lpar2rrdLparName s '$lpar' XORUX-MIB::lpar2rrdValue s '$util' XORUX-MIB::lpar2rrdSu bsystem s '$alert_type_text'`;
  # this one send numerical (it's OK for our needs)

  my $snmp_exe = "/opt/freeware/bin/snmptrap";    # AIX place
  if ( !-f "$snmp_exe" ) {
    $snmp_exe = "/usr/bin/snmptrap";              # linux one
    if ( !-f "$snmp_exe" ) {
      $snmp_exe = "snmptrap";                     # lets hope it is in the PATH
    }
  }

  # print "SNMP trap exec : $snmp_exe -v 1 -c $community_string $trap_host $PRE.1.0.1.0.7 \'\' 6 7 \'\' $PRE.1.1 s $host $PRE.1.2 s $managed $PRE.1.3 s $lpar $PRE.1.4 s \'$alert_type_text\' $PRE.1.5 s $util\n";
  my $trap_text = "";
  for my $instance ( keys %{ $alert_data{$metric} } ) {
    my $value = $alert_data{$metric}{$instance}{metric_value};
    $trap_text .= "$PRE.1.9 s '$instance' $PRE.1.11 s '$value'";
  }

  ## add multiple snmp hosts, they are separated by comma, eg. 1.1.1.1,1.1.1.2,...
  my @snmp_hosts = split /,/, $trap_host;

  foreach my $new_snmp_host (@snmp_hosts) {

    my $out = `$snmp_exe -v 1 -c '$community_string' '$new_snmp_host' $PRE.1.0.1.0.7 '' 6 7 '' $PRE.1.8 s '$managed' $trap_text 2>&1;`;

    print $out;
    if ( $out =~ m/not found/ ) {
      error("SNMP Trap: $snmp_exe binnary has not been found, install net-snmp as per https://www.lpar2rrd.com/alerting_trap.php ($out)");
    }
    if ( $out =~ m/Usage: snmptrap/ ) {
      error("SNMP Trap: looks like you use native AIX /usr/sbin/snmptrap, it is not supported, check here: https://www.lpar2rrd.com/alerting_trap.php");
    }

  }

  return 1;
}

sub nagios_alarm {
  my $host            = shift;
  my $managed         = shift;
  my $lpar            = shift;
  my $util            = shift;
  my $utillim         = shift;
  my $ltime_str       = shift;
  my $last_type       = shift;
  my $alert_type_text = shift;
  my $metric          = shift;

  my $basedir    = "TBD";
  my $nagios_dir = "$basedir/nagios";
  my $lpar_name  = $lpar;
  $lpar_name =~ s/\//&&1/g;

  #print "Alert nagios   : $last_type=$lpar:$managed:$lpar utilization=$util\n";

  if ( !-d "$nagios_dir" ) {

    #print "mkdir          : $nagios_dir\n" if $DEBUG ;
    mkdir( "$nagios_dir", 0755 ) || error( "Cannot mkdir $nagios_dir: $!" . __FILE__ . ":" . __LINE__ ) && return 1;
    chmod 0777, "$nagios_dir" || error( "Can't chmod 666 $nagios_dir: $!" . __FILE__ . ":" . __LINE__ ) && return 1;
  }

  if ( !-d "$nagios_dir/$managed" ) {

    #print "mkdir          : $nagios_dir/$managed\n" if $DEBUG ;
    mkdir( "$nagios_dir/$managed", 0755 ) || error( "Cannot mkdir $nagios_dir/$managed: $!" . __FILE__ . ":" . __LINE__ ) && return 1;
    chmod 0777, "$nagios_dir/$managed" || error( "Can't chmod 666 $nagios_dir/$managed: $!" . __FILE__ . ":" . __LINE__ ) && return 1;
  }

  if ( !-d "$nagios_dir/$managed/$lpar_name" ) {

    #print "mkdir          : $nagios_dir/$managed/$lpar_name\n" if $DEBUG ;
    mkdir( "$nagios_dir/$managed/$lpar_name", 0755 ) || error( "Cannot mkdir $nagios_dir/$managed/$lpar_name: $!" . __FILE__ . ":" . __LINE__ ) && return 1;
    chmod 0777, "$nagios_dir/$managed/$lpar_name" || error( "Can't chmod 666 $nagios_dir/$managed/$lpar_name: $!" . __FILE__ . ":" . __LINE__ ) && return 1;
  }

  open( FH, "> $nagios_dir/$managed/$lpar_name/$metric" ) || error( "Can't create $nagios_dir/$managed/$lpar_name/$metric : $!" . __FILE__ . ":" . __LINE__ ) && return 1;

  if ( $alert_type_text =~ m/Swapping/ ) {
    print FH "$alert_type_text alert for: $last_type=$lpar server=$managed; $util, MAX limit=$utillim\n";
  }
  else {
    print FH "$alert_type_text alert for: $managed $last_type=$lpar server=$managed managed by = $host; utilization=$util, MAX limit=$utillim\n";
  }

  close(FH);

  chmod 0666, "$nagios_dir/$managed/$lpar_name/$metric" || error( "Can't chmod 666 $nagios_dir/$managed/$lpar_name/$metric : $!" . __FILE__ . ":" . __LINE__ ) && return 1;

  return 1;
}

sub isdigit {
  my $digit = shift;
  my $text  = shift;

  if ( !defined $digit || $digit eq '' ) {
    return 0;
  }
  if ( $digit eq 'U' ) {
    return 1;
  }

  my $digit_work = $digit;
  $digit_work =~ s/[0-9]//g;
  $digit_work =~ s/\.//;
  $digit_work =~ s/^-//;
  $digit_work =~ s/e//;
  $digit_work =~ s/\+//;
  $digit_work =~ s/\-//;

  if ( length($digit_work) == 0 ) {

    # is a number
    return 1;
  }

  # NOT a number
  return 0;
}

sub init_alerting_globals {
  require Alerting;

  my %alerting_globals = %{ Alerting::readCfg( 1, "amsure") };

  %ALERTS       = %{$alerting_globals{alerts}};
  %EMAIL_GROUPS = %{$alerting_globals{email_groups}};
  %CONFIG       = %{$alerting_globals{config}};
}

sub get_group_members {

  # param: group_name
  # return sorted array of defined alerts
  my $group_name = shift;
  return $EMAIL_GROUPS{$group_name};
}

1;
