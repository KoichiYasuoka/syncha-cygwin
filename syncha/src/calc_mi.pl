#!/usr/bin/env perl

use strict;
use warnings;
 use utf8;
 use open ':utf8';

package CalcMI;

sub new {
    my $type = shift;
    my $self = {}; 
    bless $self;
    my $opt_ref = shift;
    my $dir = shift; # cacao:/work/ryu-i/ncv/dat/
#     my $p1 = shift; $p1 = 'Pn.cdb'  unless $p1;
#     my $p2 = shift; $p2 = 'Pcv.cdb' unless $p2;
    my $p1 = shift; $p1 = 'Pn.tsv'  unless $p1;
    my $p2 = shift; $p2 = 'Pcv.tsv' unless $p2;
    my $pz = shift; $pz = 'Pz.tsv' unless $pz;
    my $pzcv = shift; $pzcv = 'Pzcv.tsv' unless $pzcv;
    
    my %pzcv = ();
#     print STDERR $dir.'/'.$pzcv."\n";
#     open 'PZCV', $dir.'/'.$pzcv or die $!;
#     while (<PZCV>) {
# 	chomp; my ($k, $v) = split '\t', $_, 2;
# 	$pzcv{$k} = $v;
#     }
#     close PZCV;
#     $self->{pzcv} = \%pzcv;

    my %pn = ();
    open 'PN', $dir.'/'.$p1 or die $!;
    while (<PN>) {
	chomp;
	my ($k, $v) = split '\t', $_, 2;
	$pn{$k} = $v;
    }
    close PN;
    $self->{pn} = \%pn;

    my %pcv = ();
    open 'PCV', $dir.'/'.$p2 or die $!;
    while (<PCV>) {
	chomp;
	my ($k, $v) = split '\t', $_, 2;
	$pcv{$k} = $v;
    }
    close PCV;
    $self->{pcv} = \%pcv;

#     tie my %pn, 'CDB_File', $dir.'/'.$p1 or die $!;
#     $self->{pn} = \%pn;

#     tie my %pcv, 'CDB_File', $dir.'/'.$p2 or die $!;
#     $self->{pcv} = \%pcv;

    
    my @pz = ();
    open 'PZ', $dir.'/'.$pz or die $!;
    while (<PZ>) {
	my ($tmp, $pz) = split '\t', $_;
	chomp; push @pz, $pz;	
    }
    close PZ;
    $self->{pz} = \@pz;

#     open 'PZ', $dir.'/n1000.pz' or die $!;
#     my $pz = <PZ>; chomp $pz;
#     my @pz = split ' ', $pz;
#     close PZ;
#     $self->{pz} = \@pz;

    return $self;
}

sub calc_mi {
    my $self = shift;
    my ($n, $cv) = @_;
    my $pn  = $self->{pn}{$n};
    my $pcv = $self->{pcv}{$cv};

    return 0 unless $pn;
    my %pn = ();
    for (split ' ', $pn) {
	my ($id, $p) = split '\:', $_;
	$pn{$id} = $p;
    }
    return 0 unless $pcv;
    my %pcv = ();
    for (split ' ', $pcv) {
	my ($id, $p) = split '\:', $_;
	$pcv{$id} = $p;
    }
    my $zid = 0; 
    my $Pncv = 0; my $Pn = 0; my $Pcv = 0;
    for (@{$self->{pz}}) {
	my $Pz = $_;
	my $cur_pn = ($pn{$zid})? $pn{$zid} : 0;
	$Pn += $Pz*$cur_pn;
	my $cur_pcv = ($pcv{$zid})? $pcv{$zid} : 0;
	$Pcv += $Pz*$cur_pcv;
	$Pncv += $Pz*$cur_pn*$cur_pcv;
	$zid++;
    }
    return 0 unless $Pn;
    return 0 unless $Pcv;
    return 0 unless $Pncv;
    return log($Pncv/($Pn*$Pcv));
}

sub calc_prob {
    my $self = shift;
    my ($n, $cv) = @_;
    my $pn  = $self->{pn}{$n};
    my $pcv = $self->{pcv}{$cv};

    return 0 unless $pn;
    my %pn = ();
    for (split ' ', $pn) {
	my ($id, $p) = split '\:', $_;
	$pn{$id} = $p;
    }
    return 0 unless $pcv;
    my %pcv = ();
    for (split ' ', $pcv) {
	my ($id, $p) = split '\:', $_;
	$pcv{$id} = $p;
    }
    my $zid = 0; my $Pncv = 0; 
    # my $Pn = 0; my $Pcv = 0;
    for (@{$self->{pz}}) {
	my $Pz = $_;
	my $cur_pn = ($pn{$zid})? $pn{$zid} : 0;

	# $Pn += $Pz*$cur_pn;
	my $cur_pcv = ($pcv{$zid})? $pcv{$zid} : 0;

	# $Pcv += $Pz*$cur_pcv;
	$Pncv += $Pz*$cur_pn*$cur_pcv;
	$zid++;
    }
#     return 0 unless $Pn;
#     return 0 unless $Pcv;
    return 0 unless $Pncv;
    # return log($Pncv/($Pn*$Pcv));
    return $Pncv;
}

sub calc_mi_with_ref {
    my $self = shift;
    my ($n, $n2, $cv) = @_;
#    print STDERR $n."\t".$n2."\t".$cv."\n";
    my $pn   = $self->{pn}{$n};
    my $pzcv = $self->{pzcv}{$cv};
    my $pn2  = $self->{pn}{$n2};
#     my $pcv = $self->{pcv}{$cv};
    return 0 unless $pn2;
    my $pnc2v = $self->calc_prob($n2, $cv);
    my $C     = $self->calc_C($n2, $cv);
    return 0 unless $C;
    return 0 unless $pn;
    my %pn = ();
    for (split ' ', $pn) {
	my ($id, $p) = split '\:', $_;
	$pn{$id} = $p;
    }
    my %pzcv = ();
    my $ii = 0;
    for (split ' ', $pzcv) {
	$pzcv{$ii++} = $_;
    }
    my %pn2 = ();
    for (split ' ', $pn2) {
	my ($id, $p) = split '\:', $_; $pn2{$id} = $p;
    }
    my $zid = 0; 
    my $Pncv = 0; my $Pn = 0; # my $Pcv = 0;
    my $Pncncv = 0;
    for (@{$self->{pz}}) {
	my $Pz = $_;
	my $cur_pn   = ($pn{$zid})?   $pn{$zid}   : 0;
	my $cur_pzcv = ($pzcv{$zid})? $pzcv{$zid} : 0;
	$Pn += $Pz*$cur_pn;
# 	my $cur_pcv = $pcv{$zid};
# 	next unless $cur_pcv;
# 	$Pcv += $Pz*$cur_pcv;
#	$Pncv += $Pz*$cur_pn*$cur_pcv;
	my $cur_pn2  = ($pn2{$zid})?  $pn2{$zid}  : 0;
	$Pncncv += $cur_pn * ($cur_pzcv * $cur_pn2);
	$zid++;
    }
    $Pncncv = $Pncncv / $C;
    return 0 unless $Pn;
#     return 0 unless $pnc2v;
    return 0 unless $Pncncv;
#     return log($Pncv/($Pn*$Pcv));
    return log($Pncncv / $Pn);
#    return log(($Pncncv * $pnc2v) / ($Pn * $pnc2v));
}

sub calc_C {
    my $self = shift;
    my ($n, $cv) = @_;
    my $pn   = $self->{pn}{$n};
    my $pzcv = $self->{pzcv}{$cv};
#     print STDERR 'pn: '. $pn."\n";
#     print STDERR 'pzcv: '.$pzcv."\n";
    return 0 unless $pn;
    return 0 unless $pzcv;
    my %pn = ();
    for (split ' ', $pn) {
	my ($id, $p) = split '\:', $_; $pn{$id} = $p;
    }
    my %pzcv = (); my $ii = 0;
    for (split ' ', $pzcv) {
	$pzcv{$ii++} = $_;
    }
    my $zid = 0;
    my $C = 0;
    for (@{$self->{pz}}) {
	my $cur_pn   = $pn{$zid};   next unless $cur_pn;
	my $cur_pzcv = $pzcv{$zid}; next unless $cur_pzcv;
	$C += $cur_pn * $cur_pzcv;
	$zid++;
    }
    return $C;
}

sub js_v {
    my $self = shift;
    my ($v1, $v2) = @_;
    return 0 unless $self->{pzcv}{$v1};
    return 0 unless $self->{pzcv}{$v2};
    my @pi = split ' ', $self->{pzcv}{$v1}; my $p_num = @pi;
    my @pj = split ' ', $self->{pzcv}{$v2};
    my $sum = 0;
    for (my $i=0;$i<$p_num;$i++) {
	next if $pi[$i] == 0 and $pj[$i] == 0;
	my $ave = ($pi[$i] + $pj[$i])/2;
	$sum += $pi[$i] * log($pi[$i]/$ave) if ($pi[$i] and $pi[$i] != 0);
	$sum += $pj[$i] * log($pj[$i]/$ave) if ($pj[$i] and $pj[$i] != 0);
    }
    $sum = $sum / 2;
    return $sum;
}

sub cos_v {
    my $self = shift;
    my ($v1, $v2) = @_;
    return 0 unless $self->{pzcv}{$v1};
    return 0 unless $self->{pzcv}{$v2};
    my @pi = split ' ', $self->{pzcv}{$v1}; my $p_num = @pi;
    my @pj = split ' ', $self->{pzcv}{$v2};
    my $sum = 0;
    my $v1_sum = 0; my $v2_sum = 0;
    for (my $i=0;$i<$p_num;$i++) {
# 	next if $pi[$i] == 0 and $pj[$i] == 0;
	$sum += ($pi[$i] * $pj[$i]);
	$v1_sum += $pi[$i] ** 2;
	$v2_sum += $pj[$i] ** 2;
    }
    return $sum/(sqrt($v1_sum)*sqrt($v2_sum));
}

sub multi_each_zv {
    my $self = shift;
    my ($v1, $v2) = @_;
    return () unless $self->{pzcv}{$v1};
    return () unless $self->{pzcv}{$v2};
    my @pi = split ' ', $self->{pzcv}{$v1}; my $p_num = @pi;
    my @pj = split ' ', $self->{pzcv}{$v2};
    my @out = ();
    my $v1_sum = 0; my $v2_sum = 0;
    for (my $i=0;$i<$p_num;$i++) {
# 	next if $pi[$i] == 0 and $pj[$i] == 0;
	push @out, ($pi[$i] * $pj[$i]);
# 	$v1_sum += $pi[$i] ** 2;
# 	$v2_sum += $pj[$i] ** 2;
    }
    return @out;
}


1;
