package GoogleCloud;

use strict;
use warnings;

use HTTP::Request::Common;
use LWP;
use Data::Dumper;
use JSON;
use POSIX qw(strftime ceil);
use Date::Parse;
use Time::Local;
use GCloudDataWrapper;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir  = $ENV{INPUTDIR};
my $conf_path = "$inputdir/data/GCloud";
my $agent_path = "$inputdir/data/GCloud/agent";

unless ( -d $conf_path ) {
  mkdir( "$conf_path", 0755 ) || warn( localtime() . ": Cannot mkdir $conf_path: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $agent_path ) {
  mkdir( "$agent_path", 0755 ) || warn( localtime() . ": Cannot mkdir $agent_path: $!" . __FILE__ . ':' . __LINE__ );
}

my @metrics             = ( { 'name' => 'cpu_util',    'url' => 'compute.googleapis.com/instance/cpu/utilization',          'type' => 'doubleValue' }, { 'name' => 'read_bytes',        'url' => 'compute.googleapis.com/instance/disk/read_bytes_count',         'type' => 'int64Value' }, { 'name' => 'write_bytes', 'url' => 'compute.googleapis.com/instance/disk/write_bytes_count', 'type' => 'int64Value' }, { 'name' => 'read_ops', 'url' => 'compute.googleapis.com/instance/disk/read_ops_count', 'type' => 'int64Value' }, { 'name' => 'write_ops', 'url' => 'compute.googleapis.com/instance/disk/write_ops_count', 'type' => 'int64Value' }, { 'name' => 'received_bytes', 'url' => 'compute.googleapis.com/instance/network/received_bytes_count', 'type' => 'int64Value' }, { 'name' => 'sent_bytes', 'url' => 'compute.googleapis.com/instance/network/sent_bytes_count', 'type' => 'int64Value' } );
my @metrics_agent       = ( { 'name' => 'mem_used',    'url' => 'agent.googleapis.com/memory/bytes_used',                   'type' => 'doubleValue' }, { 'name' => 'mem_usage',         'url' => 'agent.googleapis.com/memory/percent_used',                      'type' => 'doubleValue' } );
my @metrics_db          = ( { 'name' => 'cpu_util',    'url' => 'cloudsql.googleapis.com/database/cpu/utilization',         'type' => 'doubleValue' }, { 'name' => 'disk_used',         'url' => 'cloudsql.googleapis.com/database/disk/bytes_used',              'type' => 'int64Value' }, { 'name' => 'disk_quota', 'url' => 'cloudsql.googleapis.com/database/disk/quota', 'type' => 'int64Value' }, { 'name' => 'read_ops', 'url' => 'cloudsql.googleapis.com/database/disk/read_ops_count', 'type' => 'int64Value' }, { 'name' => 'write_ops', 'url' => 'cloudsql.googleapis.com/database/disk/write_ops_count', 'type' => 'int64Value' }, { 'name' => 'mem_total', 'url' => 'cloudsql.googleapis.com/database/memory/quota', 'type' => 'int64Value' }, { 'name' => 'mem_used', 'url' => 'cloudsql.googleapis.com/database/memory/usage', 'type' => 'int64Value' }, { 'name' => 'mem_total', 'url' => 'cloudsql.googleapis.com/database/memory/quota', 'type' => 'int64Value' }, { 'name' => 'connections', 'url' => 'cloudsql.googleapis.com/database/network/connections', 'type' => 'int64Value' }, { 'name' => 'received_bytes', 'url' => 'cloudsql.googleapis.com/database/network/received_bytes_count', 'type' => 'int64Value' }, { 'name' => 'sent_bytes', 'url' => 'cloudsql.googleapis.com/database/network/sent_bytes_count', 'type' => 'int64Value' } );
my @metrics_db_mysql    = ( { 'name' => 'innodb_read', 'url' => 'cloudsql.googleapis.com/database/mysql/innodb_pages_read', 'type' => 'int64Value' },  { 'name' => 'innodb_write',      'url' => 'cloudsql.googleapis.com/database/mysql/innodb_pages_written',   'type' => 'int64Value' }, { 'name' => 'queries', 'url' => 'cloudsql.googleapis.com/database/mysql/queries', 'type' => 'int64Value' }, { 'name' => 'questions', 'url' => 'cloudsql.googleapis.com/database/mysql/questions', 'type' => 'int64Value' }, { 'name' => 'innodb_buffer_free', 'url' => 'cloudsql.googleapis.com/database/mysql/innodb_buffer_pool_pages_free', 'type' => 'int64Value' }, { 'name' => 'innodb_buffer_total', 'url' => 'cloudsql.googleapis.com/database/mysql/innodb_buffer_pool_pages_total', 'type' => 'int64Value' }, { 'name' => 'innodb_data_fsyncs', 'url' => 'cloudsql.googleapis.com/database/mysql/innodb_data_fsyncs', 'type' => 'int64Value' }, { 'name' => 'innodb_os_fsyncs', 'url' => 'cloudsql.googleapis.com/database/mysql/innodb_os_log_fsyncs', 'type' => 'int64Value' } );
my @metrics_db_postgres = ( { 'name' => 'connections', 'url' => 'cloudsql.googleapis.com/database/postgresql/num_backends', 'type' => 'int64Value' },  { 'name' => 'transaction_count', 'url' => 'cloudsql.googleapis.com/database/postgresql/transaction_count', 'type' => 'int64Value' } );

sub new {
  my ( $self, $name, $print, $uuid, @credentials ) = @_;
  my $o = {};

  my $cred_file = "$inputdir/etc/web_config/gcloud_" . $name . "_credentials.json";
  open my $cf, ">", $cred_file;
  print $cf JSON->new->pretty->encode($credentials[0][0]);
  close $cf;

  $ENV{GOOGLE_APPLICATION_CREDENTIALS} = $cred_file;
  my $result  = `export GOOGLE_APPLICATION_CREDENTIALS="$cred_file"`;
  my $token   = `gcloud auth application-default print-access-token `;
  my $project = $credentials[0][0]->{project_id};


  $o->{uuid} = defined $uuid ? $uuid : $name;

  $o->{uuid}            = defined $uuid ? $uuid : $name;
  $o->{credentials}     = $credentials[0];
  $o->{token}           = $token;
  $o->{project}         = $project;
  $o->{zones}           = &getZones( $token, $project );
  $o->{name}            = $name;
  $o->{current_account} = 0;
  bless $o, $self;
  return $o;
}

sub testToken {
  my ($self) = @_;
  return $self->{token};
}

sub setNextServiceAccount {
  my ($self) = @_;

  my $is_last = 0;

  if( scalar( @{ $self->{credentials} } ) == $self->{current_account}){
    $is_last = 1;
    return $is_last;
  }

  my $cred_file = "$inputdir/etc/web_config/gcloud_" . $self->{name} . "_credentials.json";

  open my $cf, ">", $cred_file;
  print $cf JSON->new->allow_nonref->pretty->encode($self->{credentials}[$self->{current_account}]);
  close $cf;

  $ENV{GOOGLE_APPLICATION_CREDENTIALS} = $cred_file;
  my $result  = `export GOOGLE_APPLICATION_CREDENTIALS="$cred_file"`;
  my $token   = `gcloud auth application-default print-access-token`;
  my $project = $self->{credentials}[$self->{current_account}]->{project_id};

  $self->{token}   = $token;
  $self->{project} = $project;
  $self->{zones}   = &getZones( $token, $project );

  $self->{current_account}++;

  return $is_last;

}

sub resetServiceAccounts {
  my ($self) =  @_;
  $self->{current_account} = 0;
}

sub getZones {
  my ( $token, $project ) = @_;

  my @zones;

  my $response = gcloudRequest( "https://compute.googleapis.com/compute/v1/projects/$project/regions", $token );

  for ( @{ $response->{items} } ) {
    my $region = $_;
    my $add    = 0;

    for ( @{ $region->{quotas} } ) {
      my $quota = $_;

      if ( $quota->{metric} eq "INSTANCES" && $quota->{usage} >= 1 ) {
        $add = 1;
      }
    }

    if ( $add eq "1" ) {
      for ( @{ $region->{zones} } ) {
        my $zone     = $_;
        my @splitted = split( /\//, $zone );

        #print "\n$splitted[8]";
        push( @zones, $splitted[8] );
      }
    }

  }

  return \@zones;
}

sub listInstances {
  my ( $self, $print ) = @_;

  my %data;

  $data{specification}{hostcfg_uuid}{ $self->{uuid} } = $self->{uuid};
  $data{project}{$self->{uuid}}{label} = $self->{name};
  $data{project}{$self->{uuid}}{uuid} = $self->{uuid};

    while($self->setNextServiceAccount() eq 0){

        for ( @{ $self->{zones} } ) {
            my $region = $_;

            if ( $print eq "1" ) {
            print "\nSearching in zone: $region";
            }


            my $response = gcloudRequest( "https://compute.googleapis.com/compute/v1/projects/$self->{project}/zones/$region/instances", $self->{token} );

            #print Dumper($response);

            if (defined $response->{items}){
              $data{project}{$self->{uuid}}{regions}{$region.$self->{name}} = $region;
              $region = $region.$self->{name};
            }

            for ( @{ $response->{items} } ) {
              my $item = $_;

              $item->{id} = $item->{id}.$self->{name};

              $data{specification}{compute}{ $item->{id} }{status}            = $item->{status};
              $data{specification}{compute}{ $item->{id} }{name}              = $item->{name};
              $data{specification}{compute}{ $item->{id} }{cpuPlatform}       = $item->{cpuPlatform};
              $data{specification}{compute}{ $item->{id} }{machineType}       = $item->{machineType};
              $data{specification}{compute}{ $item->{id} }{creationTimestamp} = $item->{creationTimestamp};
              $data{specification}{compute}{ $item->{id} }{region}            = $region;
              $data{specification}{compute}{ $item->{id} }{ip}                = $item->{networkInterfaces}->[0]->{accessConfigs}->[0]->{natIP};
              $data{specification}{compute}{ $item->{id} }{hostcfg_uuid}      = $self->{uuid};

              if ( !defined $data{specification}{region}{$region} ) {
                  $data{specification}{region}{$region}{running} = 0;
                  $data{specification}{region}{$region}{stopped} = 0;
              }

              if ( $item->{status} eq "RUNNING" ) {
                  if ( defined $data{specification}{region}{$region}{running} ) {
                  $data{specification}{region}{$region}{running} = $data{specification}{region}{$region}{running} + 1;
                  }
                  else {
                  $data{specification}{region}{$region}{running} = 1;
                  }
              }
              else {
                  if ( defined $data{specification}{region}{$region}{stopped} ) {
                  $data{specification}{region}{$region}{stopped} = $data{specification}{region}{$region}{stopped} + 1;
                  }
                  else {
                  $data{specification}{region}{$region}{stopped} = 1;
                  }
              }

              my $diskSize = 0;
              for ( @{ $item->{disks} } ) {
                  my $disk = $_;
                  $diskSize = $diskSize + $disk->{diskSizeGb};
              }

              $data{specification}{compute}{ $item->{id} }{diskSize} = $diskSize;

              my @adresa = split /\//, $item->{machineType};

              $data{specification}{compute}{ $item->{id} }{size} = $adresa[10];

              $data{label}{compute}{ $item->{id} } = $item->{name};

              if ( exists $data{architecture}{region_compute}{$region}[0] ) {
                  push( @{ $data{architecture}{region_compute}{$region} }, $item->{id} );
              }
              else {
                  $data{architecture}{region_compute}{$region}[0] = $item->{id};
              }
            }

        }

        #my $databases_plain = `gcloud sql instances list --format=json  --user-output-enabled=false -q`; #old way of fetching sql instances
        my $databases = gcloudRequest("https://sqladmin.googleapis.com/v1/projects/$self->{project}/instances", $self->{token});
        if(defined $databases->{items}){
          for ( @{$databases->{items}} ) {
              my $database = $_;

              $data{project}{$self->{uuid}}{regions_database}{$database->{region}.$self->{name}} = $database->{region};
              $database->{region} = $database->{region}.$self->{name};

              my $type = "undef";
              if ( index( $database->{databaseVersion}, "MYSQL" ) != -1 ) {
              $type = "mysql";
              }
              elsif ( index( $database->{databaseVersion}, "POSTGRES" ) != -1 ) {
              $type = "postgres";
              }

              my $database_id = "$database->{project}:$database->{name}".$self->{name};
              $database_id =~ s/:/__/g;

              $data{specification}{database}{$database_id}{name}            = $database->{name};
              $data{specification}{database}{$database_id}{region}          = $database->{region};
              $data{specification}{database}{$database_id}{databaseVersion} = $database->{databaseVersion};
              $data{specification}{database}{$database_id}{dataDiskSizeGb}  = $database->{settings}->{dataDiskSizeGb};
              $data{specification}{database}{$database_id}{dataDiskType}    = $database->{settings}->{dataDiskType};
              $data{specification}{database}{$database_id}{size}            = $database->{settings}->{tier};
              $data{specification}{database}{$database_id}{status}          = $database->{state};
              $data{specification}{database}{$database_id}{hostcfg_uuid}    = $self->{uuid};

              $data{engines}{$database_id} = $type;

              for ( @{ $database->{ipAddresses} } ) {
              my $ip = $_;
              if ( $ip->{type} eq "PRIMARY" ) {
                  $data{specification}{database}{$database_id}{ip} = $ip->{ipAddress};
              }
              }

              if ( exists $data{architecture}{region_database}{ $database->{gceZone}.$self->{name} }[0] ) {
              push( @{ $data{architecture}{region_database}{ $database->{gceZone}.$self->{name} } }, $database_id );
              }
              else {
              $data{architecture}{region_database}{ $database->{gceZone}.$self->{name} }[0] = $database_id;
              }

              $data{label}{database}{$database_id} = $database->{name};

          }
        }

    }

    $self->resetServiceAccounts();

    print "\n";
    return \%data;

}

sub testInstances {
  my ($self) = @_;

  my %data;

  my $error = 1;

  for ( @{ $self->{zones} } ) {
    my $region = $_;

    my $response = gcloudRequestTest( "https://compute.googleapis.com/compute/v1/projects/$self->{project}/zones/$region/instances", $self->{token} );

    if ( $response eq "1" ) {
      $error = 0;
    }

  }
  return $error;

}

sub reformatTime {
  my ($time) = @_;
  my %data;
  foreach my $time_key ( keys %{$time} ) {
    $data{$time_key} = sprintf( "%02d", $time->{$time_key} );
  }
  return \%data;
}

sub getMetrics {
    my ($self) = @_;

    #Get last record
    my $lastHour                = time() - 600;
    my $timestamp_json_recovery = "{\"timestamp\":\"$lastHour\"}";
    my $timestamp_json          = '';
    if ( open( my $fh, '<', $conf_path . "/last_" . $self->{name} . ".json" ) ) {
        while ( my $row = <$fh> ) {
        chomp $row;
        $timestamp_json .= $row;
        }
        close($fh);
    }
    else {
        open my $hl, ">", $conf_path . "/last_" . $self->{name} . ".json";
        $timestamp_json = "{\"timestamp\":\"$lastHour\"}";
        print $hl "{\"timestamp\":\"$lastHour\"}";
    }

    # decode JSON
    my $timestamp_data = ();
    eval { $timestamp_data = decode_json($timestamp_json); };
    if ($@) {
        warn( localtime() . ": Error decoding JSON in timestamp file: missing data" );
        $timestamp_data = decode_json($timestamp_json_recovery);
    }

    my $timestamp = time();
    $timestamp = $timestamp - 210;
    my $timestamp_from = $timestamp_data->{timestamp};

    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime($timestamp_from);
    $year += 1900;
    $mon  += 1;
    my $reformated = reformatTime( { 'month' => $mon, 'day' => $mday, 'hour' => $hour, 'min' => $min, 'sec' => $sec } );
    my $start_time = "$year-$reformated->{month}-$reformated->{day}T$reformated->{hour}:$reformated->{min}:$reformated->{sec}";

    ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime($timestamp);
    $year += 1900;
    $mon  += 1;
    $reformated = reformatTime( { 'month' => $mon, 'day' => $mday, 'hour' => $hour, 'min' => $min, 'sec' => $sec } );
    my $end_time = "$year-$reformated->{month}-$reformated->{day}T$reformated->{hour}:$reformated->{min}:$reformated->{sec}";

    my %agent;
    my %data;

    while($self->setNextServiceAccount() eq 0){

        for (@metrics) {
            my $metric = $_;

            my $response = gcloudRequest( "https://monitoring.googleapis.com/v3/projects/$self->{project}/timeSeries?filter=metric.type=\"" . $metric->{url} . "\"&interval.endTime=" . $end_time . "Z&interval.startTime=" . $start_time . "Z", $self->{token} );

            for ( @{ $response->{timeSeries} } ) {
            my $timeserie = $_;

            for ( @{ $timeserie->{points} } ) {
                my $point = $_;

                my $pretty_time = str2time( $point->{interval}->{endTime} );
                $pretty_time                                                                                       = int($pretty_time);
                $pretty_time                                                                                       = $pretty_time - ( $pretty_time % 60 );
                $agent{ $timeserie->{resource}->{labels}->{instance_id}.$self->{name} }                                          = 0;
                $data{compute}{ $timeserie->{resource}->{labels}->{instance_id}.$self->{name} }{$pretty_time}{ $metric->{name} } = $point->{value}->{ $metric->{type} };
            }
            }
        }

        #all databases
        for (@metrics_db) {
            my $metric = $_;

            my $response = gcloudRequest( "https://monitoring.googleapis.com/v3/projects/$self->{project}/timeSeries?filter=metric.type=\"" . $metric->{url} . "\"&interval.endTime=" . $end_time . "Z&interval.startTime=" . $start_time . "Z", $self->{token} );

            #print Dumper($response);

            for ( @{ $response->{timeSeries} } ) {
            my $timeserie = $_;

            for ( @{ $timeserie->{points} } ) {
                my $point = $_;

                my $pretty_time = str2time( $point->{interval}->{endTime} );
                $pretty_time = int($pretty_time);
                $pretty_time = $pretty_time - ( $pretty_time % 60 );

                my $database_id = $timeserie->{resource}->{labels}->{database_id}.$self->{name};
                $database_id =~ s/:/__/g;

                $data{database}{$database_id}{$pretty_time}{ $metric->{name} } = $point->{value}->{ $metric->{type} };
            }
            }
        }

        #mysql
        for (@metrics_db_mysql) {
            my $metric = $_;

            my $response = gcloudRequest( "https://monitoring.googleapis.com/v3/projects/$self->{project}/timeSeries?filter=metric.type=\"" . $metric->{url} . "\"&interval.endTime=" . $end_time . "Z&interval.startTime=" . $start_time . "Z", $self->{token} );

            #print Dumper($response);

            for ( @{ $response->{timeSeries} } ) {
            my $timeserie = $_;

            for ( @{ $timeserie->{points} } ) {
                my $point = $_;

                my $pretty_time = str2time( $point->{interval}->{endTime} );
                $pretty_time = int($pretty_time);
                $pretty_time = $pretty_time - ( $pretty_time % 60 );

                my $database_id = $timeserie->{resource}->{labels}->{database_id}.$self->{name};
                $database_id =~ s/:/__/g;

                $data{database}{$database_id}{$pretty_time}{ $metric->{name} } = $point->{value}->{ $metric->{type} };
            }
            }
        }

        #postgres
        for (@metrics_db_postgres) {
            my $metric = $_;

            my $response = gcloudRequest( "https://monitoring.googleapis.com/v3/projects/$self->{project}/timeSeries?filter=metric.type=\"" . $metric->{url} . "\"&interval.endTime=" . $end_time . "Z&interval.startTime=" . $start_time . "Z", $self->{token} );

            #print Dumper($response);

            for ( @{ $response->{timeSeries} } ) {
                my $timeserie = $_;

                for ( @{ $timeserie->{points} } ) {
                    my $point = $_;

                    my $pretty_time = str2time( $point->{interval}->{endTime} );
                    $pretty_time = int($pretty_time);
                    $pretty_time = $pretty_time - ( $pretty_time % 60 );

                    my $database_id = $timeserie->{resource}->{labels}->{database_id}.$self->{name};
                    $database_id =~ s/:/__/g;

                    $data{database}{$database_id}{$pretty_time}{ $metric->{name} } = $point->{value}->{ $metric->{type} };
                }
            }
        }

        #agent process
        ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime( $timestamp_from - 180 );
        $year += 1900;
        $mon  += 1;
        $reformated = reformatTime( { 'month' => $mon, 'day' => $mday, 'hour' => $hour, 'min' => $min, 'sec' => $sec } );
        $start_time = "$year-$reformated->{month}-$reformated->{day}T$reformated->{hour}:$reformated->{min}:$reformated->{sec}";

        ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime( $timestamp + 60 );
        $year += 1900;
        $mon  += 1;
        $reformated = reformatTime( { 'month' => $mon, 'day' => $mday, 'hour' => $hour, 'min' => $min, 'sec' => $sec } );
        $end_time   = "$year-$reformated->{month}-$reformated->{day}T$reformated->{hour}:$reformated->{min}:$reformated->{sec}";

        my $response = gcloudRequest( "https://monitoring.googleapis.com/v3/projects/$self->{project}/timeSeries?filter=metric.type=\"agent.googleapis.com/processes/count_by_state\"&interval.endTime=" . $end_time . "Z&interval.startTime=" . $start_time . "Z", $self->{token} );

        for ( @{ $response->{timeSeries} } ) {
            my $timeserie = $_;

            for ( @{ $timeserie->{points} } ) {
            my $point = $_;

            my $pretty_time = str2time( $point->{interval}->{endTime} );
            $pretty_time                                              = int($pretty_time);
            $pretty_time                                              = $pretty_time - ( $pretty_time % 60 );
            $agent{ $timeserie->{resource}->{labels}->{instance_id}.$self->{name} } = 1;
            if ( defined $data{compute}{ $timeserie->{resource}->{labels}->{instance_id}.$self->{name} }{$pretty_time} ) {
                $data{compute}{ $timeserie->{resource}->{labels}->{instance_id}.$self->{name} }{$pretty_time}{'process'}{ $timeserie->{metric}->{labels}->{state} } = $point->{value}->{doubleValue};
            }
            }
        }
        for (@metrics_agent) {
            my $metric = $_;
            $response = gcloudRequest( "https://monitoring.googleapis.com/v3/projects/$self->{project}/timeSeries?filter=metric.type=\"" . $metric->{url} . "\"&interval.endTime=" . $end_time . "Z&interval.startTime=" . $start_time . "Z", $self->{token} );

            for ( @{ $response->{timeSeries} } ) {
            my $timeserie = $_;

            for ( @{ $timeserie->{points} } ) {
                my $point = $_;

                my $pretty_time = str2time( $point->{interval}->{endTime} );
                $pretty_time = int($pretty_time);
                $pretty_time = $pretty_time - ( $pretty_time % 60 );
                if ( defined $data{compute}{ $timeserie->{resource}->{labels}->{instance_id}.$self->{name} }{$pretty_time} ) {
                $data{compute}{ $timeserie->{resource}->{labels}->{instance_id}.$self->{name} }{$pretty_time}{ $metric->{name} } = $point->{value}->{ $metric->{type} };
                }
            }
            }
        }

        my $config_compute = GCloudDataWrapper::get_conf_section('spec-compute');

        foreach my $computeKey ( %{$config_compute} ) {

            if ( !defined $config_compute->{$computeKey}->{region} ) {
            next;
            }

            if ( !defined $data{region}{ $config_compute->{$computeKey}->{region} } ) {
            $data{region}{ $config_compute->{$computeKey}->{region} }{running} = 0;
            $data{region}{ $config_compute->{$computeKey}->{region} }{stopped} = 0;
            }

            if ( defined $data{compute}{$computeKey} ) {
            if ( defined $data{region}{ $config_compute->{$computeKey}->{region} }{running} ) {
                $data{region}{ $config_compute->{$computeKey}->{region} }{running} = $data{region}{ $config_compute->{$computeKey}->{region} }{running} + 1;
            }
            else {
                $data{region}{ $config_compute->{$computeKey}->{region} }{running} = 1;
            }
            }
            else {
            if ( defined $data{region}{ $config_compute->{$computeKey}->{region} }{stopped} ) {
                $data{region}{ $config_compute->{$computeKey}->{region} }{stopped} = $data{region}{ $config_compute->{$computeKey}->{region} }{stopped} + 1;
            }
            else {
                $data{region}{ $config_compute->{$computeKey}->{region} }{stopped} = 1;
            }
            }
        }

    }


    if (%data) {
        open my $hl, ">", $conf_path . "/last_" . $self->{name} . ".json";
        print $hl "{\"timestamp\":\"$timestamp\"}";
        close $hl;
    }

    if (%agent) {
        open my $hl, ">", $agent_path . "/" . $self->{name} . ".json";
        print $hl JSON->new->pretty->encode( \%agent );
        close $hl;
    }

    $self->resetServiceAccounts();

    return \%data;
}

sub gcloudRequest {
  my $url   = shift;
  my $token = shift;

  my $api_ua = LWP::UserAgent->new(
    timeout  => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 }
  );
  $api_ua->default_header( Authorization => 'Bearer ' . $token );

  my $api_response = $api_ua->get($url);

  if ( $api_response->is_success ) {
    use Data::Dumper;

    #print Dumper($api_data);
    if( defined $api_response->content){
      my $api_data = decode_json( $api_response->content );
      return $api_data;
    }elsif (defined $api_response->items){
      my $api_data = decode_json( $api_response->items );
      return $api_data;
    }
  }
  else {
    my $api_data = decode_json("{}");
    return $api_data;

    #die;
  }
}

sub gcloudRequestTest {
  my $url   = shift;
  my $token = shift;

  my $api_ua = LWP::UserAgent->new(
    timeout  => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 }
  );
  $api_ua->default_header( Authorization => 'Bearer ' . $token );

  my $api_response = $api_ua->get($url);

  if ( $api_response->is_success ) {
    return 1;
  }
  else {
    return 0;
  }
}

sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  print STDERR "$act_time: $text : $!\n";
  return 1;
}

1;
