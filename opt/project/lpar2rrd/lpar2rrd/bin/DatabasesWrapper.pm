package DatabasesWrapper;

use strict;
use warnings;

use Data::Dumper;


sub can_update {
  my $file = shift;
  my $time = shift;
  my $reset = shift;

  my $run_conf     = 0;
  my $checkup_file = $file;
  if ( -e $checkup_file ) {
    my $timediff = get_file_timediff($checkup_file);
    if ( $timediff >= $time - 100 ) {
      $run_conf = 1;
      if (defined $reset and $reset eq "1"){
        open my $fh, '>', $checkup_file;
        print $fh "1\n";
        close $fh;
      }
    }
  }
  elsif ( !-e $checkup_file ) {
    $run_conf = 1;
    if (defined $reset and $reset eq "1"){
      open my $fh, '>', $checkup_file;
      print $fh "1\n";
      close $fh;
    }
  }

  return $run_conf;
}

sub get_file_timediff {
  my $file = shift;

  my $modtime  = ( stat($file) )[9];
  my $timediff = time - $modtime;

  return $timediff;
}

sub get_healthstatus_files {
  my $hs_dir = shift;
  my $alias  = shift;

  my $dh;
  opendir( $dh, $hs_dir ) or warn "Couldn't open dir '$hs_dir" && return "empty";

  my @files = readdir $dh;
  closedir $dh;

  #  my @files = bsd_glob("$hs_dir/*ok");
  @files = grep( /$alias/, @files );

  return \@files;
}

#takes initial values in bytes
sub get_fancy_value {
  my $value           = shift;
  my $step            = 1024;
  my @supported_types = ( $step**3, $step**4, $step**5 );
  my @supported_names = ( "GiB", "TiB", "PiB" );
  my $counter         = 0;

  foreach my $step_type (@supported_types) {
    my $decimals  = $supported_names[$counter] eq "MiB" ? 0 : 1;
    my $converted = sprintf( "%.".$decimals."f", $value / $step_type );
    if ( $converted >= $step ) {
      if ( $counter >= $#supported_types ) {
        return "$converted $supported_names[$counter]";
      }
      else {
        $counter++;
        next;
      }
    }
    else {
      return "$converted $supported_names[$counter]";
    }
  }
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

sub get_healthstatus {
  my $hw_type  = shift; 
  my $alias    = shift;

  my $inputdir = $ENV{INPUTDIR};
  my $hs_dir   = "$inputdir/tmp/health_status_summary/$hw_type";

  my @files = @{ get_healthstatus_files($hs_dir, $alias) };

  my %status;
  foreach my $file (@files) {
    my $status = basename( $file, '.' );
    if ( defined $status ) {
      my $filename = $file;
      $filename =~ s/$hs_dir\///g;
      $filename =~ s/$alias\_//g;
      $filename =~ s/\.ok//g;
      $filename =~ s/\.nok//g;
      my $hs_ip = $filename;
      my $status_bool;
      if ( $status eq "ok" ) {
        $status_bool = 1;
      }
      elsif ( $status eq "nok" ) {
        $status_bool = 0;
      }
      else {
        next;
      }

      $status{status}{$hs_ip}{metric_value} = $status_bool;
    }
  }

  return defined $status{status} ? \%status : {};
}




1;
