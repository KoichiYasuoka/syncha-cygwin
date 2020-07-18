use strict;
use warnings;
use IPC::Open2;
# use utf8;

use FindBin qw($Bin);
unshift @INC, $Bin.'/src';
require 'cab.pl';

use open ':utf8';

sub open_raw_input {
    my ($in, $IN, $OUT) = @_;
    my @sent = (); my $sid = 0;
    for my $in (split /\n/, $in) {
	if ($in) {
	    print $IN $in."\n";
	    local $/ = "EOS\n";
	    my $out = <$OUT>;
	    chomp;
	    push @sent, Sentence->new($out, $sid++);
	}
# 	$sid++;
	local $/ = "\n";
    }
    return @sent;
}

sub open_cabocha_input {
    my $in = shift;
    return () unless $in;
    die "use cabocha format as input.\n" if $in !~ /EOS/sm;
    my @sent = (); my $sid = 0;
    for (split /EOS\n/, $in) {
	push @sent, Sentence->new($_, $sid++) if $_;
    }
    return @sent;
}

sub mark_path {
    my ($pred, $ant, $s) = @_;
    my @b = @{$s->bunsetsu}; my $b_num = @b;

    # init
    for (my $bid=0;$bid<$b_num;$bid++) { $b[$bid]->in_path(0); }

    my $cur = $pred; my @p = ($cur);
    while ($cur->has_dep) {
        $cur = $b[$cur->dep]; push @p, $cur;
	last if $cur->dep and $b[$cur->dep] and 
	        $cur->dep == $b[$cur->dep]->dep;
    }
    $cur = $ant; my @a = ($cur);
    while ($cur->has_dep) {
        $cur = $b[$cur->dep]; push @a, $cur;
	last if $cur->dep and $b[$cur->dep] and 
	        $cur->dep == $b[$cur->dep]->dep;
    }

    my $p_num = @p; my $a_num = @a;
    for (my $i=0;$i<$p_num;$i++) {
        for (my $j=0;$j<$a_num;$j++) {
            next if ($p[$i]->id ne $a[$j]->id);
            for (my $k=0;$k<=$i;$k++) {
                $p[$k]->in_path(1);
            }
            for (my $k=0;$k<=$j;$k++) {
                $a[$k]->in_path(1);
            }
            return;
        }
    }
    return;
    die $!;
}

sub open_tsv {
    my $file = shift;

    my %key2val = ();

    open 'FL', $file or die $!;
    binmode 'FL', ':utf8';
    while (<FL>) {
	chomp;
	my ($key, $val) = split '\t', $_, 2;
	$key2val{$key} = $val;
    }
    close FL;

    return \%key2val;
}


1;

