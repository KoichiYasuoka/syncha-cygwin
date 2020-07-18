#!/usr/bin/env perl

use strict;
use warnings;
# use utf8;
use open ':utf8';

package MegamBinary;

sub new {
    my $type = shift; 
    my $self = {};
    bless $self;
    my $model = shift;
    $self->model($model);
    return $self;
}

sub model {
    my $self = shift;
    my $model = shift;
#    print STDERR $model."\n";
    die "please set model file when using MegamBinary\n".$model."\n" unless $model;
    my %fe2wei = ();
    open 'MDL', $model or die $!;
    while (<MDL>) {
	chomp;
	my ($fe, $wei) = split ' ', $_;
	$fe2wei{$fe} = $wei;
    }
    close MDL;
    $self->{fe2wei} = \%fe2wei;
    return;
}

sub fe2wei {
    my $self = shift;
    my $fe = shift;
    my $wei = $self->{fe2wei}{$fe};
    $wei = 0 unless $wei;
    return $wei;
}

sub predict {
    my $self = shift;
    my $fe = shift;
    my $res = $self->fe2wei('**BIAS**');
    if ($fe) {
	my @fe = split ' ', $fe;
	while (@fe) {
	    my $fname = shift @fe; my $fval = shift @fe;
	    my $wei = $self->fe2wei($fname);
	    if ($fval eq '0') {
		$res += $wei * 0;
	    } else {
		$res += $wei * $fval;
	    }
	}
    }
    return 1/(1+exp(-$res));
}

package main;

if ($0 eq __FILE__) {

    use Getopt::Std;
    my $usage = <<USG;
megam_binary.pl -m wei_file -i test_file 
USG

    my %options;
    getopts("m:i:h", \%options);
    die $usage if $options{h};
    die $usage unless $options{m};
    die $usage unless $options{i};

    my $model = MegamBinary->new($options{m});
    
    open 'TST', $options{i} or die $!;
    while (<TST>) {
	chomp;
	my ($label, $fe) = split ' ', $_, 2;
	my $res = $model->predict($fe);
 	print $label.' '.$res."\n";
    }
    close TST;

}


1;
