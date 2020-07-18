#!/usr/local/bin/perl 

use strict;
use warnings;
# use utf8;
# use open ':utf8';

package Center;

sub new {
    my $type = shift;
    my $self = {};
    bless $self;
    
    return $self;
}

sub HA {
    my $self = shift;
    if (@_) {
	push @{$self->{HA}}, $_[0];
    } else {
	return $self->{HA};
    }
}

sub GA {
    my $self = shift;
    if (@_) {
	push @{$self->{GA}}, $_[0];
    } else {
	return $self->{GA};
    }
}

sub NI {
    my $self = shift;
    if (@_) {
	push @{$self->{NI}}, $_[0];
    } else {
	return $self->{NI};
    }
}

sub WO {
    my $self = shift;
    if (@_) {
	push @{$self->{WO}}, $_[0];
    } else {
	return $self->{WO};
    }
}

sub OTHER {
    my $self = shift;
    if (@_) {
	push @{$self->{OTHER}}, $_[0];
    } else {
	return $self->{OTHER};
    }
}

sub add {
    my $self = shift;
    my $b = shift;
    return unless ($b->is_noun_ext);
    if ($b->_case eq 'は') {
	$self->HA($b); $self->order($b, 1);
    } elsif ($b->_case eq 'が') {
	$self->GA($b); $self->order($b, 2);
    } elsif ($b->_case eq 'に') {
	$self->NI($b); $self->order($b, 3);
    } elsif ($b->_case eq 'を') {
	$self->WO($b); $self->order($b, 4);
#     } elsif ($b->CASE eq '') { # その他はとりあえず使わない
    }
    return;
}

# sub add_rank {
    
# }

sub order { # 入力文節の順位を返す
    my $self = shift; my $b = shift; 
    if (@_) {
	my $order = shift;
	return '' unless ($b->is_noun_ext);
	unshift @{$self->{order}->[$order]}, $b;
    } else {
	return '' unless (ref($self->{order}) eq 'ARRAY');
	for (my $i=1;$i<=$self->order_last;$i++) {
	    next unless ($self->{order}->[$i]);
	    my $B = $self->{order}->[$i]->[0];
	    die $! if (ref($B) ne 'Bunsetsu');
	    return $i if ($B->sid eq $b->sid and $B->id eq $b->id);
	}
	return '';
    }
}

sub rank {
    my $self = shift; my $b = shift;
    return '' unless (ref($self->{order}) eq 'ARRAY');
    my $rank = 1;
    for (my $i=0;$i<=$self->order_last;$i++) {
	next unless ($self->{order}->[$i]); # Listが空
	my $B = $self->{order}->[$i]->[0];
	return $rank if ($B->sid eq $b->sid and $B->id eq $b->id);
	$rank++; # Listに要素がある場合のみインクリメント
    }
    return '';
}

sub order_last {
    my $self = shift;
    return 4;
}

sub cp {
    my $self = shift;
    my $cp = Center->new;
    for my $type ('HA', 'GA', 'WO', 'NI', 'OTHER') {
	next unless $self->{$type};
	for (@{$self->{$type}}) {
	    push @{$cp->{$type}}, $_;
	}
    }
    if ($self->{order}) {
	for (my $i=0;$i<=$self->order_last;$i++) {
	    next unless $self->{order}->[$i];
	    for (@{$self->{order}->[$i]}) { 
		push @{$cp->{order}->[$i]}, $_;
	    }
	}
    }
    return $cp;
}

1;
