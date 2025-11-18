use strict;
use warnings;

use Data::Dumper;
use Xorux_lib qw(error read_json write_json);
use DBI;
use HostCfg;
use PostgresDataWrapper;

my $sh_alias;

if (@ARGV) {
  $sh_alias = $ARGV[0];
}

if ( !$sh_alias ) {
  warn "PostgreSQL couldn't retrieve alias" && exit 1;
}

my $alias          = "$sh_alias";
my $inputdir       = $ENV{INPUTDIR};
my $home_dir       = "$inputdir/data/PostgreSQL";
my $act_dir        = "$home_dir/$alias";
my $iostats_dir    = "$act_dir/iostats";
my $conf_dir       = "$act_dir/Configuration";
my $hs_dir         = "$ENV{INPUTDIR}/tmp/health_status_summary";
my $hs_dir_psql    = "$hs_dir/PostgreSQL";
my $total_dir      = "$home_dir/_Totals";
my $total_conf_dir = "$total_dir/Configuration";
my %creds          = %{ HostCfg::getHostConnections("PostgreSQL") };
my $db_name        = $creds{$alias}{instance};
my $port           = $creds{$alias}{port};
my $username       = $creds{$alias}{username};
my $password       = $creds{$alias}{password};
my $ip             = $creds{$alias}{host};
my $use_whitelist  = $creds{$alias}{use_whitelist};

#warn Dumper \%creds;
my %whitelisted;

#warn $use_whitelist;
if ($use_whitelist) {
  if ( defined $creds{$alias}{dbs}[0] ) {
    foreach my $wl_db ( @{ $creds{$alias}{dbs} } ) {
      $whitelisted{$wl_db} = 1;
    }
  }
}

#warn Dumper \%whitelisted;

my @health_status;
my %db_ids;
my %arc;
$arc{hostnames}{ $creds{$alias}{uuid} }{alias} = $alias;

unless ( -d $home_dir ) {
  mkdir( $home_dir, 0755 ) || warn("Cannot mkdir $home_dir: $!") && exit 1;
}
unless ( -d $act_dir ) {
  mkdir( $act_dir, 0755 ) || warn("Cannot mkdir $act_dir: $!") && exit 1;
}
unless ( -d $iostats_dir ) {
  mkdir( $iostats_dir, 0755 ) || warn("Cannot mkdir $iostats_dir: $!") && exit 1;
}
unless ( -d $hs_dir ) {
  mkdir( $hs_dir, 0755 ) || warn("Cannot mkdir $hs_dir: $!") && exit 1;
}
unless ( -d $hs_dir_psql ) {
  mkdir( $hs_dir_psql, 0755 ) || warn("Cannot mkdir $hs_dir_psql: $!") && exit 1;
}
unless ( -d $conf_dir ) {
  mkdir( $conf_dir, 0755 ) || warn("Cannot mkdir $conf_dir: $!") && exit 1;
}
unless ( -d $total_dir ) {
  mkdir( $total_dir, 0755 ) || warn("Cannot mkdir $total_dir: $!") && exit 1;
}
unless ( -d $total_conf_dir ) {
  mkdir( $total_conf_dir, 0755 ) || warn("Cannot mkdir $total_conf_dir: $!") && exit 1;
}

my %query = (
  "_dbs"        => "SELECT datid, datname, blks_read FROM pg_stat_database;",
  "_main"       => "show all;",
  "_relations" => "SELECT nspname AS \"Namespace\", relname AS \"Name\", relkind AS \"Type\",
                           pg_relation_size(C.oid) AS \"Size\", relpages AS \"Pages\",reltuples AS \"Rows\"
                    FROM pg_class C
                    LEFT JOIN pg_namespace N ON (N.oid = C.relnamespace)
                    WHERE nspname NOT IN ('pg_catalog', 'information_schema')
                    ORDER BY pg_relation_size(C.oid) DESC
                    LIMIT 50;"
);

my %conf_sa = (
  shared_buffers       => "1",
  work_mem             => "1",
  max_connections      => "1",
  temp_buffers         => "1",
  maintenance_work_mem => "1",
  autovacuum_work_mem  => "1",
  wal_buffers          => "1",
  effective_cache_size => "1",
  random_page_cost     => "1",
  min_wal_size         => "1",
  max_wal_size         => "1",
  wal_sync_method      => "1",
  wal_buffers          => "1",
);

my %rel_types = (
  r => "ordinary table",
  i => "index",
  S => "sequence",
  v => "view",
  m => "materialized view",
  c => "composite type",
  t => "TOAST table",
  f => "foreign table",
);

my $time = time;

my @perf_types = ( "_dbs" );

my $pre_perf = get_data( "PERF", $db_name, $ip, $port, $username, $password, "skip" );

my $act_perf = make_perf($pre_perf);

my $db_longnames = rrd_check();
my $current_full_db;
my @pre_conf;
my $g_main = 0;
for my $db ( keys %{$db_longnames} ) {
  $current_full_db = $db;
  my @db_parts = split( "-", $db );
    pop(@db_parts);
    my $alm_full = join("-",@db_parts);
  next if ( !( defined $db_parts[0] ) or $db_parts[0] eq "template0" or $db_parts[0] eq "shrdrltn" );
  if ( $g_main == 0 ) {
    get_data( "CONF+", $alm_full, $ip, $port, $username, $password,undef, $db );
    $g_main = 1;
  }
  else {
    get_data( "CONF", $alm_full, $ip, $port, $username, $password,undef, $db );
  }
}

my $act_conf = make_conf( \@pre_conf );

print Dumper \$act_conf;
Xorux_lib::write_json( "$conf_dir/postgres_conf.json", $act_conf );

sub get_data {
  my $type      = shift;
  my $_db_name  = shift;
  my $_ip       = shift;
  my $_port     = shift;
  my $_username = shift;
  my $_password = shift;
  my $skip      = shift;
  my $current_full_db = shift;
  my $result;
  my $dbh = DBI->connect( "DBI:Pg:dbname=$_db_name;host=$_ip;port=$_port", "$_username", "$_password", { PrintError => 0 } );

  my $time_is_now = time;
  my $err         = 0;
  $err = DBI->errstr;
  if ( !( defined $skip ) ) {
    if ($err) {
      my @row;
      $row[0] = "PostgreSQL";
      $row[1] = "$alias";
      $row[2] = "$current_full_db";
      $row[3] = "NOT_OK";
      $row[4] = "$time_is_now";
      $row[5] = $err;
      push( @health_status, \@row );
    }
    else {
      my @row;
      $row[0] = "PostgreSQL";
      $row[1] = "$alias";
      $row[2] = "$current_full_db";
      $row[3] = "OK";
      $row[4] = "$time_is_now";
      push( @health_status, \@row );
    }
  }

  if ( !( defined $dbh ) ) {
    if ( defined $skip ) {
      warn $err;
    }
    return "empty";
  }

  if ( $type eq "PERF" ) {
    my @pre_perf;

    foreach my $_type (@perf_types) {
      if ( $_type and $query{$_type} ) {
        my $array = get_query_result( $dbh, $_type );
        my %temp_hash;
        $temp_hash{type}    = $_type;
        $temp_hash{db_name} = $_db_name;
        $temp_hash{data}    = $array;
        push( @pre_perf, \%temp_hash );
      }
    }
    return \@pre_perf;
  }
  elsif ( $type =~ /CONF/ ) {
    if ( $type eq "CONF+" ) {
      my $arr = get_query_result( $dbh, "_main" );
      my %temp_hsh;
      $temp_hsh{type}    = "_main";
      $temp_hsh{data}    = $arr;
      $temp_hsh{db_name} = $_db_name;
      push( @pre_conf, \%temp_hsh );
    }
    my $array = get_query_result( $dbh, "_relations" );
    my %temp_hash;
    $temp_hash{type}    = "_relations";
    $temp_hash{data}    = $array;
    $temp_hash{db_name} = $current_full_db;
    
    push( @pre_conf, \%temp_hash );
  }

  # clean up
  $dbh->disconnect();

  return "empty";
}

sub get_query_result {
  my $_dbh  = shift;
  my $_type = shift;
  my @array;
  my $sth = $_dbh->prepare( $query{$_type} );

  #$sth = $dbh->prepare("show all;");
  $sth->execute();

  if ( $_type eq "_main" ) {
    while ( my $ref = $sth->fetchrow_hashref() ) {
      if ( $conf_sa{ $ref->{name} } ) {
        push( @array, $ref );
      }
    }
  }
  else {
    while ( my $ref = $sth->fetchrow_hashref() ) {
      push( @array, $ref );
    }
  }

  return \@array;
}

sub make_conf {
  my $rows    = shift;
  my @r_array = @{$rows};

  my %conf;
  foreach my $row_type (@r_array) {
    if ( $row_type->{type} eq "_main" ) {
      foreach my $row ( @{ $row_type->{data} } ) {
        my %hash_row = %{$row};
        $conf{_cluster}{_main}{ $row->{name} }[0]{setting} = $row->{setting};
      }
    }
    elsif ( $row_type->{type} eq "_relations" ) {
      my $counter = 0;
      foreach my $row ( @{ $row_type->{data} } ) {
        my %hash_row = %{$row};
        $hash_row{Type} = $rel_types{ $hash_row{Type} };

        #$hash_row{Size} = to_gib($hash_row{Size});
        $conf{_cluster}{_relations}{ $row_type->{db_name} }[$counter] = \%hash_row;
        $counter++;
      }
    }
  }
  $conf{_info}{timestamp}     = time;
  $conf{_info}{readable_time} = localtime( $conf{_info}{timestamp} );
  return \%conf;
}

sub make_perf {
  my $rows    = shift;
  my @r_array = @{$rows};

  my %perf;
  foreach my $row_type (@r_array) {
    if ( $row_type->{type} eq "_dbs" ) {
      foreach my $row ( @{ $row_type->{data} } ) {
        my %hash_row = %{$row};
        my %hr_dupl  = %hash_row;
        if ( !( defined $hash_row{datname} ) ) {
          $hash_row{datname} = "shrdrltn";
        }
        delete $hr_dupl{datid};
        delete $hr_dupl{datname};
        my $accepted = 0;
        if ($use_whitelist) {
          if ( $whitelisted{ $hash_row{datname} } ) {
            $accepted = 1;
          }
        }
        else {
          $accepted = 1;
        }

        if ($accepted) {
          $perf{_dbs}{"$hash_row{datname}-$hash_row{datid}"} = \%hr_dupl;
          my $uuid = PostgresDataWrapper::md5_string("$alias-$hash_row{datname}-$hash_row{datid}");
          $arc{hostnames}{ $creds{$alias}{uuid} }{_dbs}{$uuid}{label}    = $hash_row{datname};
          $arc{hostnames}{ $creds{$alias}{uuid} }{_dbs}{$uuid}{id}       = $hash_row{datid};
          $arc{hostnames}{ $creds{$alias}{uuid} }{_dbs}{$uuid}{filename} = "$hash_row{datname}-$hash_row{datid}";
          $db_ids{ $hash_row{datid} }                                    = "$hash_row{datname}-$hash_row{datid}";
        }
      }
    }
  }

  $perf{_info}{timestamp}     = time;
  $perf{_info}{readable_time} = localtime( $perf{_info}{timestamp} );

  return \%perf;
}

sub table2hash {
  my $data = shift;

  $data =~ s/ //g;
  $data =~ s/\|/;;;/g;
  my @data_rows = split( "\n", $data );
  my $header    = shift @data_rows;
  shift @data_rows;
  my @header_sp = split( ";;;", $header );

  my @rows;
  foreach my $row (@data_rows) {
    my %hash;
    my @atoms = split( ";;;", $row );

    if ( $#atoms == $#header_sp ) {
      for ( my $i = 0; $i <= $#atoms; $i++ ) {
        $hash{ $header_sp[$i] } = $atoms[$i];
      }
      push( @rows, \%hash );
    }
  }
  return \@rows;
}

sub round {
  my $value    = shift;
  my $decimals = shift;

  return $value = sprintf( "%." . "$decimals" . "f", $value );
}

# transforms given gmtime to UTC #
sub gmtime2utc {
  my ( $sec, $min, $hour, $mday, $mon, $year, $secbool ) = @_;
  $year += 1900;
  $mon  += 1;
  $mon  = sprintf( "%02d", $mon );
  $mday = sprintf( "%02d", $mday );
  $hour = sprintf( "%02d", $hour );
  $min  = sprintf( "%02d", $min );
  if ( defined $secbool and $secbool == 1 ) {
    return "$year-$mon-$mday" . "T" . "$hour:$min:$sec" . "Z";
  }
  else {
    return "$year-$mon-$mday" . "T" . "$hour:$min:00Z";
  }
}

sub rrd_check {
  my %_empty_dbs;
  for my $id ( keys %db_ids ) {
    $_empty_dbs{ $db_ids{$id} } = {};
  }
  return \%_empty_dbs;
}

sub filetime {
  my ( $sec, $min, $hour, $mday, $mon, $year ) = ( localtime( $time - 120 ) );
  my $utctime = gmtime2utc( $sec, $min, $hour, $mday, $mon, $year );
  $utctime = substr( $utctime, 0, -4 );
  $utctime =~ s/-//g;
  $utctime =~ s/://g;
  $utctime =~ s/T/_/g;

  return $utctime;
}

sub to_gib {
  my $value = shift;
  my $GiB   = 1073741824;
  if ( !( defined $value ) or $value eq 0 ) {
    return 0;
  }
  return sprintf( "%.1f", ( $value / $GiB ) );
}

sub to_tib {
  my $value = shift;
  my $GiB   = 1073741824;
  if ( !( defined $value ) or $value eq 0 ) {
    return 0;
  }
  return sprintf( "%.3f", ( ( $value / $GiB ) / 1024 ) );
}
