package PowercmcGraph;

use strict;
use warnings;

use PowercmcDataWrapper;
use Data::Dumper;
use Xorux_lib qw(error read_json);
use Xorux_lib;
use JSON;

defined $ENV{INPUTDIR} || warn("INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ") && exit 1;

my $inputdir      = $ENV{INPUTDIR};
my $bindir        = $ENV{BINDIR};
my $main_data_dir = "${inputdir}/data/PEP2";
my $wrkdir        = "${inputdir}/data";

my $instance_names;
my $can_read;
my $ref;
my $del = "XORUX";    # delimiter, this is for rrdtool print lines for clickable legend

my @_colors = get_colors();

sub tab_os_condition {
  my $type = shift;

  if ( $type eq 'aix' || $type eq 'ibmi' || $type eq 'rhelcoreos' || $type eq 'rhel' || $type eq 'sles' || $type eq 'linux_vios') {
    return 1;
  }
  else {
    return 0;
  }
}
# GLOBAL
my $cmc_id;
my $local_console;

sub signpost {
  my $item      = shift;
  my $colors    = shift;
  my $time_type = shift;
  $cmc_id    = shift;
  
  #warn "ITEM: $item, ID:  $cmc_id";

  my ( $console_name, $uid )  = PowercmcDataWrapper::decompose_id($cmc_id);
  my ( $type, $tab_type )     = PowercmcDataWrapper::decompose_item($item);

  $local_console = $console_name || "";

  my $cmd_def     = '';
  my $cmd_cdef    = '';
  my $cmd_legend  = '';
  my $cmd_params  = '';

  $cmd_params .= " --lower-limit=0.00";
  $cmd_params .= " --units-exponent=1.00";

  $cmd_legend = " COMMENT:\" \"";

  my $graph_entry;



  # DECISION TREE:
  if ( $type eq 'pep2_all' ) {
    $graph_entry = graph_all_total($console_name, $uid, $item, \@_colors, $time_type );
  }
  elsif ( $type eq 'pep2_pool' ){

    if ( $tab_type eq 'cmc_system' || $tab_type eq 'cmc_system_memory' ) {
      $graph_entry = stacked_graph("Pools", $console_name, $uid, $item, \@_colors, $time_type );
    }
    elsif ( $tab_type eq 'credit' ) {
      $graph_entry = simple_graph($console_name, $uid, $item, \@_colors );
    }
    elsif ( tab_os_condition($tab_type) ) { # aix, ibmi ...
      $graph_entry = simple_os_graph($console_name, $uid, $item, \@_colors );
      #$graph_entry = composed_os_graph($console_name, $uid, $item, \@_colors );
    }
    else {
      $graph_entry = simple_graph($console_name, $uid, $item, \@_colors );
    }

  }
  elsif ( $type eq 'pep2_system' ) {

    if ( $tab_type eq 'cmc_system' || $tab_type eq 'cmc_system_memory' ) {
      $graph_entry = simple_graph($console_name, $uid, $item, \@_colors );
    }
    else {
      $graph_entry = simple_os_graph($console_name, $uid, $item, \@_colors );
    }

  }
  elsif ( $item =~ /^powercmc/ ) {
    $graph_entry = simple_graph($console_name, $uid, $item, \@_colors );
  }
  else {
    warn "Graph decision tree: UNK: item::>${item}<::meti";
    $graph_entry = 0;
  }


  my $vertical_label   = '';

  $cmd_def    .= $graph_entry->{cmd_def};
  $cmd_cdef   .= $graph_entry->{cmd_cdef};
  $cmd_legend .= $graph_entry->{cmd_legend};
  $vertical_label = " --vertical-label=\" $graph_entry->{cmd_vlabel} \"";

  my $filepath = $graph_entry->{filename};

  if ( !-f $filepath ) {
    warn( "$filepath does not exist " . __FILE__ . ":" . __LINE__ );
  }

  my $last_update_time = 0;
  
  my $rrd_update_time;

  if (defined $filepath){
    $rrd_update_time = ( stat($filepath) )[9] ;
  }
  else{
    $rrd_update_time = 0;
  }

  if ( $rrd_update_time > $last_update_time ) {
    $last_update_time = $rrd_update_time;
  }

  my $cmd_custom_part_r;

  $cmd_custom_part_r .= $cmd_params;
  $cmd_custom_part_r .= $cmd_def;
  $cmd_custom_part_r .= $cmd_cdef;
  $cmd_custom_part_r .= $cmd_legend;

  return ($cmd_custom_part_r, $graph_entry);
}

sub cmd_start {

}


 
# SUM ALL METRICS IN LIST
sub rrd_sum_to {
  # Creates RRD graphing command to sum list of defined RRD metrics to sum_result name

  # IN: list of RRD metric names
  #     name of RRD sum metric
  # OUT: RRD command of the process

  my $metrics_to_sum_reference = shift;
  my $sum_result  = shift;
  
  my $rrd_command = 'CDEF';
  my @metrics_to_sum = @{$metrics_to_sum_reference};

  $" = ',';
  my $pluses = '';
  if (scalar(@metrics_to_sum) gt 1){
    $pluses = ',+'x int((scalar @metrics_to_sum) - 1);
  }

  my $cmd = " ${rrd_command}:${sum_result}=@{metrics_to_sum}${pluses}";
  $" = ' ';

  return $cmd;
} 


sub get_console_type_history {
  my $console = shift;
  my $sec     = shift;

  
}

sub rrd_last_update {
  my $filepath = shift;
  
  my $rrdtool = $ENV{RRDTOOL};
  
  my $rrd_was_on;
  
  # CHECK RRDp for wider range of usage
  eval{
    RRDp::start "$rrdtool"
  };

  if ($@){  $rrd_was_on = 1;}
  else{     $rrd_was_on = 0;}

  my $last_time = ${Xorux_lib::rrd_last_update($filepath)};

  if (! $rrd_was_on){
    RRDp::end;
  }

  return $last_time;
}

sub group_latest_update {
  # Nearest latest update from group
  my @rrds = @_;
  my $latest_update = 0;
  my $save_rrd = $rrds[0];

  for my $rrd (@rrds){
    my $last_time = rrd_last_update($rrd);
    if ($last_time gt $latest_update){
      $latest_update = $last_time;
      $save_rrd = $rrd;
    }

  }

  return ($latest_update, $save_rrd);
}

sub rrd_group_time_in_range {
  # Check if nearest last update is in d/w/m/(y) range
  my $range     = shift;
  my $rrds_ref  = shift;

  my @rrds = @{$rrds_ref};

  my ($latest_group_time, $latest_rrd) = group_latest_update(@rrds);

  if (time_in_range($range, $latest_group_time)){
    return 1;
  }
  else{
    return 0;
  }  

}

sub time_in_range {
  my $range = shift;
  my $rrd_time   = shift;

  my $now_time = time();
  #warn $range;
  my $range_time;

  if ( "$range" eq 'd' ) {
    $range_time = $now_time - 86400;
  }
  if ( "$range" eq "w" ) {
    $range_time = $now_time - 604800;
  }
  if ( "$range" eq "m" ) {
    $range_time = $now_time - 2764800;
  }
  if ( "$range" eq "y" ) {
    return 1
  }
  #warn "now: $now_time RANGE: $range_time";  
  if ($rrd_time gt $range_time){
    return 1;
  }
  else{
    return 0;
  }

}

sub rrd_time_in_range {
  my $range = shift;
  my $rrd   = shift;

  my $now_time = time();

  my $rrd_time = rrd_last_update($rrd);
  #my $rrd_time = ( stat($rrd) )[9];

  my $range_time;

  if ( "$range" eq 'd' ) {
    $range_time = $now_time - 86400;
  }
  if ( "$range" eq "w" ) {
    $range_time = $now_time - 604800;
  }
  if ( "$range" eq "m" ) {
    $range_time = $now_time - 2764800;
  }
  if ( "$range" eq "y" ) {
    return 1
  }
  #warn $range;
  #warn "now: $now_time rrd: $rrd_time RANGE: $range_time";  
  if ($rrd_time gt $range_time){
    return 1;
  }
  else{
    return 0;
  }

}

sub rrd_stack_cmd {
  my $p_name = shift;
  my $p_color = shift;
  my $p_label = shift;

  my $p_counter = shift;
  my $p_counter_start = shift || 0;

  my $p_command = "";

  if ( $p_counter == $p_counter_start ) {
    $p_command = rrd_make_line("AREA", $p_name, $p_color, $p_label);
  }
  else {
    $p_command = rrd_make_line("STACK", $p_name, $p_color, $p_label);
  }

  return $p_command;
}

sub graph_all_total {
  # Graphs total per pools stats
  my $console       = shift;
  my $uid           = shift;
  my $item          = shift;
  
  my $colors_ref    = shift;
  my $time_type     = shift; 
 
  my ($type, $tab_type) = PowercmcDataWrapper::decompose_item($item);

  my $legend = graph_legend($tab_type);
  my $section = PowercmcDataWrapper::get_tabs_section($tab_type);  
  my %console_section_id_name = PowercmcDataWrapper::console_structure();
  
  my %console_history; 

  #-----------------------------------------------------------------------------------------------
 
  my $color;
  my $metric_counter = 0;
  my $color_counter = 0; 

  my $rrd;
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = "";

  my %type_tab_name_metric = give_type_tab_name_metric();
    
  #-----------------------------------------------------------------------------------------------
  
  my @system_uuids;

  my @console_names = sort keys %console_section_id_name;

  my @pool_ids; 
  my %pool_rrds;

  my @latest_rrds = ();

  # Next problem: array of ids -> array of rrd names
  for my $console_name (@console_names){
    %console_history = PowercmcDataWrapper::console_history($wrkdir, $console_name); 

    if ($section eq "Pools"){
      my @IDS;
      @IDS = sort keys %{$console_history{Pools}};
      for my $ID (@IDS){
        my @rrd_list = ();
        push(@pool_ids, $ID);
        push(@rrd_list, "${inputdir}/data/PEP2/${console_name}/${section}_${ID}.rrd");
        
        my $lapdate;
        ( $lapdate , $rrd ) = group_latest_update(@rrd_list);
        
        push(@latest_rrds, $rrd);
        $pool_rrds{$console_name}{$ID} = \@rrd_list; 
      }
    }
    elsif($section eq "Systems"){
      %console_history = PowercmcDataWrapper::console_history($wrkdir, $console_name); 
      
      for my $pool_id (sort keys %{$console_history{Pools}}){
        my @rrd_list = ();
        my @IDS;
        for my $system_uuid (keys %{$console_history{Pools}{$pool_id}{Systems}}){
          push (@IDS, $system_uuid);
        }
        for my $ID (@IDS){
          push (@rrd_list, "${inputdir}/data/PEP2/${console_name}/${section}_${ID}.rrd");
        }
        
        my $lapdate;
        ( $lapdate , $rrd ) = group_latest_update(@rrd_list);
        
        push(@latest_rrds, $rrd);
        $pool_rrds{$console_name}{$pool_id} = \@rrd_list; 
        push(@pool_ids, $pool_id);
      }
    }

  }

  #-----------------------------------------------------------------------------------------------
  
  $cmd_params .= " --lower-limit=0.00";
  $cmd_params .= " --alt-y-grid";
  $cmd_legend .= " COMMENT:\\n";


  my %type_metric = (
    "total_credit"  => 'reserve_1',
    "total_cpu"     => 'utilizedProcUnits',
  );

  my $pool_counter = 0;
  for my $console_name (sort keys %pool_rrds) {

    for my $pool_id (sort keys %{$pool_rrds{$console_name}}) {
      $pool_counter++;
      
      # check time and kill here
      my @rrd_group_to_check = @{$pool_rrds{$console_name}{$pool_id}};
      my @rrd_list = @{$pool_rrds{$console_name}{$pool_id}}; 
      next if (! rrd_group_time_in_range( $time_type, \@rrd_group_to_check ));
 
      my $command = "";
      $cmd_def .= "\n";
    
     
      my $rrd_metricname = $type_metric{$tab_type};
      my @rrd_metrics_to_sum = ();

      for $rrd (@rrd_list){ 
        # in: rrd, metric name (one per rrd), metric counter
        # ret: RRD CMD, RRD named metrics list, metric_counter
        # same names in RRD => unique name list
        $cmd_def .= " DEF:name-$metric_counter-$rrd_metricname=\"$rrd\":$rrd_metricname:AVERAGE";
        $cmd_def .= "\n";
        push (@rrd_metrics_to_sum, "name-$metric_counter-$rrd_metricname");
        $metric_counter++;
      }

      ## CDEF: metrics -> clean metrics
      my @checked_metrics_to_sum = ();
      for my $metric_to_sum (@rrd_metrics_to_sum){
        my $clean_metric_name = "clean-${metric_to_sum}";
        $command .= " CDEF:${clean_metric_name}=${metric_to_sum},UN,0,${metric_to_sum},IF";
        push (@checked_metrics_to_sum, "$clean_metric_name");
      }    
      
      # CDEF: UN checker: 0 => all UN | !=0 => at least one is not UN
      my @u_checked_metrics;
      for my $metric_to_sum (@rrd_metrics_to_sum){
        my $ucheck_metric_name = "u_check-${metric_to_sum}";
        $command .= " CDEF:${ucheck_metric_name}=${metric_to_sum},UN,0,1,IF";
        push (@u_checked_metrics, "$ucheck_metric_name");
      }

      $command .= rrd_sum_to(\@u_checked_metrics, "sum-u_check-${rrd_metricname}_${pool_counter}");
      $command .= rrd_sum_to(\@{checked_metrics_to_sum}, "x_sum-${rrd_metricname}_${pool_counter}");
      
      $command .= " CDEF:sum-${rrd_metricname}_${pool_counter}=sum-u_check-${rrd_metricname}_${pool_counter},0,EQ,UNKN,x_sum-${rrd_metricname}_${pool_counter},IF";
      
      #$command .= " CDEF:sum-${rrd_metricname}_${pool_counter}=x_sum-${rrd_metricname}_${pool_counter},0,EQ,UNKN,x_sum-${rrd_metricname}_${pool_counter},IF";
      
      $cmd_cdef .= $command;     
      $cmd_cdef .= "\n";

    }
  }
  $pool_counter = 0;

  for my $console_name (sort keys %pool_rrds) {
    %console_history = PowercmcDataWrapper::console_history($wrkdir, $console_name); 

    for my $pool_id (sort keys %{$pool_rrds{$console_name}}) {
      $pool_counter++;
      my $rrd_metricname = $type_metric{$tab_type};
      
      $color = get_color( $colors_ref, $color_counter );
      $color_counter++;
 
      my @rrd_group_to_check = @{$pool_rrds{$console_name}{$pool_id}};
      next if (! rrd_group_time_in_range( $time_type, \@rrd_group_to_check ));
 
 
      my $pool_name = $console_history{Pools}{$pool_id}{Name};
      my $console_alias = $console_section_id_name{$console_name}{Alias}; 
      my $label   = get_formatted_label_val("$console_alias\\:$pool_name");

      #-----------------------------------------------------------------------------------------------
      my $cmd_printer = "";
      my $print_name = "sum-${rrd_metricname}_${pool_counter}";
      my $decimals = $legend->{decimals};

      $cmd_printer .= " LINE1:${print_name}" . "$color:\" $label\"";
      $cmd_printer .= "\n";
  
      $cmd_printer .= make_prints_with_legend($print_name, $decimals, $item, $label, $color, $tab_type);

      #-----------------------------------------------------------------------------------------------
      $cmd_legend .= $cmd_printer;
  
      $metric_counter++;
    }
  } 

  my $lapdate;
  ( $lapdate , $rrd ) = group_latest_update(@latest_rrds);

  my %command_hash = (
    filename        => $rrd,     
    header          => "$legend->{header}", 
    reduced_header  => "$legend->{header}", 
    cmd_params      => $cmd_params,
    cmd_def         => $cmd_def, 
    cmd_cdef        => $cmd_cdef,           
    cmd_legend      => $cmd_legend,        
    cmd_vlabel      => "$legend->{v_label}"
  );

  return \%command_hash;

}

sub stacked_graph {
  my $data_section  = shift; 
  my $console       = shift;
  my $uid           = shift;
  my $item          = shift;
  my $colors_ref    = shift;
  my $time_type     = shift; 
  
  my %console_section_id_name = PowercmcDataWrapper::console_structure();

  my ($type, $tab_type) = PowercmcDataWrapper::decompose_item($item);
  my $section = PowercmcDataWrapper::get_types_section($type);
  my %type_tab_name_metric = give_type_tab_name_metric();

  $type = 'pep2_system';

  my $color;
  my $metric_counter = 0;
  my $color_counter = 0; 

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = "";
  
  my @rrd_list = PowercmcDataWrapper::list_rrds("systems", $console);

  if ( $tab_type eq "cmc_system_memory" ) {
    @rrd_list = PowercmcDataWrapper::list_rrds("systems_os", $console);
  }

  my ( $lapdate , $rrd ) = group_latest_update(@rrd_list);

  my %console_history;
  my @system_uuids;

  # get historical uuid list by section -> move to PowercmcDataWrapper 
  # Historical console structure
  if ( $data_section eq "Systems" ){

    %console_history = PowercmcDataWrapper::console_history($wrkdir, $console); 
    for my $system_uuid (keys %{$console_history{Systems}}){
      push (@system_uuids, $system_uuid);
    }
  }
  elsif ( $data_section eq "Pools" ){

    %console_history = PowercmcDataWrapper::console_history($wrkdir, $console);

    for my $system_uuid (keys %{$console_history{Pools}{$uid}{Systems}}){
      push (@system_uuids, $system_uuid);
    }

  }

  my %checker = ();
  for my $sys_uuid ( @system_uuids ) {
    $checker{$sys_uuid} = 1;
  }

  #-----------------------------------------------------------------------------------------------
  #$tab_type = 'cmc_system';

  my @named_metrics;
  @named_metrics = keys %{ $type_tab_name_metric{$type}{$tab_type} };
  @named_metrics = sort { lc($a) cmp lc($b) } @named_metrics;

  my @named_metrics_to_sum = ('Base', 'Installed');
  my @named_metrics_to_stack = ('Utilized');

  if ( $tab_type eq "cmc_system_memory" ) {
    @named_metrics_to_stack = ('Usage');
  }
  #'Installed' => 'proc_installed',
  #'Utilized'  => 'utilizedProcUnits', 
  #'Total'     => 'totalProcUnits'
  my $legend = graph_legend($tab_type);
  
  #-----------------------------------------------------------------------------------------------
  
  $cmd_params .= " --lower-limit=0.00";
  $cmd_params .= " --alt-y-grid";
  $cmd_legend .= " COMMENT:\\n";


  for my $named_metric (@named_metrics_to_stack) {
    my $number_to_stacking = $metric_counter;
    
    # rrds of all servers
    for $rrd (sort @rrd_list){ 
      my $rrd_metricname = $type_tab_name_metric{$type}{$tab_type}{$named_metric};
      my $uid;

      if ( $rrd =~ /Systems_(.+)\.rrd/ ) {
        $uid = $1;
        next if ( ! defined $checker{$uid} );
      }
      elsif ( $rrd =~ /SystemOS_(.+)\.rrd/ ) {
        $uid = $1;
        next if ( ! defined $checker{$uid} );
      }

      my $name = $console_history{Systems}{$uid};

      # color counted per every server == unique in all graphs
      $color = get_color( $colors_ref, $color_counter );
      $color_counter++;
        
      # rrd time check
      next if (! rrd_time_in_range( $time_type, $rrd ));
      my $label   = get_formatted_label_val("$name");
       
      my $unique_name = "$metric_counter-$rrd_metricname";
      my $def_name = "name-${unique_name}";
      my $cdef_name = "view-${unique_name}";
      
      $cmd_def .= " DEF:${def_name}=\"$rrd\":$rrd_metricname:AVERAGE";
      $cmd_def .= "\n";
    
      $cmd_cdef .= " CDEF:${cdef_name}=${def_name},$legend->{denom},/";
      $cmd_cdef .= "\n";
      

      #-----------------------------------------------------------------------------------------------
      my $cmd_printer = "";
      my $print_name = "$cdef_name";

      if ( $metric_counter == $number_to_stacking ) {
        $cmd_printer .= " AREA:$print_name" . "$color:\" $label\"";
        $cmd_printer .= "\n";
      }
      else {
        $cmd_printer .= " STACK:$print_name" . "$color:\" $label\"";
        $cmd_printer .= "\n";
      }
    
      my $decimals = $legend->{decimals};
      #my %loc_params = (
      #  'type'    => "pep2_system",
      #  'console' => $console,
      #  'uid'     => $uid,
      #);
      #my $local_link = PowercmcDataWrapper::make_link(\%loc_params);
      #$label = "<a href=\"$local_link\">$label</a>";
      $cmd_printer .= make_prints_with_legend($print_name, $decimals, $item, $label, $color, $tab_type, $uid);

      
      #-----------------------------------------------------------------------------------------------
      $cmd_legend .= $cmd_printer;
    
      $metric_counter++;
    
    }
  }

  for my $named_metric (@named_metrics_to_sum) {

    my $command = "";
    $cmd_def .= "\n";

    my $rrd_metricname = $type_tab_name_metric{$type}{$tab_type}{$named_metric};
    # DEF: metrics + RRDs
    # rrd1 => metric_list_1
    # rrd2 => metric_list_2
    my @rrd_metrics_to_sum = ();
  
    if ( $tab_type eq "cmc_system_memory" ) {
      # TODO: CHANGE THAT LOAD!
      # NOTE
      if ( $named_metric eq "Installed" ) {
        @rrd_list = PowercmcDataWrapper::list_rrds("systems", $console);
      }
      else {
        @rrd_list = PowercmcDataWrapper::list_rrds("systems_os", $console);
      }

    }

    for $rrd (@rrd_list){ 

      if ( $rrd =~ /Systems_(.+)\.rrd/ ) {
        $uid = $1;
        next if ( ! defined $checker{$uid} );
      }
      elsif ( $rrd =~ /SystemOS_(.+)\.rrd/ ) {
        $uid = $1;
        next if ( ! defined $checker{$uid} );
      }

      $cmd_def .= " DEF:name-$metric_counter-$rrd_metricname=\"$rrd\":$rrd_metricname:AVERAGE";
      $cmd_def .= "\n";
      push (@rrd_metrics_to_sum, "name-$metric_counter-$rrd_metricname");
      $metric_counter++;
    }

    # CDEF: metrics -> clean metrics
    my @checked_metrics_to_sum = ();
    for my $metric_to_sum (@rrd_metrics_to_sum){
      my $clean_metric_name = "clean-${metric_to_sum}";
      $command .= " CDEF:${clean_metric_name}=${metric_to_sum},UN,0,${metric_to_sum},IF";
      push (@checked_metrics_to_sum, "$clean_metric_name");
    }

    # CDEF: UN checker: 0 => all UN | !=0 => at least one is not UN
    my @u_checked_metrics;
    for my $metric_to_sum (@rrd_metrics_to_sum){
      my $ucheck_metric_name = "u_check-${metric_to_sum}";
      $command .= " CDEF:${ucheck_metric_name}=${metric_to_sum},UN,0,1,IF";
      push (@u_checked_metrics, "$ucheck_metric_name");
    }

    $command .= rrd_sum_to(\@u_checked_metrics, "sum-u_check-${rrd_metricname}");
    $command .= rrd_sum_to(\@{checked_metrics_to_sum}, "x_sum-${rrd_metricname}");
    
    $command .= " CDEF:sum-${rrd_metricname}=sum-u_check-${rrd_metricname},0,EQ,UNKN,x_sum-${rrd_metricname},IF";
    
    $cmd_cdef .= $command;     
    $cmd_cdef .= "\n";
    #print $command;

  }

  my %named_metric_color = (
    'Available' => '#00FF00', 
    'Base'      => '#000000', 
    'Installed' => '#00008B', 
    'Total'     => '#808080',
  );

  for my $named_metric (@named_metrics_to_sum) {
    my $rrd_metricname = $type_tab_name_metric{$type}{$tab_type}{$named_metric};
    
    if (defined $named_metric_color{$named_metric}){
      $color = $named_metric_color{$named_metric};
    }
    else{
      $color = get_color( $colors_ref, $color_counter );
      $color_counter++;
    }  
  
    my $label   = get_formatted_label_val("$named_metric");

    #-----------------------------------------------------------------------------------------------
    my $cmd_printer = "";

    my $print_name = "sum-$rrd_metricname";
    my $decimals = $legend->{decimals};

    if ( "$named_metric" eq 'Installed' && $tab_type ne "cmc_system_memory"){
      $cmd_printer .= " LINE2:${print_name}#FFFFFF:\" $label\":skipscale";
      $cmd_printer .= "\n";

      $cmd_printer .= make_prints_with_legend($print_name, $decimals, $item, $label, "", $tab_type);

    }
    else{
      $cmd_printer .= " LINE2:${print_name}" . "$color:\" $label\"";
      $cmd_printer .= "\n";

      $cmd_printer .= make_prints_with_legend($print_name, $decimals, $item, $label, $color, $tab_type);

    }
  

    #-----------------------------------------------------------------------------------------------
    $cmd_legend .= $cmd_printer;
  
    $metric_counter++;
  }
 

  $rrd       = $rrd_list[0];
  ( $lapdate , $rrd ) = group_latest_update(@rrd_list);
  
  my %command_hash = (
    filename        => $rrd,     
    header          => "$legend->{header}", 
    reduced_header  => "$legend->{header}", 
    cmd_params      => $cmd_params,
    cmd_def         => $cmd_def, 
    cmd_cdef        => $cmd_cdef,           
    cmd_legend      => $cmd_legend,        
    cmd_vlabel      => "$legend->{v_label}"
  );

  return \%command_hash;

}


sub simple_graph {
  my $console     = shift;
  my $uid         = shift;
  my $item        = shift;
  my $colors_ref  = shift;
  
  my ($type, $tab_type) = PowercmcDataWrapper::decompose_item($item);
  my %type_tab_name_metric = give_type_tab_name_metric();
  my $section = PowercmcDataWrapper::get_types_section($type);
  # get type_tabs section? 
  # could help to differentiate in case of more RRDs per section

  my $color;
  my $metric_counter = 0;
  
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = "";

  my @rrd_list  = ("${inputdir}/data/PEP2/${console}/${section}_${uid}.rrd");

  my ( $lapdate , $rrd ) = group_latest_update(@rrd_list);

  #-----------------------------------------------------------------------------------------------
  
  my @named_metrics;
  @named_metrics = keys %{ $type_tab_name_metric{$type}{$tab_type} };
  @named_metrics = sort { lc($a) cmp lc($b) } @named_metrics;
  
  my $legend = graph_legend($tab_type);
  
  #-----------------------------------------------------------------------------------------------
  
  $cmd_params .= " --lower-limit=0.00";
  $cmd_params .= " --alt-y-grid";
  $cmd_legend .= " COMMENT:\\n";
  
  my %named_metric_color = (
    'Available'   => '#00FF00', 
    'Base'        => '#000000', 
    'Installed'   => '#00008B', 
    'Total'       => '#808080',
    'Utilized'    => '#FF0000',
    'Usage'       => '#FF0000',# memory
    'AIX'         => '#00FFFF',#'#50C878', 
    'IBMi'        => '#0000FF', 
    'RHEL'        => '#EE0000',
    'VIOS'        => '#0000FF',
    'Other Linux' => '#f6c91e',
    'Linux/VIOS'  => '#f6c91e',
    'RHCOS'       => '#FF7518',
    'SLES'        => '#00FF00',
  );
  my $color_counter = 0;

  for $rrd (@rrd_list){ 
    for my $named_metric (@named_metrics) {

      if ( $named_metric =~ /Base/ || $named_metric  eq 'Usage'){
        next;
      }

      my $rrd_metricname = $type_tab_name_metric{$type}{$tab_type}{$named_metric};
      
      if (defined $named_metric_color{$named_metric}){
        $color = $named_metric_color{$named_metric};
      }
      else{
        $color = get_color( $colors_ref, $color_counter );
        $color_counter++;
      }
      
      my $label   = get_formatted_label_val("$named_metric");
       
      my $def_name  = "name-$metric_counter-$rrd_metricname";
      my $cdef_name = "view-$metric_counter-$rrd_metricname";
      
      $cmd_def .= " DEF:$def_name=\"$rrd\":$rrd_metricname:AVERAGE";
      $cmd_def .= "\n";
    
      $cmd_cdef .= " CDEF:${cdef_name}=${def_name},$legend->{denom},/";
      $cmd_cdef .= "\n";
      

      #-----------------------------------------------------------------------------------------------
      my $cmd_printer = "";
      my $print_name = $cdef_name;
      
      if ( "$named_metric" eq 'Installed' && $item =~ /pep2_system/ && !($item =~ /memory/)){
          $cmd_printer .= rrd_make_line("LINE1", $print_name, "#FFFFFF", $label, ":skipscale");
      }
      else{
        if ( $legend->{graph_type} eq "LINE1" ) {
          $cmd_printer .= rrd_make_line("LINE1", $print_name, $color, $label);
        }
        else {
          $cmd_printer .= rrd_stack_cmd($print_name, $color, $label, $metric_counter, 0);
        }
      }


      my $decimals = $legend->{decimals};

      if ( "$named_metric" eq 'Installed' && $item =~ /pep2_system/ && !($item =~ /memory/) ){
        $cmd_printer .= make_prints_with_legend($print_name, $decimals, $item, $label, "", $tab_type);
      }
      else{
        $cmd_printer .= make_prints_with_legend($print_name, $decimals, $item, $label, $color, $tab_type);
      }
    
      $cmd_legend .= $cmd_printer;
    
      $metric_counter++;
    
    }
  }

  for my $named_metric (@named_metrics) {
    my @rrd_list_use = @rrd_list;

    # Purpose of if: create Server -> Memory tab -> Base Memory line
    if ( ("$named_metric" eq 'Base' || "$named_metric" eq 'Usage') && $item =~ /pep2_system/ && ($item =~ /cmc_system_memory/)){
      @rrd_list_use  = ("${inputdir}/data/PEP2/${console}/SystemOS_${uid}.rrd");
    }

    for $rrd (@rrd_list_use){ 

      if ( $named_metric  !~ /Base/ &&  $named_metric  ne 'Usage'){
        next;
      }


      my $rrd_metricname = $type_tab_name_metric{$type}{$tab_type}{$named_metric};
      
      if (defined $named_metric_color{$named_metric}){
        $color = $named_metric_color{$named_metric};
      }
      else{
        $color = get_color( $colors_ref, $color_counter );
        $color_counter++;
      }
      
      my $label   = get_formatted_label_val("$named_metric");
       
      my $def_name  = "name-$metric_counter-$rrd_metricname";
      my $cdef_name = "view-$metric_counter-$rrd_metricname";
      
      $cmd_def .= " DEF:$def_name=\"$rrd\":$rrd_metricname:AVERAGE";
      $cmd_def .= "\n";
    
      $cmd_cdef .= " CDEF:${cdef_name}=${def_name},$legend->{denom},/";
      $cmd_cdef .= "\n";
      

      #-----------------------------------------------------------------------------------------------
      my $cmd_printer = "";
      my $print_name = $cdef_name;
      
      if ( "$named_metric" eq 'Installed' && $item =~ /pep2_system/ && !($item =~ /memory/)){
          $cmd_printer .= rrd_make_line("LINE1", $print_name, "#FFFFFF", $label, ":skipscale");
      }
      else{
        if ( $legend->{graph_type} eq "LINE1" ) {
          $cmd_printer .= rrd_make_line("LINE1", $print_name, $color, $label);
        }
        else {
          $cmd_printer .= rrd_stack_cmd($print_name, $color, $label, $metric_counter, 0);
        }
      }


      my $decimals = $legend->{decimals};

      if ( "$named_metric" eq 'Installed' && $item =~ /pep2_system/ && !($item =~ /memory/) ){
        $cmd_printer .= make_prints_with_legend($print_name, $decimals, $item, $label, "", $tab_type);
      }
      else{
        $cmd_printer .= make_prints_with_legend($print_name, $decimals, $item, $label, $color, $tab_type);
      }
    
      $cmd_legend .= $cmd_printer;
    
      $metric_counter++;
    
    }
  }

  my $local_name = "";

  my %console_section_id_name = PowercmcDataWrapper::console_structure();
  if ( defined $console_section_id_name{$console}{Systems}{$uid}{Name} ) {
    $local_name = $console_section_id_name{$console}{Systems}{$uid}{Name};
    $legend->{header} .= " : $local_name";
  }


  $rrd       = $rrd_list[0];
  ( $lapdate , $rrd ) = group_latest_update(@rrd_list);
  my %command_hash = (
    filename        => $rrd,     
    header          => "$legend->{header}", 
    reduced_header  => "$legend->{header}", 
    cmd_params      => $cmd_params,
    cmd_def         => $cmd_def, 
    cmd_cdef        => $cmd_cdef,           
    cmd_legend      => $cmd_legend,        
    cmd_vlabel      => "$legend->{v_label}"
  );

  return \%command_hash;

}

sub simple_os_graph {
  my $console     = shift;
  my $uid         = shift;
  my $item        = shift;
  my $colors_ref  = shift;
  
  my ($type, $tab_type) = PowercmcDataWrapper::decompose_item($item);
  my %type_tab_name_metric = give_type_tab_name_metric();
  my $section = PowercmcDataWrapper::get_types_section($type);

  my $color;
  my $metric_counter = 0;
  
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = "";

  my $rrd_use;

  if ( $type eq "pep2_system") {
    $rrd_use = PowercmcDataWrapper::get_rrd_path($console, "systemOS", $uid);
  }
  else {
    $rrd_use = PowercmcDataWrapper::get_rrd_path($console, "pools", $uid);
  }

  my @rrd_list  = ($rrd_use);

  my ( $lapdate , $rrd ) = group_latest_update(@rrd_list);

  #-----------------------------------------------------------------------------------------------
  
  my @named_metrics;
  @named_metrics = keys %{ $type_tab_name_metric{$type}{$tab_type} };
  @named_metrics = sort { lc($a) cmp lc($b) } @named_metrics;
  
  my $legend = graph_legend($tab_type);
  
  #-----------------------------------------------------------------------------------------------
  
  $cmd_params .= " --lower-limit=0.00";
  $cmd_params .= " --alt-y-grid";
  $cmd_legend .= " COMMENT:\\n";
  
  my %named_metric_color = (
    'AIX'         => '#00FFFF',#'#50C878', 
    'IBMi'        => '#0000FF', 
    'RHEL'        => '#EE0000',
    'VIOS'        => '#0000FF',
    'Other Linux' => '#f6c91e',
    #'RHCOS'       => '#800080',
    'RHCOS'       => '#FF7518',
    'SLES'        => '#00FF00',
  );
  my $color_counter = 0;

  # make def
  # make cdef
  # make lines and prints

  # define os sum per servers in pool
  # 
  my $number_to_stacking = $metric_counter;

  for $rrd (@rrd_list){ 
    for my $named_metric (@named_metrics) {
      my $rrd_metricname = $type_tab_name_metric{$type}{$tab_type}{$named_metric};

      if ( $named_metric =~ /Base/ ){
        next;
      }

      #warn "\n GONE THROUGHT: $rrd_metricname";
      
      if (defined $named_metric_color{$named_metric}){
        $color = $named_metric_color{$named_metric};
      }
      else{
        $color = get_color( $colors_ref, $color_counter );
        $color_counter++;
      }
      
      my $label   = get_formatted_label_val("$named_metric");
       
      my $def_name = "name-$metric_counter-$rrd_metricname";
      $cmd_def .= " DEF:${def_name}=\"$rrd\":$rrd_metricname:AVERAGE";

      $cmd_def .= "\n";
      #push (@def_names, $def_name);
      my $cdef_name = "view-$metric_counter-$rrd_metricname";
      my $denom = $legend->{denom};

      $cmd_cdef .= " CDEF:${cdef_name}=${def_name},${denom},/";
      $cmd_cdef .= "\n";
      

      #-----------------------------------------------------------------------------------------------
      my $cmd_printer = "";
      my $print_name = $cdef_name;
      my $decimals = $legend->{decimals};

      if ( $metric_counter == $number_to_stacking ) {
        $cmd_printer .= " AREA:${print_name}" . "$color:\" $label\"";
        $cmd_printer .= "\n";
      }
      else {
        $cmd_printer .= " STACK:${print_name}" . "$color:\" $label\"";
        $cmd_printer .= "\n";
      }

      $cmd_printer .= make_prints_with_legend($print_name, $decimals, $item, $label, $color, $tab_type);

      #-----------------------------------------------------------------------------------------------
      $cmd_legend .= $cmd_printer;
    
      $metric_counter++;
    
    }
  }

  for $rrd (@rrd_list){ 
    for my $named_metric (@named_metrics) {
      my $rrd_metricname = $type_tab_name_metric{$type}{$tab_type}{$named_metric};
      if ( $named_metric !~ /Base/  ){
        next;
      }
      $color = '#000000';
      
      my $label   = get_formatted_label_val("$named_metric");
       
      my $def_name = "name-$metric_counter-$rrd_metricname";
      $cmd_def .= " DEF:${def_name}=\"$rrd\":$rrd_metricname:AVERAGE";

      $cmd_def .= "\n";
      #push (@def_names, $def_name);
      my $cdef_name = "view-$metric_counter-$rrd_metricname";
      my $denom = $legend->{denom};

      $cmd_cdef .= " CDEF:${cdef_name}=${def_name},${denom},/";
      $cmd_cdef .= "\n";
      

      #-----------------------------------------------------------------------------------------------
      my $cmd_printer = "";
      my $print_name = $cdef_name;
      my $decimals = $legend->{decimals};


      $cmd_printer .= " LINE1:${print_name}" . "$color:\" $label\"";
      $cmd_printer .= "\n";        

    
      $cmd_printer .= make_prints_with_legend($print_name, $decimals, $item, $label, $color, $tab_type);
      #-----------------------------------------------------------------------------------------------
      $cmd_legend .= $cmd_printer;
    
      $metric_counter++;
    
    }
  }


  $rrd       = $rrd_list[0];
  ( $lapdate , $rrd ) = group_latest_update(@rrd_list);
  my %command_hash = (
    filename        => $rrd,     
    header          => "$legend->{header}", 
    reduced_header  => "$legend->{header}", 
    cmd_params      => $cmd_params,
    cmd_def         => $cmd_def, 
    cmd_cdef        => $cmd_cdef,           
    cmd_legend      => $cmd_legend,        
    cmd_vlabel      => "$legend->{v_label}"
  );

  return \%command_hash;

}

sub rrd_make_line {
  my $line      = shift || "LINE1";
  my $p_name    = shift || warn "No print name in command";
  my $p_color   = shift || warn "LINE $p_name not specified";
  my $p_label   = shift;
  my $additional = shift || "";

  my $command = " LINE1:${p_name}${p_color}:\" $p_label\"$additional \n";

  return $command;
}

sub make_prints_with_legend {
  my $print_name  = shift;
  my $decimals    = shift;
  my $item        = shift;
  my $label       = shift;
  my $color       = shift;
  my $tab_type    = shift;
  my $loc_uid          = shift || $label;

  my $loc_id = PowercmcDataWrapper::compose_id($local_console, $loc_uid);

  my ( $type_l, $tab_type_l )     = PowercmcDataWrapper::decompose_item($item);
  my %legend_params = ( 
    'id'    => $cmc_id,
    'type'  => $type_l,
  );
  my $leg_href = PowercmcDataWrapper::make_link(\%legend_params);
  #$label = "<a href=\"$leg_href\">$label</a>";

  my $local_command = "";
  $local_command .= " GPRINT:${print_name}:AVERAGE:\" %6.${decimals}lf\"";
  $local_command .= "\n";
  $local_command .= " GPRINT:${print_name}:MAX:\" %6.${decimals}lf\"";
  $local_command .= "\n";
  $local_command .= " PRINT:${print_name}:AVERAGE:\" %6.${decimals}lf $del $item $del $label $del $color $del $tab_type\""; 
  $local_command .= "\n";
  $local_command .= " PRINT:${print_name}:MAX:\" %6.${decimals}lf $del asd $del $loc_id $del cur_hos\"";
  $local_command .= "\n";
  $local_command .= " COMMENT:\\n";
  $local_command .= "\n";

  return $local_command;
}

sub composed_os_graph {
  my $console     = shift;
  my $uid         = shift;
  my $item        = shift;
  my $colors_ref  = shift;
  
  my ($type, $tab_type) = PowercmcDataWrapper::decompose_item($item);
  my %type_tab_name_metric = give_type_tab_name_metric();
  my $section = PowercmcDataWrapper::get_types_section($type);

  my $color;
  my $metric_counter = 0;
  
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = "";

  

  my @servers_on_pool = PowercmcDataWrapper::listofrom($console, "servers", "pool", $uid);
  my @rrd_list;

  for my $server_on_pool (@servers_on_pool) {
    my $rrd_use = PowercmcDataWrapper::get_rrd_path($console, "systemOS", $server_on_pool);
    push (@rrd_list, $rrd_use);   
  }

  my ( $lapdate , $rrd ) = group_latest_update(@rrd_list);

  #-----------------------------------------------------------------------------------------------
  
  my @named_metrics;
  @named_metrics = keys %{ $type_tab_name_metric{$type}{$tab_type} };
  @named_metrics = sort { lc($a) cmp lc($b) } @named_metrics;
  
  my $legend = graph_legend($tab_type);
  
  #-----------------------------------------------------------------------------------------------
  
  $cmd_params .= " --lower-limit=0.00";
  $cmd_params .= " --alt-y-grid";
  $cmd_legend .= " COMMENT:\\n";
  
  my %named_metric_color = (
    'Available' => '#00FF00', 
    'Base'      => '#000000', 
    'Installed' => '#00008B', 
    'Total'     => '#808080',
    'Utilized'  => '#FF0000',
  );
  my $color_counter = 0;

  # make def
  # make cdef
  # make lines and prints

  # define os sum per servers in pool
  # 

  for $rrd (@rrd_list){ 
    for my $named_metric (@named_metrics) {
      my $rrd_metricname = $type_tab_name_metric{$type}{$tab_type}{$named_metric};
      
      if (defined $named_metric_color{$named_metric}){
        $color = $named_metric_color{$named_metric};
      }
      else{
        $color = get_color( $colors_ref, $color_counter );
        $color_counter++;
      }
      
      my $label   = get_formatted_label_val("$named_metric");
       
      my $def_name = "name-$metric_counter-$rrd_metricname";
      $cmd_def .= " DEF:${def_name}=\"$rrd\":$rrd_metricname:AVERAGE";

      $cmd_def .= "\n";
      #push (@def_names, $def_name);
      my $cdef_name = "view-$metric_counter-$rrd_metricname";
      my $denom = $legend->{denom};

      $cmd_cdef .= " CDEF:${cdef_name}=${def_name},${denom},/";
      $cmd_cdef .= "\n";
      

      #-----------------------------------------------------------------------------------------------
      my $cmd_printer = "";
      my $print_name = $cdef_name;
      my $decimals = $legend->{decimals};

      $cmd_printer .= rrd_make_line("LINE1", $print_name, $color, $label);

      $cmd_printer .= make_prints_with_legend($print_name, $decimals, $item, $label, $color, $tab_type);
    
      #-----------------------------------------------------------------------------------------------
      $cmd_legend .= $cmd_printer;
    
      $metric_counter++;
    
    }
  }
  $rrd       = $rrd_list[0];
  ( $lapdate , $rrd ) = group_latest_update(@rrd_list);
  my %command_hash = (
    filename        => $rrd,     
    header          => "$legend->{header}", 
    reduced_header  => "$legend->{header}", 
    cmd_params      => $cmd_params,
    cmd_def         => $cmd_def, 
    cmd_cdef        => $cmd_cdef,           
    cmd_legend      => $cmd_legend,        
    cmd_vlabel      => "$legend->{v_label}"
  );

  return \%command_hash;

}

sub get_colors {
  my @colors = ( "#FF0000", "#0000FF", "#FFFF00", "#00FFFF", "#FFA500", "#00FF00", "#808080", "#63FFAC", "#B79762", "#1CE6FF", "#FF34FF", "#FF4A46", "#008941", "#006FA6", "#A30059", "#7A4900", "#0000A6", "#004D43", "#8FB0FF", "#997D87", "#5A0007", "#809693", "#1B4400", "#4FC601", "#3B5DFF", "#4A3B53", "#FF2F80", "#61615A", "#BA0900", "#6B7900", "#00C2A0", "#FFAA92", "#FF90C9", "#B903AA", "#D16100", "#000035", "#7B4F4B", "#A1C299", "#300018", "#0AA6D8", "#013349", "#00846F", "#372101", "#FFB500", "#C2FFED", "#A079BF", "#CC0744", "#C0B9B2", "#C2FF99", "#001E09", "#00489C", "#6F0062", "#0CBD66", "#EEC3FF", "#456D75", "#B77B68", "#7A87A1", "#788D66", "#885578", "#FAD09F", "#FF8A9A", "#D157A0", "#BEC459", "#456648", "#0086ED", "#886F4C", "#34362D", "#B4A8BD", "#00A6AA", "#452C2C", "#636375", "#A3C8C9", "#FF913F", "#938A81", "#575329", "#00FECF", "#B05B6F", "#8CD0FF", "#3B9700", "#04F757", "#C8A1A1", "#1E6E00", "#7900D7", "#A77500", "#6367A9", "#A05837", "#6B002C", "#772600", "#D790FF", "#9B9700", "#549E79", "#FFF69F", "#201625", "#72418F", "#BC23FF", "#99ADC0", "#3A2465", "#922329", "#5B4534", "#FDE8DC", "#404E55", "#0089A3", "#CB7E98", "#A4E804", "#324E72", "#6A3A4C", "#83AB58", "#001C1E", "#D1F7CE", "#004B28", "#C8D0F6", "#A3A489", "#806C66", "#222800", "#BF5650", "#E83000", "#66796D", "#DA007C", "#FF1A59", "#8ADBB4", "#1E0200", "#5B4E51", "#C895C5", "#320033", "#FF6832", "#66E1D3", "#CFCDAC", "#D0AC94", "#7ED379", "#012C58", "#7A7BFF", "#D68E01", "#353339", "#78AFA1", "#FEB2C6", "#75797C", "#837393", "#943A4D", "#B5F4FF", "#D2DCD5", "#9556BD", "#6A714A", "#001325", "#02525F", "#0AA3F7", "#E98176", "#DBD5DD", "#5EBCD1", "#3D4F44", "#7E6405", "#02684E", "#962B75", "#8D8546", "#9695C5", "#E773CE", "#D86A78", "#3E89BE", "#CA834E", "#518A87", "#5B113C", "#55813B", "#E704C4", "#00005F", "#A97399", "#4B8160", "#59738A", "#FF5DA7", "#F7C9BF", "#643127", "#513A01", "#6B94AA", "#51A058", "#A45B02", "#1D1702", "#E20027", "#E7AB63", "#4C6001", "#9C6966", "#64547B", "#97979E", "#006A66", "#391406", "#F4D749", "#0045D2", "#006C31", "#DDB6D0", "#7C6571", "#9FB2A4", "#00D891", "#15A08A", "#BC65E9", "#FFFFFE", "#C6DC99", "#203B3C", "#671190", "#6B3A64", "#F5E1FF", "#FFA0F2", "#CCAA35", "#374527", "#8BB400", "#797868", "#C6005A", "#3B000A", "#C86240", "#29607C", "#402334", "#7D5A44", "#CCB87C", "#B88183", "#AA5199", "#B5D6C3", "#A38469", "#9F94F0", "#A74571", "#B894A6", "#71BB8C", "#00B433", "#789EC9", "#6D80BA", "#953F00", "#5EFF03", "#E4FFFC", "#1BE177", "#BCB1E5", "#76912F", "#003109", "#0060CD", "#D20096", "#895563", "#29201D", "#5B3213", "#A76F42", "#89412E", "#1A3A2A", "#494B5A", "#A88C85", "#F4ABAA", "#A3F3AB", "#00C6C8", "#EA8B66", "#958A9F", "#BDC9D2", "#9FA064", "#BE4700", "#658188", "#83A485", "#453C23", "#47675D", "#3A3F00", "#061203", "#DFFB71", "#868E7E", "#98D058", "#6C8F7D", "#D7BFC2", "#3C3E6E", "#D83D66", "#2F5D9B", "#6C5E46", "#D25B88", "#5B656C", "#00B57F", "#545C46", "#866097", "#365D25", "#252F99", "#00CCFF", "#674E60", "#FC009C", "#92896B" );
  
  #my @colors = ( "#FF0000", "#0000FF", "#FFFF00", "#00FFFF", "#FFA500", "#00FF00", "#808080", "#1CE6FF", "#FF34FF", "#FF4A46", "#008941", "#006FA6", "#A30059", "#7A4900", "#0000A6", "#63FFAC", "#B79762", "#004D43", "#8FB0FF", "#997D87", "#5A0007", "#809693", "#1B4400", "#4FC601", "#3B5DFF", "#4A3B53", "#FF2F80", "#61615A", "#BA0900", "#6B7900", "#00C2A0", "#FFAA92", "#FF90C9", "#B903AA", "#D16100", "#000035", "#7B4F4B", "#A1C299", "#300018", "#0AA6D8", "#013349", "#00846F", "#372101", "#FFB500", "#C2FFED", "#A079BF", "#CC0744", "#C0B9B2", "#C2FF99", "#001E09", "#00489C", "#6F0062", "#0CBD66", "#EEC3FF", "#456D75", "#B77B68", "#7A87A1", "#788D66", "#885578", "#FAD09F", "#FF8A9A", "#D157A0", "#BEC459", "#456648", "#0086ED", "#886F4C", "#34362D", "#B4A8BD", "#00A6AA", "#452C2C", "#636375", "#A3C8C9", "#FF913F", "#938A81", "#575329", "#00FECF", "#B05B6F", "#8CD0FF", "#3B9700", "#04F757", "#C8A1A1", "#1E6E00", "#7900D7", "#A77500", "#6367A9", "#A05837", "#6B002C", "#772600", "#D790FF", "#9B9700", "#549E79", "#FFF69F", "#201625", "#72418F", "#BC23FF", "#99ADC0", "#3A2465", "#922329", "#5B4534", "#FDE8DC", "#404E55", "#0089A3", "#CB7E98", "#A4E804", "#324E72", "#6A3A4C", "#83AB58", "#001C1E", "#D1F7CE", "#004B28", "#C8D0F6", "#A3A489", "#806C66", "#222800", "#BF5650", "#E83000", "#66796D", "#DA007C", "#FF1A59", "#8ADBB4", "#1E0200", "#5B4E51", "#C895C5", "#320033", "#FF6832", "#66E1D3", "#CFCDAC", "#D0AC94", "#7ED379", "#012C58", "#7A7BFF", "#D68E01", "#353339", "#78AFA1", "#FEB2C6", "#75797C", "#837393", "#943A4D", "#B5F4FF", "#D2DCD5", "#9556BD", "#6A714A", "#001325", "#02525F", "#0AA3F7", "#E98176", "#DBD5DD", "#5EBCD1", "#3D4F44", "#7E6405", "#02684E", "#962B75", "#8D8546", "#9695C5", "#E773CE", "#D86A78", "#3E89BE", "#CA834E", "#518A87", "#5B113C", "#55813B", "#E704C4", "#00005F", "#A97399", "#4B8160", "#59738A", "#FF5DA7", "#F7C9BF", "#643127", "#513A01", "#6B94AA", "#51A058", "#A45B02", "#1D1702", "#E20027", "#E7AB63", "#4C6001", "#9C6966", "#64547B", "#97979E", "#006A66", "#391406", "#F4D749", "#0045D2", "#006C31", "#DDB6D0", "#7C6571", "#9FB2A4", "#00D891", "#15A08A", "#BC65E9", "#FFFFFE", "#C6DC99", "#203B3C", "#671190", "#6B3A64", "#F5E1FF", "#FFA0F2", "#CCAA35", "#374527", "#8BB400", "#797868", "#C6005A", "#3B000A", "#C86240", "#29607C", "#402334", "#7D5A44", "#CCB87C", "#B88183", "#AA5199", "#B5D6C3", "#A38469", "#9F94F0", "#A74571", "#B894A6", "#71BB8C", "#00B433", "#789EC9", "#6D80BA", "#953F00", "#5EFF03", "#E4FFFC", "#1BE177", "#BCB1E5", "#76912F", "#003109", "#0060CD", "#D20096", "#895563", "#29201D", "#5B3213", "#A76F42", "#89412E", "#1A3A2A", "#494B5A", "#A88C85", "#F4ABAA", "#A3F3AB", "#00C6C8", "#EA8B66", "#958A9F", "#BDC9D2", "#9FA064", "#BE4700", "#658188", "#83A485", "#453C23", "#47675D", "#3A3F00", "#061203", "#DFFB71", "#868E7E", "#98D058", "#6C8F7D", "#D7BFC2", "#3C3E6E", "#D83D66", "#2F5D9B", "#6C5E46", "#D25B88", "#5B656C", "#00B57F", "#545C46", "#866097", "#365D25", "#252F99", "#00CCFF", "#674E60", "#FC009C", "#92896B" );
  return @colors;
}

sub get_formatted_label {

  my $label_space = shift;

  $label_space .= " " x ( 30 - length($label_space) );

  return $label_space;
}

sub get_formatted_label_val {
  my $label_space = shift;
  if (length($label_space) < 25){
    $label_space .= " " x ( 25 - length($label_space) );
  }
  return $label_space;
}

sub get_color {
  my $colors_ref = shift;
  my $col        = shift;

  my @colors     = @{$colors_ref};
  my $color;
  my $next_index = $col % $#colors;
  $color = $colors[$next_index];
  
  return $color;
}

sub graph_legend {
  my $page = shift;

  #This defines rules for graphs in each tab
  my %legend = (
    'default' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'not_defined',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'LINE1',
      'v_label'    => 'not_defined',
      'decimals'   => '1'
    },
    'cmc_pools' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Pool',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'LINE1',
      'v_label'    => 'Memory [Memory.Minutes]',
      'decimals'   => '2'
    },
    'total_cpu' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Total CPU utilization',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'LINE1',
      'v_label'    => 'CPU Cores',
      'decimals'   => '2'
    },
    'total_credit' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Total credit consumption',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'LINE1',
      'v_label'    => 'Credits',
      'decimals'   => '3'
    },
    'memory_credit' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Pool credit consumption',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'STACK',
      'v_label'    => 'Credits',
      'decimals'   => '3'
    },
    'metered_core_minutes' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Pool metered core minutes',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'STACK',
      'v_label'    => 'Metered Core Minutes',
      'decimals'   => '1'
    },
    'metered_memory_minutes' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Pool metered memory minutes',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'STACK',
      'v_label'    => 'Metered Memory Minutes',
      'decimals'   => '1'
    },
    'credit' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Pool credit consumption',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'STACK',
      'v_label'    => 'Credit',
      'decimals'   => '3'
    },
    'cmc_pools_c' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => '',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'LINE1',
      'v_label'    => 'CPU [Core.Minutes]',
      'decimals'   => '1'
    },
    'cmc_system' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Server CPU',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'LINE1',
      'v_label'    => 'CPU [cores]',
      'decimals'   => '1'
    },
    'cmc_system_memory' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Server Memory',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'LINE1',
      'v_label'    => 'Memory [GB]',
      'decimals'   => '1'
    },
    'aix' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'AIX CPU',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'STACK',
      'v_label'    => 'CPU [Cores]',
      'decimals'   => '1'
    },
    'ibmi' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'IBMi CPU',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'STACK',
      'v_label'    => 'CPU [Cores]',
      'decimals'   => '1'
    },
    'linux_vios' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Linux/VIOS CPU',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'STACK',
      'v_label'    => 'CPU [Cores]',
      'decimals'   => '1'
    },
    'rhelcoreos' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'RHCOS CPU',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'STACK',
      'v_label'    => 'CPU [Cores]',
      'decimals'   => '1'
    },
    'rhel' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'RHEL CPU',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'STACK',
      'v_label'    => 'CPU [Cores]',
      'decimals'   => '1'
    },
    'sles' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'SLES CPU',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'STACK',
      'v_label'    => 'CPU [Cores]',
      'decimals'   => '1'
    },

  );

  if ( $legend{$page} ) {
    return $legend{$page};
  }
  else {
    return $legend{default};
  }
}

#          'Available' => 'proc_available',
#          'Installed' => 'proc_installed',
#          'Total'     => 'totalProcUnits',

sub give_type_tab_name_metric {
  my %type_tab_name_metric;

  %type_tab_name_metric = (

    'total' => {
      'total' => {
          'Utilized'  => 'utilizedProcUnits', 
          'Base'     => 'base_anyoscores',
          'Installed' => 'proc_installed',
      }
    },

    'pep2_all' => {
      'total_cpu' => {
          'Utilized'  => 'utilizedProcUnits', 
      },
      'total_credit' => {
          'Total' => 'reserve_1',
      }
    },

    'pep2_cmc_total' => {
      'cmc_total' => {
        'Available' => 'proc_available',
        'Installed' => 'proc_installed',
       }
    },
    #'cm_aix', 'cm_otherlinux',
    #'cm_sles', 'cm_vios', 'cm_ibmi',
    #'cm_rhel', 'cm_rhelcoreos', 'cm_total',
    #
    #'reserve_1', 'reserve2',
    #'reserve_3', 'reserve4',
    #'reserve_5', 'reserve6',
    #'reserve_7', 'reserve8',
    #'reserve_9', 'reserve10',

    'pep2_pool' => {
      'aix' => {
        "AIX"               => 'cm_aix',
        "Base"          => 'reserve2',
        #"Base AIX"          => 'reserve2',

      },
      'ibmi' => {
        "IBMi"              => 'cm_ibmi',
        "Base"         => 'reserve4',
        #"Base IBMi"         => 'reserve4',
      },
      'linux_vios' => {
        "VIOS"              => 'cm_vios',
        #"RHEL"              => 'cm_rhel',
        "Other Linux"       => 'cm_otherlinux',
        "Base"              => 'reserve6',
      },
      'rhel' => {
        "RHEL"              => 'cm_rhel',
        "Base"              => 'reserve_5',
      },
      'rhelcoreos' => {
        "RHCOS"             => 'cm_rhelcoreos',
        "Base"        => 'reserve8',
        #"Base RHCOS"        => 'reserve8',
      },
      'sles' => {
        "SLES"              => 'cm_sles',
        "Base"         => 'reserve10',
        #"Base SLES"         => 'reserve10',
      },

      'credit' => {
        "AIX" => 'cmc_aix',
        "IBMi" => 'cmc_ibmi',
        "RHCOS" => 'cmc_rhelcoreos',
        "RHEL" => 'cmc_rhel',
        "SLES" =>  'cmc_sles',
        "Linux/VIOS" => 'cmc_linuxvios',
        #"VIOS" => 'cmc_vios',
        #"AnyOS" => 'cmc_anyos',
        #"Total" => 'cmc_total',
        "Memory" => 'mm_credits',
      },

      'metered_core_minutes' => {
        "AIX" => 'cmm_aix',
        "IBMi" => 'cmm_ibmi',
        "RHCOS" => 'cmm_rhelcoreos',
        "RHEL" => 'cmm_rhel',
        "SLES" =>  'cmm_sles',
        "Linux/VIOS" => 'cmm_linuxvios',
        #"AnyOS" => 'cmc_anyos',
        #"Total" => 'cmc_total',
      },

      'metered_memory_minutes' => {
        "Memory" => 'mm_minutes',
      },

      'cmc_system' => {
        'Utilized'  => 'utilizedProcUnits', 
        'Base'     => 'base_anyoscores',
        'Installed' => 'proc_installed',
      },

      'cmc_system_memory' => {
        # NOTE: keep Available?
        #'Available'     => 'mem_available',
        'Base'          => 'base_memory',
        'Installed'     => 'mem_installed',
        'Usage'         => 'mem_total',
      },

      'cmc_pools' => {
        'AIX' =>'mm_aix',
        'SLES' =>'mm_sles',
        'VIOS' =>'mm_vios',
        'IBMi' =>'mm_ibmi',
        'RHEL' =>'mm_rhel',
        'RHCOS' =>'mm_rhelcoreos',
        'Total' =>'mm_total',
        'Other Linux' =>'mm_otherlinux',
      },

      'cmc_pools_c' => {
        'AIX' =>'cm_aix',
        'SLES' =>'cm_sles',
        'VIOS' =>'cm_vios',
        'IBMi' =>'cm_ibmi',
        'RHEL' =>'cm_rhel',
        'RHCOS' =>'cm_rhelcoreos',
        'Total' =>'cm_total',
        'Other Linux' =>'cm_total',
       }
    },

    'pep2_system' => {

      'cmc_system' => {
        'Utilized'  => 'utilizedProcUnits', 
        'Base'      => 'base_anyoscores',
        'Installed' => 'proc_installed',
      },

      'cmc_system_memory' => {
        # NOTE: keep Available?
        #'Available'     => 'mem_available',
        'Base'          => 'base_memory',
        'Installed'     => 'mem_installed',
        'Usage'         => 'mem_total',
      },

      'aix' => {
        "AIX" => 'core_aix',
        "Base" => 'base_core_aix',
        #"Base AIX" => 'base_core_aix',
      },
      'ibmi' => {
        "IBMi" => 'core_ibmi',
        "Base" => 'base_core_imbi',
        #"Base IBMi" => 'base_core_imbi',
      },
      'rhel' => {
        "RHEL" => 'core_rhel',
        "Base" => 'base_core_rhel',
      },
      'linux_vios' => {
        "VIOS" => 'core_vios',
        #"RHEL" => 'core_rhel',
        "Other Linux" => 'core_other_linux',
        "Base" => 'base_core_linuxvios',
        #"Base Linux/VIOS" => 'base_core_linuxvios',
      },
      'rhelcoreos' => {
        "RHCOS" => 'core_rhelcoreos',
        "Base" => 'base_core_rhcos',
        #"Base RHCOS" => 'base_core_rhel_c_os',
      },
      'sles' => {
        "SLES" => 'core_sles',
        "Base" => 'base_core_sles',
        #"Base SLES" => 'base_core_sles',
      },


    },

  );

  return %type_tab_name_metric;
}

sub file_to_string {
  my $filename = shift;
  my $json;
  open(FH, '<', $filename) or die $!;
  while(<FH>){
     $json .= $_;
  }
  close(FH);
  return $json;
}

sub get_graph_legend_template {
  my $table_part        = $_[0]; # header / row
  my $number_of_columns = $_[1] || 4;
  my $units             = $_[2] || "";
  my $headers_ref       = $_[3] || "";
  
  my @headers;
  if ($headers_ref ) {
    @headers = @{$_[3]};
  }
  else {
    @headers = ();
  }
  my $header0 = $headers[0] || "";
  my $header1 = $headers[1] || "";

  my $header_count = int($number_of_columns) - 3;
  # check number of headers

  my $table_header_ncol = "";
  if ( @headers ) {

  $table_header_ncol = <<END;
  <p class='custom0'>$units</p>
  <table class=\"tablesorter tablegend\" data-sortby='$number_of_columns'>

  <thead>

    <tr>
      <th>&nbsp;</th>
      <th class=\"sortable header toleft\">$header0</th>
END

  for ( my $i = 0; $i < $header_count; $i++){
    $table_header_ncol .= qq(      <th class=\"sortable header toleft\">$headers[$i]</th>);
  }

  $table_header_ncol .= <<END;
      <th class=\"sortable header\">Avrg&nbsp;&nbsp;&nbsp;&nbsp;</th>
      <th class=\"sortable header\">Max&nbsp;&nbsp;&nbsp;&nbsp;</th>
    </tr>

  </thead>

  <tbody>
END

  } # if ( @headers )

  my $table_header_4col = <<END;
  <p class='custom0'>$units</p>
  <table class=\"tablesorter tablegend\" data-sortby='4'>
    <thead>

      <tr>
        <th>&nbsp;</th>
        <th class=\"sortable header toleft\">$header0</th>
        <th class=\"sortable header\">Avrg&nbsp;&nbsp;&nbsp;&nbsp;</th>
        <th class=\"sortable header\">Max&nbsp;&nbsp;&nbsp;&nbsp;</th>
      </tr>

    </thead>

    <tbody>
END

  my $table_header_5col = <<END;
  <p class='custom0'>$units</p>
  <table class=\"tablesorter tablegend\" data-sortby='5'>
    <thead>
      <tr>
        <th>&nbsp;</th>
        <th class=\"sortable header toleft\">$header0</th>
        <th class=\"sortable header toleft\">$header1</th>
        <th class=\"sortable header\">Avrg&nbsp;&nbsp;&nbsp;&nbsp;</th>
        <th class=\"sortable header\">Max&nbsp;&nbsp;&nbsp;&nbsp;</th>
      </tr>
    </thead>

    <tbody>
END

# ROW: TD tag
# N col:
# 1: class=\"legsq\"
# 2: class=\"clickabletd\"
# ...: class=\"clickabletd\"
# N-1 : ""
# N   : ""

  my $table_row_4col = <<END;
      <tr>
        <td class=\"legsq\">xorux_val1_color</td>
        <td class=\"clickabletd\">xorux_lpar_name</td>
        <td>xorux_val1_avg</td>
        <td>xorux_val1_max</td>
      </tr>
END

  my $table_row_5col = <<END;
      <tr>
        <td class=\"legsq\">xorux_val1_color</td>
        <td class=\"clickabletd\">xorux_server_name</td>
        <td class=\"clickabletd\">xorux_lpar_name</td>
        <td>xorux_val1_avg</td>
        <td>xorux_val1_max</td>
      </tr>
END

  if ( $table_part eq 'row' ) {
    if ( $number_of_columns eq 4 ) {
      return $table_row_4col;
    }
    if ( $number_of_columns eq 5 ) {
      return $table_row_5col;
    }
  }
  if ( $table_part eq 'header' ) {
    if ( $number_of_columns eq 4 ) {
      return $table_header_4col;
    }
    if ( $number_of_columns eq 5 ) {
      return $table_header_5col;
    }
  }


}

1;
