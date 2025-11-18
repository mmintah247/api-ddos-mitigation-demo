# AzureLoadDataModule.pm
# create/update RRDs with Azure metrics

package AzureLoadDataModule;

use strict;
use warnings;

use Data::Dumper;
use Date::Parse;
use RRDp;
use File::Copy qw(copy);
use Xorux_lib;
use Math::BigInt;
use POSIX;

use AzureDataWrapper;

my $rrdtool = $ENV{RRDTOOL};

my $step           = 60;
my $no_time        = $step * 7;
my $no_time_twenty = $step * 25;

my $one_minute_sample = 86400;
my $five_mins_sample  = 25920;
my $one_hour_sample   = 4320;
my $five_hours_sample = 1734;
my $one_day_sample    = 1080;

sub rrd_last_update {
  my $filepath    = shift;
  my $last_update = -1;

  RRDp::cmd qq(last "$filepath");
  eval { $last_update = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return $last_update;
}

sub update_rrd_vm {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  #check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $cpu_percent      = exists $args{cpu_usage_percent} && defined $args{cpu_usage_percent} ? $args{cpu_usage_percent} / 100 : "U";
  my $disk_read_ops    = exists $args{disk_read_ops}     && defined $args{disk_read_ops}     ? $args{disk_read_ops}           : "U";
  my $disk_write_ops   = exists $args{disk_write_ops}    && defined $args{disk_write_ops}    ? $args{disk_write_ops}          : "U";
  my $disk_read_bytes  = exists $args{disk_read_bytes}   && defined $args{disk_read_bytes}   ? $args{disk_read_bytes}         : "U";
  my $disk_write_bytes = exists $args{disk_write_bytes}  && defined $args{disk_write_bytes}  ? $args{disk_write_bytes}        : "U";
  my $network_in       = exists $args{network_in}        && defined $args{network_in}        ? $args{network_in}              : "U";
  my $network_out      = exists $args{network_out}       && defined $args{network_out}       ? $args{network_out}             : "U";
  my $mem_free         = exists $args{mem_free}          && defined $args{mem_free}          ? $args{mem_free}                : "U";
  my $mem_used         = exists $args{mem_used}          && defined $args{mem_used}          ? $args{mem_used}                : "U";

  my $values = join ":", ( $cpu_percent, $disk_read_ops, $disk_write_ops, $disk_read_bytes, $disk_write_bytes, $network_in, $network_out, $mem_free, $mem_used );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_storage {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  #check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $account_transactions    = exists $args{account_transactions}    && defined $args{account_transactions}    ? $args{account_transactions}   : "U";
  my $account_ingress         = exists $args{account_ingress}         && defined $args{account_ingress}         ? $args{account_ingress}        : "U";
  my $account_egress          = exists $args{account_egress}          && defined $args{account_egress}          ? $args{account_egress}         : "U";
  my $account_suc_server_lat  = exists $args{account_suc_server_lat}  && defined $args{account_suc_server_lat}  ? $args{account_suc_server_lat} : "U";
  my $account_suc_e2e_lat     = exists $args{account_suc_e2e_lat}     && defined $args{account_suc_e2e_lat}     ? $args{account_suc_e2e_lat}    : "U";
  my $account_availability    = exists $args{account_availability}    && defined $args{account_availability}    ? $args{account_availability}   : "U";

  my $blob_transactions    = exists $args{blob_transactions}    && defined $args{blob_transactions}    ? $args{blob_transactions}   : "U";
  my $blob_ingress         = exists $args{blob_ingress}         && defined $args{blob_ingress}         ? $args{blob_ingress}        : "U";
  my $blob_egress          = exists $args{blob_egress}          && defined $args{blob_egress}          ? $args{blob_egress}         : "U";
  my $blob_suc_server_lat  = exists $args{blob_suc_server_lat}  && defined $args{blob_suc_server_lat}  ? $args{blob_suc_server_lat} : "U";
  my $blob_suc_e2e_lat     = exists $args{blob_suc_e2e_lat}     && defined $args{blob_suc_e2e_lat}     ? $args{blob_suc_e2e_lat}    : "U";
  my $blob_availability    = exists $args{blob_availability}    && defined $args{blob_availability}    ? $args{blob_availability}   : "U";

  my $file_transactions    = exists $args{file_transactions}    && defined $args{file_transactions}    ? $args{file_transactions}   : "U";
  my $file_ingress         = exists $args{file_ingress}         && defined $args{file_ingress}         ? $args{file_ingress}        : "U";
  my $file_egress          = exists $args{file_egress}          && defined $args{file_egress}          ? $args{file_egress}         : "U";
  my $file_suc_server_lat  = exists $args{file_suc_server_lat}  && defined $args{file_suc_server_lat}  ? $args{file_suc_server_lat} : "U";
  my $file_suc_e2e_lat     = exists $args{file_suc_e2e_lat}     && defined $args{file_suc_e2e_lat}     ? $args{file_suc_e2e_lat}    : "U";
  my $file_availability    = exists $args{file_availability}    && defined $args{file_availability}    ? $args{file_availability}   : "U";

  my $queue_transactions    = exists $args{queue_transactions}    && defined $args{queue_transactions}    ? $args{queue_transactions}   : "U";
  my $queue_ingress         = exists $args{queue_ingress}         && defined $args{queue_ingress}         ? $args{queue_ingress}        : "U";
  my $queue_egress          = exists $args{queue_egress}          && defined $args{queue_egress}          ? $args{queue_egress}         : "U";
  my $queue_suc_server_lat  = exists $args{queue_suc_server_lat}  && defined $args{queue_suc_server_lat}  ? $args{queue_suc_server_lat} : "U";
  my $queue_suc_e2e_lat     = exists $args{queue_suc_e2e_lat}     && defined $args{queue_suc_e2e_lat}     ? $args{queue_suc_e2e_lat}    : "U";
  my $queue_availability    = exists $args{queue_availability}    && defined $args{queue_availability}    ? $args{queue_availability}   : "U";

  my $table_transactions    = exists $args{table_transactions}    && defined $args{table_transactions}    ? $args{table_transactions}   : "U";
  my $table_ingress         = exists $args{table_ingress}         && defined $args{table_ingress}         ? $args{table_ingress}        : "U";
  my $table_egress          = exists $args{table_egress}          && defined $args{table_egress}          ? $args{table_egress}         : "U";
  my $table_suc_server_lat  = exists $args{table_suc_server_lat}  && defined $args{table_suc_server_lat}  ? $args{table_suc_server_lat} : "U";
  my $table_suc_e2e_lat     = exists $args{table_suc_e2e_lat}     && defined $args{table_suc_e2e_lat}     ? $args{table_suc_e2e_lat}    : "U";
  my $table_availability    = exists $args{table_availability}    && defined $args{table_availability}    ? $args{table_availability}   : "U";
  
  my $used_capacity    = exists $args{used_capacity}    && defined $args{used_capacity}    ? $args{used_capacity}   : "U";

  my $blob_capacity    = exists $args{blob_capacity}    && defined $args{blob_capacity}    ? $args{blob_capacity}   : "U";
  my $blob_count    = exists $args{blob_count}    && defined $args{blob_count}    ? $args{blob_count}   : "U";
  my $container_count    = exists $args{container_count}    && defined $args{container_count}    ? $args{container_count}   : "U";

  my $file_capacity    = exists $args{file_capacity}    && defined $args{file_capacity}    ? $args{file_capacity}   : "U";
  my $file_count    = exists $args{file_count}    && defined $args{file_count}    ? $args{file_count}   : "U";
  my $file_share_count    = exists $args{file_share_count}    && defined $args{file_share_count}    ? $args{file_share_count}   : "U";
  my $file_share_snapshot_count    = exists $args{file_share_snapshot_count}    && defined $args{file_share_snapshot_count}    ? $args{file_share_snapshot_count}   : "U";
  my $file_share_snapshot_size    = exists $args{file_share_snapshot_size}    && defined $args{file_share_snapshot_size}    ? $args{file_share_snapshot_size}   : "U";
  my $file_share_capacity_quota    = exists $args{file_share_capacity_quota}    && defined $args{file_share_capacity_quota}    ? $args{file_share_capacity_quota}   : "U";

  my $queue_capacity    = exists $args{queue_capacity}    && defined $args{queue_capacity}    ? $args{queue_capacity}   : "U";
  my $queue_count    = exists $args{queue_count}    && defined $args{queue_count}    ? $args{queue_count}   : "U";
  my $queue_message_count    = exists $args{queue_message_count}    && defined $args{queue_message_count}    ? $args{queue_message_count}   : "U";

  my $table_capacity    = exists $args{table_capacity}    && defined $args{table_capacity}    ? $args{table_capacity}   : "U";
  my $table_count    = exists $args{table_count}    && defined $args{table_count}    ? $args{table_count}   : "U";
  my $table_entity_count    = exists $args{table_entity_count}    && defined $args{table_entity_count}    ? $args{table_entity_count}   : "U";


  my $values = join ":", ( 
    $account_transactions, 
    $account_ingress, 
    $account_egress, 
    $account_suc_server_lat, 
    $account_suc_e2e_lat, 
    $account_availability,

    $blob_transactions, 
    $blob_ingress, 
    $blob_egress, 
    $blob_suc_server_lat, 
    $blob_suc_e2e_lat, 
    $blob_availability,

    $file_transactions, 
    $file_ingress, 
    $file_egress, 
    $file_suc_server_lat, 
    $file_suc_e2e_lat, 
    $file_availability,

    $queue_transactions, 
    $queue_ingress, 
    $queue_egress, 
    $queue_suc_server_lat, 
    $queue_suc_e2e_lat, 
    $queue_availability,

    $table_transactions, 
    $table_ingress, 
    $table_egress, 
    $table_suc_server_lat, 
    $table_suc_e2e_lat, 
    $table_availability,

    $used_capacity,

    $blob_capacity,
    $blob_count,
    $container_count,

    $file_capacity,
    $file_count,
    $file_share_count,
    $file_share_snapshot_count,
    $file_share_snapshot_size,
    $file_share_capacity_quota,

    $queue_capacity,
    $queue_count,
    $queue_message_count,

    $table_capacity,
    $table_count,
    $table_entity_count,

    );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_app {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  #check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $cpu_time         = exists $args{cpu_time}         && defined $args{cpu_time}         ? $args{cpu_time}         : "U";
  my $requests         = exists $args{requests}         && defined $args{requests}         ? $args{requests}         : "U";
  my $read_bytes       = exists $args{read_bytes}       && defined $args{read_bytes}       ? $args{read_bytes}       : "U";
  my $write_bytes      = exists $args{write_bytes}      && defined $args{write_bytes}      ? $args{write_bytes}      : "U";
  my $read_ops         = exists $args{read_ops}         && defined $args{read_ops}         ? $args{read_ops}         : "U";
  my $write_ops        = exists $args{write_ops}        && defined $args{write_ops}        ? $args{write_ops}        : "U";
  my $received_bytes   = exists $args{received_bytes}   && defined $args{received_bytes}   ? $args{received_bytes}   : "U";
  my $sent_bytes       = exists $args{sent_bytes}       && defined $args{sent_bytes}       ? $args{sent_bytes}       : "U";
  my $http_2xx         = exists $args{http_2xx}         && defined $args{http_2xx}         ? $args{http_2xx}         : "U";
  my $http_3xx         = exists $args{http_3xx}         && defined $args{http_3xx}         ? $args{http_3xx}         : "U";
  my $http_4xx         = exists $args{http_4xx}         && defined $args{http_4xx}         ? $args{http_4xx}         : "U";
  my $http_5xx         = exists $args{http_5xx}         && defined $args{http_5xx}         ? $args{http_5xx}         : "U";
  my $response         = exists $args{response}         && defined $args{response}         ? $args{response}         : "U";
  my $connections      = exists $args{connections}      && defined $args{connections}      ? $args{connections}      : "U";
  my $filesystem_usage = exists $args{filesystem_usage} && defined $args{filesystem_usage} ? $args{filesystem_usage} : "U";

  my $values = join ":", ( $cpu_time, $requests, $read_ops, $write_ops, $read_bytes, $write_bytes, $received_bytes, $sent_bytes, $http_2xx, $http_3xx, $http_4xx, $http_5xx, $response, $connections, $filesystem_usage );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_region {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  #check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $instances_running = exists $args{instances_running} ? $args{instances_running} : "U";
  my $instances_stopped = exists $args{instances_stopped} ? $args{instances_stopped} : "U";

  my $values = join ":", ( $instances_running, $instances_stopped );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

################################################################################

sub create_rrd_vm {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_compute $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:cpu_percent:GAUGE:$no_time:0:U"
        "DS:disk_read_ops:GAUGE:$no_time:0:U"
        "DS:disk_write_ops:GAUGE:$no_time:0:U"
        "DS:disk_read_bytes:GAUGE:$no_time:0:U"
        "DS:disk_write_bytes:GAUGE:$no_time:0:U"
        "DS:network_in:GAUGE:$no_time:0:U"
        "DS:network_out:GAUGE:$no_time:0:U"
	"DS:mem_free:GAUGE:$no_time:0:U"
	"DS:mem_used:GAUGE:$no_time:0:U"
        "RRA:AVERAGE:0.5:1:$one_minute_sample"
        "RRA:AVERAGE:0.5:5:$five_mins_sample"
        "RRA:AVERAGE:0.5:60:$one_hour_sample"
        "RRA:AVERAGE:0.5:300:$five_hours_sample"
        "RRA:AVERAGE:0.5:1440:$one_day_sample"
        );

  if ( !Xorux_lib::create_check("file: $filepath, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
    warn( localtime() . ": failed to create $filepath : at " . __FILE__ . ": line " . __LINE__ );
    RRDp::end;
    RRDp::start "$rrdtool";
    return 2;
  }

  return 0;
}

sub create_rrd_storage {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_storage $filepath");

  #some metrics are shorter then in other files bcos of length limit of 19 chars
  #only other place where you need to use these shorter ones is detail-graph-cgi.pl
  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:acc_transactions:GAUGE:$no_time:0:U"
        "DS:acc_ingress:GAUGE:$no_time:0:U"
        "DS:acc_egress:GAUGE:$no_time:0:U"
        "DS:acc_suc_server_lat:GAUGE:$no_time:0:U"
        "DS:acc_suc_e2e_lat:GAUGE:$no_time:0:U"
        "DS:acc_availability:GAUGE:$no_time:0:U"
        "DS:blob_transactions:GAUGE:$no_time:0:U"
        "DS:blob_ingress:GAUGE:$no_time:0:U"
        "DS:blob_egress:GAUGE:$no_time:0:U"
        "DS:blob_suc_server_lat:GAUGE:$no_time:0:U"
        "DS:blob_suc_e2e_lat:GAUGE:$no_time:0:U"
        "DS:blob_availability:GAUGE:$no_time:0:U"
        "DS:file_transactions:GAUGE:$no_time:0:U"
        "DS:file_ingress:GAUGE:$no_time:0:U"
        "DS:file_egress:GAUGE:$no_time:0:U"
        "DS:file_suc_server_lat:GAUGE:$no_time:0:U"
        "DS:file_suc_e2e_lat:GAUGE:$no_time:0:U"
        "DS:file_availability:GAUGE:$no_time:0:U"
        "DS:queu_transactions:GAUGE:$no_time:0:U"
        "DS:queu_ingress:GAUGE:$no_time:0:U"
        "DS:queu_egress:GAUGE:$no_time:0:U"
        "DS:queu_suc_server_lat:GAUGE:$no_time:0:U"
        "DS:queu_suc_e2e_lat:GAUGE:$no_time:0:U"
        "DS:queu_availability:GAUGE:$no_time:0:U"
        "DS:tabl_transactions:GAUGE:$no_time:0:U"
        "DS:tabl_ingress:GAUGE:$no_time:0:U"
        "DS:tabl_egress:GAUGE:$no_time:0:U"
        "DS:tabl_suc_server_lat:GAUGE:$no_time:0:U"
        "DS:tabl_suc_e2e_lat:GAUGE:$no_time:0:U"
        "DS:tabl_availability:GAUGE:$no_time:0:U"
        "DS:used_capacity:GAUGE:$no_time:0:U"
        "DS:blob_capacity:GAUGE:$no_time:0:U"
        "DS:blob_count:GAUGE:$no_time:0:U"
        "DS:container_count:GAUGE:$no_time:0:U"
        "DS:file_capacity:GAUGE:$no_time:0:U"
        "DS:file_count:GAUGE:$no_time:0:U"
        "DS:file_share_count:GAUGE:$no_time:0:U"
        "DS:share_snap_count:GAUGE:$no_time:0:U"
        "DS:share_snap_size:GAUGE:$no_time:0:U"
        "DS:share_cap_quota:GAUGE:$no_time:0:U"
        "DS:queue_capacity:GAUGE:$no_time:0:U"
        "DS:queue_count:GAUGE:$no_time:0:U"
        "DS:queue_message_count:GAUGE:$no_time:0:U"
        "DS:table_capacity:GAUGE:$no_time:0:U"
        "DS:table_count:GAUGE:$no_time:0:U"
        "DS:table_entity_count:GAUGE:$no_time:0:U"
        "RRA:AVERAGE:0.5:1:$one_minute_sample"
        "RRA:AVERAGE:0.5:5:$five_mins_sample"
        "RRA:AVERAGE:0.5:60:$one_hour_sample"
        "RRA:AVERAGE:0.5:300:$five_hours_sample"
        "RRA:AVERAGE:0.5:1440:$one_day_sample"
        );

  if ( !Xorux_lib::create_check("file: $filepath, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
    warn( localtime() . ": failed to create $filepath : at " . __FILE__ . ": line " . __LINE__ );
    RRDp::end;
    RRDp::start "$rrdtool";
    return 2;
  }

  return 0;
}

sub create_rrd_app {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_app $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:cpu_time:GAUGE:$no_time:0:U"
        "DS:requests:GAUGE:$no_time:0:U"
        "DS:read_bytes:GAUGE:$no_time:0:U"
        "DS:write_bytes:GAUGE:$no_time:0:U"
        "DS:read_ops:GAUGE:$no_time:0:U"
        "DS:write_ops:GAUGE:$no_time:0:U"
        "DS:received_bytes:GAUGE:$no_time:0:U"
        "DS:sent_bytes:GAUGE:$no_time:0:U"
        "DS:http_2xx:GAUGE:$no_time:0:U"
	"DS:http_3xx:GAUGE:$no_time:0:U"
	"DS:http_4xx:GAUGE:$no_time:0:U"
	"DS:http_5xx:GAUGE:$no_time:0:U"
	"DS:response:GAUGE:$no_time:0:U"
	"DS:connections:GAUGE:$no_time:0:U"
	"DS:filesystem_usage:GAUGE:$no_time:0:U"
        "RRA:AVERAGE:0.5:1:$one_minute_sample"
        "RRA:AVERAGE:0.5:5:$five_mins_sample"
        "RRA:AVERAGE:0.5:60:$one_hour_sample"
        "RRA:AVERAGE:0.5:300:$five_hours_sample"
        "RRA:AVERAGE:0.5:1440:$one_day_sample"
        );

  if ( !Xorux_lib::create_check("file: $filepath, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
    warn( localtime() . ": failed to create $filepath : at " . __FILE__ . ": line " . __LINE__ );
    RRDp::end;
    RRDp::start "$rrdtool";
    return 2;
  }

  return 0;
}

sub create_rrd_region {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_region $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:instances_running:GAUGE:$no_time_twenty:0:U"
        "DS:instances_stopped:GAUGE:$no_time_twenty:0:U"
        "RRA:AVERAGE:0.5:1:$one_minute_sample"
        "RRA:AVERAGE:0.5:5:$five_mins_sample"
        "RRA:AVERAGE:0.5:60:$one_hour_sample"
        "RRA:AVERAGE:0.5:300:$five_hours_sample"
        "RRA:AVERAGE:0.5:1440:$one_day_sample"
        );

  if ( !Xorux_lib::create_check("file: $filepath, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
    warn( localtime() . ": failed to create $filepath : at " . __FILE__ . ": line " . __LINE__ );
    RRDp::end;
    RRDp::start "$rrdtool";
    return 2;
  }

  return 0;
}

sub touch {
  my $text = shift;

  my $version    = "$ENV{version}";
  my $basedir    = $ENV{INPUTDIR};
  my $new_change = "$basedir/tmp/$version-compute";
  my $DEBUG      = $ENV{DEBUG};

  if ( !-f $new_change ) {
    `touch $new_change`;    # tell install_html.sh that there has been a change
    if ( $text eq '' ) {
      print "touch          : $new_change\n" if $DEBUG;
    }
    else {
      print "touch          : $new_change : $text\n" if $DEBUG;
    }
  }

  return 0;
}

1;
