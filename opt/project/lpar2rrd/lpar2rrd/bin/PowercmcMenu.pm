package PowercmcMenu;

use strict;

use JSON;
use Data::Dumper;
use Xorux_lib qw(error read_json);
use Menu;
use Digest::MD5 qw(md5 md5_hex md5_base64);

my $menu = Menu->new('powercmc');

my @page_types = @{ Menu::dict($menu) };

sub create_folder {
  my $title      = shift;
  my $searchable = shift;

  #my $extra  = shift;
  my %folder = ( "folder" => "true", "title" => $title, children => [] );

  #if(!$extra){
  $folder{search} = \1 if $searchable;

  #}
  #$folder{href} = $extra if defined $extra;
  return \%folder;
}

sub get_url {

  # accepts a hash with named parameters: type, and respective url_params
  my ($args) = @_;
  my $url = "";

  foreach my $page_type (@page_types) {
    my $server = exists $args->{server} ? $args->{server} : "not_spec";
    my $host   = exists $args->{host}   ? $args->{host}   : "not_spec";
    my $id     = exists $args->{id}     ? $args->{id}     : "";
    my $url_id = "";
    $url_id = "&id=$args->{id}";
    if ( $page_type->{type} eq $args->{type} ) {
      $url =
          $page_type->{url_base} =~ /\.html$/
        ? $page_type->{url_base}
        : "$page_type->{url_base}?platform=$page_type->{platform}&type=$page_type->{type}$url_id";
      last;
    }
  }

  return $url;
}

sub get_tabs {
  my $type = shift;

  for my $page_type (@page_types) {
    if ( $page_type->{type} eq $type ) {
      return $page_type->{tabs};
    }
  }
}

sub print_menu {

  #  my $json = JSON->new->utf8->pretty;
  #  return $json->encode( \@page_types );
  return \@page_types;
}

1
