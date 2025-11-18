package PowerCheck;

use warnings;
use strict;

use File::Glob qw(bsd_glob GLOB_TILDE);

# NOTE: check out configuration?
#
# CHECKED FILE:
# my $restapi_identification_file = "$wrkdir/$server_name/$hmc_host/rest_api_touch";

sub touch_identification_file {
  my $wrkdir      = shift;
  my $server_name = shift;
  my $hmc_host    = shift;
  
  my $restapi_identification_file = "$wrkdir/$server_name/$hmc_host/rest_api_touch";

  `touch $restapi_identification_file`;

}


sub power_restapi_active {
  # ! NOTE: used also in detail-graph-cgi => don't print/warn

  my $power_server = shift;
  my $wrkdir       = shift;
  my $hmc_host     = shift || '*';  # OPTIONAL - default = enforce regex

  #my $rest_api_identification_path = "$wrkdir/$power_server/*/pool_total_gauge.rrt";
  my $rest_api_identification_path  = "$wrkdir/$power_server/$hmc_host/rest_api_touch";
  my @files       = bsd_glob($rest_api_identification_path);

  my $activity_condition = 0;

  #
  # Useful for debug
  #
  #my $function_message = (caller(2))[1] ." - ". (caller(2))[3]|| "MAIN";
  #my $local_log_file = "$wrkdir/../restapi_active_check.log";
  #`touch $local_log_file`;
  #`echo "$function_message " >> $local_log_file`;
  #print("----------- $function_message checking restapi $wrkdir/$power_server \n");
  #my $rest_api_identification_path = "$wrkdir/$power_server/*/*grm";

  if ( scalar(@files) ) {
    my $newest_timediff = 86400;

    for my $file_to_check (@files) {
      # last modified time
      my $tdiff_value = Xorux_lib::file_time_diff($file_to_check);
      if ( $newest_timediff > $tdiff_value ) {
        $newest_timediff = $tdiff_value;
      }
    }

    if ($newest_timediff >= 86400) {
      $activity_condition = 0;
    }
    else {
      $activity_condition = 1;
    }
  }
  else {
    $activity_condition = 0;
  }
  #print "(RES = $activity_condition) \n";

  return $activity_condition;
}


1;
