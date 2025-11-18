package PowercmcDataWrapper;

use strict;
use warnings;

use Data::Dumper;
use Xorux_lib qw(error read_json);
use Digest::MD5 qw(md5 md5_hex md5_base64);
use JSON;
use HostCfg;

defined $ENV{INPUTDIR} || warn("INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ") && exit 1;

my $DEBUG = 0;

my $inputdir  = $ENV{INPUTDIR};
my $home_dir  = "$inputdir/data/PEP2";
my $tmpdir    = "$inputdir/tmp";
my $wrkdir    = "$inputdir/data";

my $global_id_delimiter = "___";
my $item_delimiter_a = "_";
my $item_delimiter_b = "__";

# ITEM
sub make_item {
  my $pred      = "powercmc";
  my $type      = shift;
  my $tab_type  = shift;

  return "${pred}${item_delimiter_a}${type}${item_delimiter_b}${tab_type}";
}

sub decompose_item {
  my $item = shift;

  my $pred = "powercmc";

  my $type      = "";
  my $tab_type  = "";

  if ( $item =~ /${pred}${item_delimiter_a}(.+)${item_delimiter_b}(.+)/ ) {
    $type     = $1;
    $tab_type = $2;
  }

  return ($type, $tab_type);
}


sub compose_id {
  # CGIs id should be uniquely composed from console, pool id, server uuid | partition uuid
  # then it will be possible to translate both sides: composites <-> composition
  # inverse: decompose_id($id)
  my $console           = shift || "none";
  my $console_unique_id = shift || "";

  my $delimiter = $global_id_delimiter;
  
  my $id = "";

  if ( $console ) {
    $id .= "$console";
  }
  else {
    return "none";
  }

  if ( $console_unique_id ){
    $id .= "${delimiter}${console_unique_id}"
  }

  return $id;
}

sub decompose_id {
  # CGIs id should be uniquely composed from console, pool id, server uuid | partition uuid
  # then it will be possible to translate both sides: composites <-> composition
  # inverse: decompose_id($id)
  my $id = shift || "";

  if ( ! $id || $id eq "none" ) {
    return ("", "");
  }

  # FLOW:
  # ADD: try 2 x delimiters = console + uid + partition
  # 1 x delimiter = console + uid
  # 0 x delimiter = console

  my $delimiter = $global_id_delimiter;

  my $console = "";
  my $console_unique_id = "";

  if ( $id =~ /$delimiter/ ) {
    if ( $id =~ /(.+)${delimiter}(.+)/ ) {
      $console = $1;
      $console_unique_id = $2;
    }
  }
  else {
    $console = $id;
  }
  
  return ( $console, $console_unique_id );
}

sub make_link {
  my %parameters;
  %parameters = %{$_[0]};
  # %parameters has keys:
  # type
  # uid
  # id
  # console
  

  my $base = '/lpar2rrd-cgi/detail.sh';
  my $platform_cmc = "PowerCMC";

  my $link = $base;
  $link .= "?platform=${platform_cmc}";

  my $type;
  my $id;

  if ( defined $parameters{type} && $parameters{type} ) {
    $type = $parameters{type};
  }
  else {
    #type unspecified
  }

  if ( ! defined $parameters{uid} ) {
    $parameters{uid} = "";
  }

  if ( defined $parameters{id} ) {
    $id = $parameters{id};
  }
  elsif ( defined $parameters{console} && $parameters{console} ) {
    $id = compose_id( $parameters{console}, $parameters{uid} );
  }
  else {
    $id = '';
  }

  if ( $type ) {
    $link .= "&type=$type";
  }

  if ( $id ) {
    $link .= "&id=$id";
  }

  return $link;
}

sub configured {
  my %host_hash = %{HostCfg::getHostConnections("IBM Power CMC")};
  my @console_list = sort keys %host_hash;

  if (scalar @console_list){
    return 1;
  }
  else{
    return 0;
  }
}

sub tab_section {
  my %translate_type = (
    "total_credit"  => "Pools",
    "total_cpu"     => "Systems",
  );

  return %translate_type;
}

sub get_tabs_section {
  my $tab_type = shift;
  my %translate_type = tab_section();

  if ( defined $translate_type{$tab_type} ){
    return $translate_type{$tab_type};
  }
  else {
    warn "sub get_tabs_section: UNK: type::>$tab_type<::epyt";
    return "";
  }
}

sub type_section {
  my %type_section = (
    "pep2_tags"   => "Tags",
    "pep2_pool"   => "Pools",
    "pep2_system" => "Systems",
  );

  return %type_section;
}

sub get_sections_type {
  my $section = shift;

  my %section_type = (
    "Tags"    =>  "pep2_tags",
    "Pools"   =>  "pep2_pool",
    "Systems" =>  "pep2_system",
    "SysOS"   =>  "pep2_system",
    "Console" =>  "pep2_cmc_overview",
  );

  if ( defined $section_type{$section} ) {
    return $section_type{$section};
  }
  else {
    warn "UNKNOWN SECTION";
    return "";
  }
}

sub get_types_section {
  my $type = shift;

  my %type_section = type_section();

  if ( defined $type_section{$type} ) {
    return $type_section{$type};
  }
  else {
    #warn "get_types_section: UNK: type::>$type<::epyt";
    return "";
  }
}

sub power_configured {
  # no power -> no power menu -> no cmc menu
  my %host_hash = %{HostCfg::getHostConnections("IBM Power Systems")};
  my @console_list = sort keys %host_hash;

  if (scalar @console_list){
    return 1;
  }
  else{
    return 0;
  }
}

sub console_structure {
  my $wrkdir = shift || "$inputdir/data";

  my $consoles_file = "${wrkdir}/PEP2/console_section_id_name.json";

  my $json;
  my %console_id_name;

  if ( -f "$consoles_file") {
    
    %console_id_name = %{decode_json(file_to_string("$consoles_file"))};
    
    return %console_id_name;
  }
  else{
    return ();
  }
  
}

sub load_credit_file {
  my $frequency = shift;
  my $console   = shift;
  my $pool_id   = shift;

  my $pool_budget_file = "$inputdir/data/PEP2/$console/CreditUsage_${frequency}_${pool_id}.json";
  my %pool_budget = ();

  if ( -f "$pool_budget_file") {
    %pool_budget = %{decode_json(file_to_string("$pool_budget_file"))};
  }

  return %pool_budget;
}

sub file_to_string {
  my $filename = shift;
  my $json;
  my $local_t = localtime();

  open(FH, '<', $filename) || Xorux_lib::error( " Can't open: $filename : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  while(<FH>){
     $json .= $_;
  }

  close(FH);
  return $json;
}

sub console_history {
  # TODO: extend historical data
  my $wrkdir        = shift;
  my $console_name  = shift;

  my $hist_file = "${wrkdir}/PEP2/${console_name}/history.json";
  my $json;
  my %console_history;
  
  if ( -f "$hist_file") {
    %console_history = %{decode_json(file_to_string("$hist_file"))};
  }

  return %console_history;
  
}

# use list of | from
sub consoles_uuid_rrd {
  # ALL EXISTING OR ALL ACTIVE?
  my $console = shift;
  
  my %uuid_rrdfile = ();
  my @uuid_list;
  my @file_list = ();
  # Systems_(.+).rrd
  for my $filename (@file_list){
    if ( $filename =~ /Systems_(.+).rrd/ ){
      $uuid_rrdfile{$1} = $filename;
    }
  }

  return %uuid_rrdfile;
}

# add list rrds in folder
sub list_rrds {
  my $section = $_[0];
  # takes array, not optimal
  my @consoles = $_[1] || listofrom("consoles");

  my @rrds = ();

  for my $console (@consoles) {
    my @section_ids = listofrom($section, 'console', $console);
    for my $section_id (@section_ids){
      my $path = get_rrd_path($console, $section, $section_id);
      push (@rrds, $path);
    }
  }

  return @rrds;
}

sub get_rrd_path {
  my $console               = shift;
  my $section               = shift; #pools, servers, server_os
  my $section_specific_id   = shift;

  my $section_name = "";

  if ( $section eq "pools" || $section eq "Pools") {
    $section_name = "Pools";
  }
  elsif ( $section eq "systems" || $section eq "Systems") {
    $section_name = "Systems";
  }
  elsif ( $section eq "Systems_OS" || $section eq "systems_os" || $section eq "systemOS" || $section eq "SysOS" ) {
    $section_name = "SystemOS";
  }
  else {
    return "";
  }

  my $path = "${home_dir}/${console}/${section_name}_${section_specific_id}.rrd";

  return $path;
}

sub list_rrd_dir {

}

sub list_rrd_console {

}

sub listofrom {
  my $list_of             = shift;
  my $list_from           = shift || "";
  my $identificator       = shift || "";
  my $identificator_sec   = shift || "";

  my %console_id_name = console_structure();

  # of CONSOLES | POOLS | SERVERS | PARTITIONS
  # from LPAR2RRD | CONSOLE | POOL | SERVER 

  # DONE: 
  # consoles
  # pools     from console
  # servers   from console


  if ( $list_of eq "consoles") {
    my @consoles = sort keys %console_id_name;
    return @consoles;
  }

  if ( $list_of eq "pools" ) {
    if ( $list_from eq "console") {
      if ( defined $console_id_name{$identificator} ) {
        my @pools = sort keys %{$console_id_name{$identificator}{Pools}};
        return @pools;
      }
      else {
        return ();
      }

    }
  }

  if ( $list_of eq "systems" || $list_of eq "servers" || $list_of eq "systems_os" ) {
    if ( $list_from eq "console") {
      if ( defined $console_id_name{$identificator} ) {
        my @servers = sort keys %{$console_id_name{$identificator}{Systems}};
        return @servers;
      }
      else {
        return ();
      }

    }
    if ( $list_from eq "pool") {
      if ( defined $console_id_name{$identificator}{Pools}{$identificator_sec} ) {
        my @servers = sort keys %{$console_id_name{$identificator}{Systems}};
        return @servers;
      }
      else {
        return ();
      }

    }
  }

  return ();
  my $datadir;

  my @source;
  # list_of: rrd systems 
}

#sub rrd_filepath {
#  my $params = shift;
#
#  my $type      = $params->{type};
#  my $host      = $params->{id};
#
#  my $filepath  = "";
#
#  $filepath = "${wrkdir}/PEP2/${type}_${host}.rrd";
#
#  return $filepath;
#}



sub isnumber {
  my $possibly_number = shift;

  if ( $possibly_number =~ /^(\d)+([\.|\,](\d)+){0,1}$/ ) {
    return 1;
  }

  return 0;

  #
  # Following code is save of checks on isnumber, separate later
  #
  #my %testing = (
  #  "1.152" => 1,
  #  ""    => 0,
  #  "   "    => 0,
  #  "NOT digit" => 0,
  #  "12." => 0,
  #  "12.," => 0,
  #  "." => 0,
  #  ".51" => 0,
  #  "2,54" => 1,
  #  "2,2,5" => 0,
  #  "2,1.5" => 0,
  #  "2,1.ads5" => 0,
  #  "2,15587475" => 1,
  #  ",15587475" => 0,
  #);
  #
  #for my $test_value ( keys %testing ) {
  #  #print "V: $test_value \n";
  #  my $result = PowercmcDataWrapper::isnumber($test_value);
  #
  #  if ( $result eq $testing{$test_value} ) {
  #    #print "R: $result E: $testing{$test_value} - OK \n"
  #  }
  #  else {
  #    print "V: $test_value \n";
  #    print "R: $result E: $testing{$test_value} - NOK ----------------------- \n"
  #  }
  #}
  #
}

sub basename {
  my $full      = shift;
  my $separator = shift;
  my $out       = "";

  #my $length = length($full);
  if ( defined $separator and defined $full and index( $full, $separator ) != -1 ) {
    $out = substr( $full, length($full) - index( reverse($full), $separator ), length($full) );
    return $out;
  }
  return $full;
}

#sub print_mem_size{
## Performance measurement
#  my $object = shift;
#  my $name = shift || '';
#  use Devel::Size qw(size total_size);
#
#  print "\n";
#  if ($name){
#    print "\nMeasurement of $name";
#  }
#
#  my $use_size = size($object);
#  print "\nSIZE: $use_size\n";
#  my $total_size = total_size($object);
#  print "TOTAL SIZE: $total_size\n";
#  print "\n";
#
#}

sub make_csv {
  # uses structures prepared for tables to make CSV
  my $table_keys_ref    = shift;
  my $table_header_ref  = shift;
  my $table_body_ref    = shift;

  my @table_keys_raw  = @{$table_keys_ref};
  my %table_header    = %{$table_header_ref};
  my @table_body      = @{$table_body_ref};

  my @table_keys;
  my $csv_sep = ';';

  for my $table_key (@table_keys_raw){
    # for table prepared data: remove tag marks
    $table_key =~ s/_href//;
    push (@table_keys, $table_key);
  }

  my @csv_lines = ();
  my @csv_line = ();  
  
  # MAKE HEADER
  for my $key (@table_keys){
    push (@csv_line, "$table_header{$key}"); 
  }
  
  my $csv_line_string = join ($csv_sep, @csv_line);
  push (@csv_lines, "$csv_line_string");

  # MAKE BODY
  for my $ref_body_part (@table_body){
    my %body_part = %{$ref_body_part};
    @csv_line = ();

    for my $key (@table_keys){
      push (@csv_line, "$body_part{$key}");
    } 
    
    $csv_line_string = join ($csv_sep, @csv_line);
    push (@csv_lines, "$csv_line_string");
  }

  # COMPOSE ARRAY TO TEXT
  my $text_out = join ("\n", @csv_lines);

  return $text_out;
  #print $text_out;
  #print_mem_size(\$text_out);
  #print "\n";
}

 
sub make_html_table {
  # @table_keys: list of table_KEYs to identify     
  # %table_header: PAIRS { table_KEY : header_name } 
  # @table_body: ARRAY OF HASHES WITH PAIRS { table_KEY : table_value }
  
  my $table_keys_ref    = shift;
  my $table_header_ref  = shift;
  my $table_body_ref    = shift;
  my $sort_by           = shift || "";
  my $tfoot_ref         = shift || "";

  my @table_keys   = @{$table_keys_ref};
  my %table_header = %{$table_header_ref};
  my @table_body   = @{$table_body_ref};
  my @table_foot;
  
  if ( $tfoot_ref ) {
    @table_foot = @{$tfoot_ref};
  }

  my $table = "";
  if ( $sort_by ) {
    $table .= ' <table class="tabconfig tablesorter powersrvcfg" data-sortby="'."$sort_by".'" >';
  }
  else {
    $table .= ' <table class="tabconfig tablesorter powersrvcfg" >';
  }
  # HEAD
  $table .= ' <thead>';
  $table .= '  <tr>';

  for my $table_key (@table_keys){
    $table .= qq(   <th align="left" class="sortable" valign="center">$table_header{$table_key}</th>);
  }

  $table .= '  </tr> ';
  $table .= ' </thead>';
  
  # BODY
  $table .= ' <tbody>';

  for my $row_hash_reference (@table_body){
    $table .= '  <tr role="row">';
    my %row_hash = %{$row_hash_reference};
    for my $table_key (@table_keys){
      if (defined $row_hash{$table_key} && isnumber($row_hash{$table_key})){
        $table .= qq(   <td align="right" valign="center">$row_hash{$table_key}</td>);
      }
      elsif (defined $row_hash{$table_key}){
        $table .= qq(   <td align="left" style="text-align: left;">$row_hash{$table_key}</td>);
      }
      else{ 
        $table .= qq(   <td align="left" valign="center"></td>);
      }
    }
    $table .= '  </tr>';
  }

  $table .= " </tbody>\n";

  # TFOOT:
  if ( $tfoot_ref ) {
    $table .= " <tfoot>\n";

    for my $row_hash_reference (@table_foot){
      $table .= '  <tr style="border-top: 2px solid #6a838f; border-bottom: 2px solid #6a838f;" >';
      my %row_hash = %{$row_hash_reference};
      for my $table_key (@table_keys){
        if (defined $row_hash{$table_key} && Xorux_lib::isdigit($row_hash{$table_key})){
          $table .= qq(   <td align="right" valign="center"><strong>$row_hash{$table_key}</strong></td>);
        }
        elsif (defined $row_hash{$table_key}){
          $table .= qq(   <td align="left" valign="center"><strong>$row_hash{$table_key}</strong></td>);
        }
        else{ 
          $table .= qq(   <td align="left" valign="center"></td>);
        }
      }
      $table .= '  </tr>';
    }

    $table .= " </tfoot>\n";
  }

  $table .= " </table>\n";
  
  return $table;
}

#sub testing_create_table_data{
#  my @table_keys   = ('id1', 'id2', 'id3');
#  my %table_header = (
#    'id1' => 'ID1',
#    'id2' => 'ID2',
#    'id3' => 'ID3'
#  );
#  my @table_body;
#  
#  my @ids = ('a','b','c','d','e');
#  my @secondary_ids;
#  
#  for my $id1 ('a','b','c','d','e'){
#    for my $id2 ('al','be','ga','de'){
#
#      $id2 .= "$id1";
#
#      my $id3 = "${id1}${id2}";
#
#      my %row_hash;
#
#      $row_hash{id1} = $id1;        
#      $row_hash{id2} = $id2;        
#      $row_hash{id3} = $id3;        
#        
#      push (@table_body, \%row_hash);
#    }
#  }
#  #----------------------------------------------------------------------------------------------  
#  return (\@table_keys, \%table_header, \@table_body); 
#  
#}

sub get_csv_filename {
  my $called_from   = shift; # detail [= detail-cgi] || create [= power_cmc_caller]
  my $type          = shift; # credit || global_overview || local_overview || base
  my $console       = shift;
  my $identifier_a  = shift || "";
  my $identifier_b  = shift || "";

  my $name_out = "";

  if ( $called_from eq "create" ) {
    $name_out = ""; # invalid options => no file created (used sub write_to_file will not write to "")
  }
  elsif ( $called_from eq "detail" ) {
    $name_out = "cmc_unknown.csv"; # non-existent file, CSV icon will not show
  }

  if ( $type eq "credit" ) {
    my $pool_name = $identifier_a;
    my $frequency = $identifier_b;

    $name_out = "cmc-credit-${console}-pool-${pool_name}-${frequency}.csv";

  }
  elsif ( $type eq "global_overview" ) {

    $name_out = "cmc-global-overview-${console}.csv";

  }
  elsif ( $type eq "local_overview") {

    $name_out = "cmc-local-overview-${console}.csv";

  }
  elsif ( $type eq "base") {

    $name_out = "cmc-base-${console}.csv";

  }
  else {
    warn "UNKNOWN CALL: $type"
  }
  

  return $name_out;
}

sub sort_table_data_body {
  # UNTESTED
  my $table_body_ref    = shift;
  my $sorting_keys_ref  = shift;

  my @table_body   = @{$table_body_ref};
  my @sorting_keys = @{$sorting_keys_ref};
  
  my @sorted_table_body = @table_body;
  
  for my $sorting_key (@sorting_keys){
    my @sorted = sort { $a->{$sorting_key} cmp $b->{$sorting_key} } @sorted_table_body;
    @sorted_table_body = @sorted;
  }
  
  print Dumper @sorted_table_body;  

  return @sorted_table_body;
}

sub get_href {
  my $section = shift;
  my $name    = shift;
  my $console = shift;
  my $uid     = shift;
  # ("Pools", $pool_name, $console, $uid)
  my $type = get_sections_type("$section");
  my $href_id = compose_id($console, $uid);

  my %pool_params = ('id' => $href_id, 'type' => $type);

  my $href   = make_link(\%pool_params);

  my $href_element = "<a href=\"$href\">$name</a>";   
  #my $href_element = "<a style=\"padding-left: 0px;\" href=\"$href\">$name</a>";   

  return $href_element;
}

sub table_data_console_overview {
  my $console = shift;

  my %console_section_id_name = console_structure();

  my @table_keys   = (
    'system_name_href',
    'pool_name_href',
    'hmc_name',
    'state',
    'number_of_partitions',
    'proc_available', 
    'base_core_any_os',
    'base_core_linuxvios',
    'proc_installed',
    'mem_available',
    'mem_installed',
    'base_memory',
  );
  
  my %table_header = (
    'hmc_uuid'=>'HMC UUID', 
    'hmc_name'=>'HMCs',
    'system_uuid'=>'System UUID',

    'system_name'=> 'Server', 
    'system_name_href'=> 'Server', 

    'pool_id'=> 'PEP2 ID', 
    'pool_name' => 'PEP2', 
    'pool_name_href' => 'PEP2', 

    'tag_id' => 'Tag ID', 
    'tag_name' => 'Tag',
    'number_of_lpars' => 'Number of LPARs',
    'proc_installed' => 'Installed Processor Units', 
    'proc_available' => 'Available Entitled Processor Units', 
    'mem_installed' => 'Installed Memory [TB]', 
    'mem_available' => 'Available Memory [TB]',
    'base_memory' => 'Base Memory [TB]',

    'state' => 'State',
    'base_cores' => 'Base Processor Units', 
    'base_core_any_os' => 'Any OS Base Cores', 
    'base_core_linuxvios' => 'Linux/VIOS Base Cores', 
    'number_of_partitions' => 'Number of Partitions'
  );
  my @table_body;
  
  #----------------------------------------------------------------------------------------------  
  # BUILD TABLE BODY -> TODO: MOVE TO PowercmcGraph.pm
  #----------------------------------------------------------------------------------------------  
  # hmc_uuid hmc_name 

  for my $id (sort keys %{$console_section_id_name{$console}{Pools}}){
    for my $system_uuid (keys %{$console_section_id_name{$console}{Pools}{$id}{Systems}}){
      my %row_hash;
      my %server_data = %{$console_section_id_name{$console}{Systems}{$system_uuid}};

      my $pool_name = $console_section_id_name{$console}{Pools}{$id}{Name};
      my $system_name = $server_data{Name};

      $row_hash{pool_id}    = $id;        
      $row_hash{pool_name}  = $pool_name;
      $row_hash{pool_name_href}  = get_href("Pools", $pool_name, $console, $id);

      $row_hash{system_uuid} = $system_uuid;        
      $row_hash{system_name} = $system_name;        
      $row_hash{system_name_href}  = get_href("Systems", $system_name, $console, $system_uuid);
      
        
      $row_hash{base_cores} = $server_data{Configuration}{base_anyoscores};
      $row_hash{base_core_any_os} = $server_data{Configuration}{base_core_any_os};
      $row_hash{base_core_linuxvios} = $server_data{Configuration}{base_core_linuxvios};

      $row_hash{number_of_vioss} = $server_data{Configuration}{NumberOfVIOSs};
             
    
      $row_hash{hmc_uuid} = "";       
      $row_hash{hmc_name} = "";        

      for my $hmc_uuid (sort keys %{$server_data{HMCs}}){ 
        $row_hash{hmc_uuid}.= "$hmc_uuid ";       
        my $hmc_name = $server_data{HMCs}{$hmc_uuid}; 
        $row_hash{hmc_name}.= "$hmc_name ";        
      }

      $row_hash{tag_id}    = "";        
      $row_hash{tag_name}  = "";        
      
      for my $tag_id (sort keys %{$server_data{Tags}}){ 
        $row_hash{tag_id}    .= "$tag_id ";        
        $row_hash{tag_name}  .= "$server_data{Tags}{$tag_id}{Name} ";        
      }

      if ( ! defined $server_data{Configuration}{NumberOfLPARs} || ! $server_data{Configuration}{NumberOfLPARs}) {
        $server_data{Configuration}{NumberOfLPARs} = 0;
      }
      
      if ( ! defined $server_data{Configuration}{NumberOfVIOSs} || ! $server_data{Configuration}{NumberOfVIOSs} ) {
        $server_data{Configuration}{NumberOfVIOSs} = 0;
      }

      $row_hash{state} = $server_data{Configuration}{State};        
      $row_hash{number_of_lpars} = $server_data{Configuration}{NumberOfLPARs};        
      $row_hash{number_of_partitions} = $server_data{Configuration}{NumberOfLPARs} + $server_data{Configuration}{NumberOfVIOSs};        
      $row_hash{proc_installed} = $server_data{Configuration}{proc_installed};        
      $row_hash{proc_available} = $server_data{Configuration}{proc_available};        
      $row_hash{mem_installed} = $server_data{Configuration}{mem_installed};        
      $row_hash{mem_available} = $server_data{Configuration}{mem_available};        
      $row_hash{base_memory} = $server_data{Configuration}{base_memory};

     # warn "VIOS: $row_hash{number_of_vioss} LPAR: $row_hash{number_of_lpars}";
      push (@table_body, \%row_hash);
    }
  }
  #----------------------------------------------------------------------------------------------  
  return (\@table_keys, \%table_header, \@table_body); 
}

sub table_of_credits {
  # Called from detail cgi
  my $frequency = shift;
  my $console   = shift;
  my $pool_id   = shift;

  my $freq_rows_ref = shift;
  my %frequency_rows = %{$freq_rows_ref};
  my %pool_budget = load_credit_file($frequency, $console, $pool_id);

  my %console_section_id_name = console_structure();

  my @table_keys   = (
    'time',
    'any_os',
    'linux_vios', 
    'aix',
    'ibmi',
    'rhel',
    'rhcos',
    'sles', 
    'os_total',
    'memory'
  );
  my %table_header = (
    'time'        => 'Start Time', 
    'ibmi'        => 'IBMi', 
    'sles'        => 'SLES', 
    'rhel'        => 'RHEL',
    'rhcos'       => 'RHCOS',
    'linux_vios'  => 'Linux/VIOS', 
    'aix'         => 'AIX', 
    'any_os'      => 'Any OS', 
    'os_total'    => 'OS TOTAL', 
    'memory'      => 'Memory',
  );

  my @table_body;
  my @times = sort keys %pool_budget;

  my %all_time_sum = (
    'ibmi'        => 0, 
    'sles'        => 0, 
    'rhel'        => 0,
    'linux_vios'  => 0, 
    'aix'         => 0, 
    'any_os'      => 0, 
    'os_total'    => 0, 
    'memory'      => 0,
  );
  

  my $row_counter = 0;

  for my $time_raw (reverse sort @times){

    if ( $row_counter == $frequency_rows{$frequency} ) {
      last;
    }
    $row_counter ++;

    my %row_hash;


    my $time_use = $time_raw;

    if ( $frequency eq "Daily" ) {
      $time_use =~ s/:..\..*//;
      $time_use =~ s/T/ /;

    }
    elsif ( $frequency eq "Weekly" ) {
      $time_use =~ s/T.*//;
    }
    elsif ( $frequency eq "Monthly" ) {
      $time_use =~ s/T.*//;
    }

    $row_hash{'time'}       = $time_use;
    $row_hash{'ibmi'}       = $pool_budget{$time_raw}{CoreMeteredCredits}{IBMi};
    $row_hash{'sles'}       = $pool_budget{$time_raw}{CoreMeteredCredits}{SLES};
    $row_hash{'rhel'}       = $pool_budget{$time_raw}{CoreMeteredCredits}{RHEL};
    $row_hash{'rhcos'}      = $pool_budget{$time_raw}{CoreMeteredCredits}{RHELCoreOS};
    $row_hash{'linux_vios'} = $pool_budget{$time_raw}{CoreMeteredCredits}{LinuxVIOS}; 
    $row_hash{'aix'}        = $pool_budget{$time_raw}{CoreMeteredCredits}{AIX};
    $row_hash{'any_os'}     = $pool_budget{$time_raw}{CoreMeteredCredits}{AnyOS};
    $row_hash{'os_total'}   = $pool_budget{$time_raw}{CoreMeteredCredits}{Total};
    $row_hash{'memory'}     = $pool_budget{$time_raw}{MemoryMeteredCredits};

    $all_time_sum{'ibmi'}       += $row_hash{ibmi}; 
    $all_time_sum{'sles'}       += $row_hash{sles}; 
    $all_time_sum{'rhel'}       += $row_hash{rhel}; 
    $all_time_sum{'rhcos'}      += $row_hash{rhcos}; 
    $all_time_sum{'linux_vios'} += $row_hash{linux_vios}; 
    $all_time_sum{'aix'}        += $row_hash{aix}; 
    $all_time_sum{'any_os'}     += $row_hash{any_os}; 
    $all_time_sum{'os_total'}   += $row_hash{os_total}; 
    $all_time_sum{'memory'}     += $row_hash{memory}; 

    push (@table_body, \%row_hash);
  }

  $all_time_sum{'time'} = "TOTAL:";
  my @table_foot;
  push (@table_foot, \%all_time_sum);

  #push (@table_body, \%all_time_sum);
  #----------------------------------------------------------------------------------------------  
  return (\@table_keys, \%table_header, \@table_body, \@table_foot, $row_counter); 
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


    warn ("${debug_time}: $function_message - $message \n");

  }
}

sub table_pep_base {
  my $console = shift;

  my %console_section_id_name = console_structure();

  my @table_keys   = (
    "pep2_href",
    "base_core_any_os",
    "base_core_aix",
    "base_core_imbi",
    "base_core_linuxvios",
    "base_core_rhel",
    "base_core_rhcos",
    "base_core_sles"
  );

  my %table_header = (
    "pep2" => 'PEP 2.0',
    "pep2_href" => 'PEP 2.0',

    "base_core_any_os" => "Any OS",
    "base_core_linuxvios" => "Linux/VIOS",
    "base_core_rhel" => "RHEL",
    "base_core_rhcos" => "RHCOS",
    "base_core_sles" => "SLES",
    "base_core_aix" => "AIX",
    "base_core_imbi" => "IBMi",
  );

  my @table_body;
  
  for my $pool_id (keys %{$console_section_id_name{$console}{Pools}}) {
    my %row_hash;

    for my $base_name ("base_core_any_os", "base_core_linuxvios", "base_core_rhel", "base_core_rhcos", "base_core_sles", "base_core_aix", "base_core_imbi"){
      $row_hash{$base_name} = $console_section_id_name{$console}{Pools}{$pool_id}{Configuration}{$base_name};
      
    }
    my $pool_name = $console_section_id_name{$console}{Pools}{$pool_id}{Name};
    $row_hash{pep2} = $pool_name;
    $row_hash{pep2_href}  = get_href("Pools", $pool_name, $console, $pool_id);


    push (@table_body, \%row_hash);
  }

  return (\@table_keys, \%table_header, \@table_body); 
}



sub table_pep_configuration {
  my $console = shift;

  my %console_section_id_name = console_structure();

  my @table_keys   = (
    'pool_name_href',
    'CurrentRemainingCreditBalance', 
    'number_of_partitions',  
    'base_core_any_os',
    'base_core_linuxvios',
    'proc_available',
    'proc_installed',
    'mem_available',
    'mem_installed',
    'base_memory',
  );

  my %table_header = (
    'hmc_uuid'=>'HMC UUID', 
    'hmc_name'=>'HMC',
    'CurrentRemainingCreditBalance' => 'Current Remaining Credit Balance',
    'base_anyoscores' => 'Base Processor Units',
    'system_uuid'=>'System UUID',
    'system_name'=> 'System',
    'pool_id'=> 'PEP2 ID',
    'base_memory'=> 'Base Memory [TB]',

    'pool_name' => 'PEP2', 
    'pool_name_href' => 'PEP2',
    'tag_id' => 'Tag ID', 
    'tag_name' => 'Tag',
    'number_of_lpars' => 'Number of LPARs',
    'proc_installed' => 'Installed Processor Units', 
    'proc_available' => 'Available Entitled Processor Units', 
    'mem_installed' => 'Installed Memory [TB]', 
    'mem_available' => 'Available Memory [TB]', 
    'number_of_partitions' => 'Number of Partitions',
    'base_core_any_os' => 'Any OS Base Cores', 
    'base_core_linuxvios' => 'Linux/VIOS Base Cores', 
  );
  my @table_body;
  
  #----------------------------------------------------------------------------------------------  
  # BUILD TABLE BODY -> TODO: MOVE TO PowercmcGraph.pm
  #----------------------------------------------------------------------------------------------  
  # hmc_uuid hmc_name 
  for my $id (keys %{$console_section_id_name{$console}{Pools}}){
    my %row_hash;

    my $pool_name = $console_section_id_name{$console}{Pools}{$id}{Name};

    $row_hash{pool_name}=$pool_name;
    $row_hash{pool_name_href}  = get_href("Pools", $pool_name, $console, $id);

    
    my %pool_data = %{$console_section_id_name{$console}{Pools}{$id}};
    
    $row_hash{system_name} = $pool_data{Name};       
    if ( ! defined $pool_data{Configuration}{NumberOfLPARs} || ! $pool_data{Configuration}{NumberOfLPARs}) {
      $pool_data{Configuration}{NumberOfLPARs} = 0;
    }
    
    if ( ! defined $pool_data{Configuration}{NumberOfVIOSs} || ! $pool_data{Configuration}{NumberOfVIOSs}) {
      $pool_data{Configuration}{NumberOfVIOSs} = 0;
    } 

    
    $row_hash{CurrentRemainingCreditBalance} = $pool_data{Configuration}{CurrentRemainingCreditBalance};        
    $row_hash{base_anyoscores} = $pool_data{Configuration}{base_anyoscores};   
    $row_hash{base_core_any_os} = $pool_data{Configuration}{base_core_any_os};  
    $row_hash{base_core_linuxvios} = $pool_data{Configuration}{base_core_linuxvios};       
    $row_hash{number_of_systems} = $pool_data{Configuration}{NumberOfLPARs};        
    $row_hash{number_of_lpars} = $pool_data{Configuration}{NumberOfLPARs};        
    $row_hash{proc_installed} = $pool_data{Configuration}{proc_installed};        
    $row_hash{proc_available} = $pool_data{Configuration}{proc_available};        
    $row_hash{mem_installed} = $pool_data{Configuration}{mem_installed};        
    $row_hash{mem_available} = $pool_data{Configuration}{mem_available};        
    $row_hash{base_memory} = $pool_data{Configuration}{base_memory};        
    $row_hash{number_of_vioss} = $pool_data{Configuration}{NumberOfVIOSs};
    $row_hash{number_of_partitions} = $pool_data{Configuration}{NumberOfLPARs} + $pool_data{Configuration}{NumberOfVIOSs} || 0;        
    #warn "VIOS: $row_hash{number_of_vioss} LPAR: $row_hash{number_of_lpars}";
    #for my $keyword (keys %row_hash){
    #  if (! $row_hash{$keyword}){
    #    $row_hash{$keyword}='NA';
    #  }
    #}
    push (@table_body, \%row_hash);
  }
  #----------------------------------------------------------------------------------------------  
  return (\@table_keys, \%table_header, \@table_body); 
}

# DEVELOPMENT PURPOSES ONLY !!!
sub links_hash {
  return ();
  exit;
# DEVELOPMENT PURPOSES ONLY !!!
# do something that mimics menu tree:
# informatively contains both:
# - menu tree (for generation)
# - links
# type => platform
#       {
#          "_total_credit":"Credit"
#       }
#        {
#           "_credit":"Credits"
#        },

my @links = [
    {
      "tabs" => [
        {"Overview" => "Overview"}
      ],
      "platform" => "PowerCMC",
      "type" => "pep2_overview",
    },
    {
      "tabs" => [
        {"_total_cpu"=>"CPU"},
        {"_total_credit"=>"Credit"},
      ],
      "platform" => "PowerCMC",
      "type" => "pep2_all",
    },
    {
       "tabs" => [
         {"_cmc_overview"=>"CMC Overview"},
       ],
       "platform" => "PowerCMC",
       "type" => "pep2_cmc_overview"
    },
    {
      "tabs" => [
        {"_cmc_system"              => "CPU"},
        {"_credit"                  => "Credits"},
        {"_metered_core_minutes"    => "Metered Core Minutes"},
        {"_metered_memory_minutes"  => "Metered Memory Minutes"},
        {"_aix"                     => "AIX"},
        {"_ibmi"                    => "IBMi"},
        {"_rhel"                    => "RHEL"},
        { "_sles"                   => "SLES"},
        {"_other_linux"             => "Other Linux"},
        {"_vios"                    => "VIOS"},
      ],
      "platform" => "PowerCMC",
      "type" => "pep2_pool",
    },
    {
       "tabs" => [
          {"_cmc_system"=>"CPU"},
          {"_cmc_system_memory"=>"Memory"},
          {"_aix" => "AIX"},
          {"_ibmi" => "IBMi"},
          {"_rhel" => "RHEL"},
          {"_sles" => "SLES"},
          {"_other_linux" => "Other Linux"},
          {"_vios" => "VIOS"},
       ],
       "platform" => "PowerCMC",
       "type" => "pep2_system"
    }
  ]

}
1;
