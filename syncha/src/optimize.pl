package Optimize;

use IPC::Open2;
use FindBin qw($Bin);
# use utf8;
# use open ':utf8';

sub new {
    my $type = shift;
    my $self = {};
    bless $self;

    return $self;
}

sub solve {
    my $self = shift;
    my $sent_ref = shift;
    my $pred_res = shift;
    my $noun_res = shift;

    my @obj = ();
    my %y = (); my %y2x = ();
    my %val = ();
    my %pc2val = ();
    my %pa2val = ();
    my $CONST = 0;
    for my $e (@{$pred_res}) {
	my $p = $e->{score}; my $pos = -log($p); my $neg = -log(1-$p);
	$CONST += $neg;
	push @obj, ($pos - $neg).' '.$e->{val};
	if ($e->{val} =~ m|x(\d+)/(\d+)_(\d+)/(\d+)_(\w+)|) {
	    $val{$e->{val}} = 1;
	    my $y = 'y'.$1.'/'.$2; my $a = $3.'/'.$4; my $c = $5;
	    push @{$y2x{ $y.'_'.$c }}, $e->{val};
	    push @{$pc2val{$y.'_'.$c}}, $e->{val};
	    push @{$pa2val{$y.'_'.$a}}, $e->{val};
	} elsif ($e->{val} =~ m|w(\d+)/(\d+)_(\d+)/(\d+)_(\w+)|) {
	    $val{$e->{val}} = 1;
	    my $y = 'y'.$1.'/'.$2; my $a = $3.'/'.$4; my $c = $5;
	    push @{$pc2val{$y.'_'.$c}}, $e->{val};
	    push @{$pa2val{$y.'_'.$a}}, $e->{val};
# 	    push @{$y2x{ $y }}, $e->{val};
	} elsif ($e->{val} =~ m|y(\d+)/(\d+)_(\w+)|) {
	    $y{ $e->{val} } = 1;
	    $val{ $e->{val} } = 1;
	} else {
	    die $!."\n".$e->{val}.' in pred_res'."\n";
	}
    }
    for my $e (@{$noun_res}) {
	my $p = $e->{score}; my $pos = -log($p); my $neg = -log(1-$p);
	$CONST += $neg;
	push @obj, ($pos - $neg).' '.$e->{val};
	if ($e->{val} =~ m|x(\d+)/(\d+)/(\d+)_(\d+)/(\d+)_(\w+)|) {
	    $val{$e->{val}} = 1;
	    my $y = 'y'.$1.'/'.$2.'/'.$3; my $a = $4.'/'.$5; my $c = $6;
#	    push @{$y2x{ $y.'_'.$c }}, $e->{val};
	    push @{$pc2val{$y.'_'.$c}}, $e->{val};
	    push @{$pa2val{$y.'_'.$a}}, $e->{val};
	} elsif ($e->{val} =~ m|x(\d+)/(\d+)/(\d+)_(\d+)/(\d+)/(\d+)_(\w+)|) {
	    $val{$e->{val}} = 1;
	    my $y = 'y'.$1.'/'.$2.'/'.$3; my $a = $4.'/'.$5.'/'.$6; my $c = $7;
#	    push @{$y2x{ $y.'_'.$c }}, $e->{val};
	    push @{$pc2val{$y.'_'.$c}}, $e->{val};
	    push @{$pa2val{$y.'_'.$a}}, $e->{val};
	} elsif ($e->{val} =~ m|y(\d+)/(\d+)/(\d+)_(\w+)|) {
	    $y{ $e->{val} } = 1;
	    $val{ $e->{val} } = 1;
	} else {
	    die $!."\n".$e->{val}.' in noun_res'."\n";
	}
    }
    my $obj = 'min: '.join(' + ', @obj).' + '.$CONST.';'."\n";
    for my $y (keys %y2x) {
	for my $x (@{$y2x{$y}}) {
            $obj .= $x.' <= '.$y.";\n";
	}
    }
    for my $y (keys %y2x) {
        $obj .= $y.' <= '.join(' + ', @{$y2x{$y}}).";\n";
    }
    for my $y (keys %y2x) {
        $obj .= $y.' >= '.join(' + ', @{$y2x{$y}}).";\n";
    }
    for my $pc (keys %pc2val) {
	$obj .= join(' + ', @{$pc2val{$pc}}).' <= 1;'."\n";
    }
    for my $pa (keys %pa2val) {
	$obj .= join(' + ', @{$pa2val{$pa}}).' <= 1;'."\n";
    }
#    $obj .= 'bin '.join(', ', sort keys %val).";\n";
#    print STDERR $obj;
#    open2 my $OUT, my $IN, $Bin.'/bin/lp_solve ' or die $!;
    open2 my $OUT, my $IN, 'lp_solve ' or die $!;
    $/ = undef;
    print $IN $obj;
    close $IN;
    my %sb2id = (); my $id = 1;
    $/ = "\n";
    while (<$OUT>) {
	chomp;
# 	print STDERR $_."\n";
	if (m|[wx](\d+)/(\d+)_(\d+)/(\d+)_(\w+)\s+1|) {
	    my ($ana_sid, $ana_bid, $ant_sid, $ant_bid, $c) = ($1, $2, $3, $4, $5);
#	    print STDERR "", join(' ', ($ana_sid, $ana_bid, $ant_sid, $ant_bid, $c))."\n";
	    my $ant_m = $sent_ref->[$ant_sid]->bunsetsu->[$ant_bid]->head_n_morph;
	    unless ($sb2id{$ant_sid.'/'.$ant_bid.'/'.$ant_m->mid}) {
		$sb2id{$ant_sid.'/'.$ant_bid.'/'.$ant_m->mid} = $id++;
		$ant_m->{attrs}->{id} = $sb2id{$ant_sid.'/'.$ant_bid.'/'.$ant_m->mid};
	    }
	    my $ana_m = $sent_ref->[$ana_sid]->bunsetsu->[$ana_bid]->head_n_morph;
	    $ana_m->{attrs}->{type} = 'pred';
	    $ana_m->{attrs}->{$c} = $sb2id{$ant_sid.'/'.$ant_bid.'/'.$ant_m->mid};
	} elsif (m|x(\d+)/(\d+)/(\d+)_(\d+)/(\d+)_(\w+)\s+1|) {
	    my ($ana_sid, $ana_bid, $ana_mid, $ant_sid, $ant_bid, $c) = ($1, $2, $3, $4, $5, $6);
#	    print STDERR "", join(' ', ($ana_sid, $ana_bid, $ana_mid, $ant_sid, $ant_bid, $c))."\n";
	    my $ant_m = $sent_ref->[$ant_sid]->bunsetsu->[$ant_bid]->head_n_morph;
	    unless ($sb2id{$ant_sid.'/'.$ant_bid.'/'.$ant_m->mid}) {
		$sb2id{$ant_sid.'/'.$ant_bid.'/'.$ant_m->mid} = $id++;
		$ant_m->{attrs}->{id} = $sb2id{$ant_sid.'/'.$ant_bid.'/'.$ant_m->mid};
	    }
	    my $ana_m = $sent_ref->[$ana_sid]->bunsetsu->[$ana_bid]->morph->[$ana_mid];
	    $ana_m->{attrs}->{type} = 'noun';
	    $ana_m->{attrs}->{$c} = $sb2id{$ant_sid.'/'.$ant_bid.'/'.$ant_m->mid};

	} elsif (m|x(\d+)/(\d+)/(\d+)_(\d+)/(\d+)/(\d+)_(\w+)\s+1|) {
	    my ($ana_sid, $ana_bid, $ana_mid, $ant_sid, $ant_bid, $ant_mid, $c) = ($1, $2, $3, $4, $5, $6, $7);
#	    print STDERR "", join(' ', ($ana_sid, $ana_bid, $ana_mid, $ant_sid, $ant_bid, $ant_mid, $c))."\n";
	    my $ant_m = $sent_ref->[$ant_sid]->bunsetsu->[$ant_bid]->morph->[$ant_mid];
	    unless ($sb2id{$ant_sid.'/'.$ant_bid.'/'.$ant_mid}) {
		$sb2id{$ant_sid.'/'.$ant_bid.'/'.$ant_mid} = $id++;
		$ant_m->{attrs}->{id} = $sb2id{$ant_sid.'/'.$ant_bid.'/'.$ant_mid};
	    }
	    my $ana_m = $sent_ref->[$ana_sid]->bunsetsu->[$ana_bid]->morph->[$ana_mid];
	    $ana_m->{attrs}->{type} = 'noun';
	    $ana_m->{attrs}->{$c} = $sb2id{$ant_sid.'/'.$ant_bid.'/'.$ant_mid};
	}
    }
    close $OUT;

    my $out = '';
    for (@{$sent_ref}) {
	$out .= $_->puts;
    }
    $out .= "EOT\n";

    return $out;
}

sub sort_sb {
    my ($a, $b) = @_;
    my ($a1, $a2) = split '/', $_;
    my ($b1, $b2) = split '/', $_;
    if ($a1 < $b1) {
	return -1;
    } elsif ($a1 > $b1) {
	return 1;
    } elsif ($a2 < $b2) {
	return -1;
    } elsif ($a2 > $b2) {
	return 1;
    }
    return 0;
}

1;
