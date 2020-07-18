use strict;
use warnings;

require 'calc_mi.pl';
# require 'cab.pl';
# require 'center.pl';
# require 'common.pl';
require 'megam_binary.pl';

package Predicate;

use utf8;
use open ':utf8';

sub new {
    my $type = shift;
    my $self = {};
    bless $self;
    my $path = shift;
    my $opt_ref = shift;

    $self->{opt} = $opt_ref;

    # MI model
    $self->{ncv_model} = CalcMI->new($opt_ref, $path.'/dat/cooc', 'Pn_arg.tsv', 'Pcv_arg.tsv', 'Pz_arg.tsv');
    $self->{cv_model}  = CalcMI->new($opt_ref, $path.'/dat/cooc', 'Pc_predicate.tsv', 'Pv_predicate.tsv', 'Pz_predicate.tsv');

    # predicate-detection model
    $self->{detect_pred_model} = MegamBinary->new($path.'/dat/model/pred_detect/model_0.megam');

    # argument-detection model 
    # (skip now. consider later)

    # argument-identification model (dependants)
    for my $TYPE ('ga', 'o', 'ni') {
        $self->{'arg_depend_model_'.$TYPE} = MegamBinary->new($path.'/dat/model/dep_soon_'.$TYPE.'/model_0.megam');
    }

    # argument-identification model (adnominal clause)
    for my $TYPE ('ga', 'o', 'ni') {
        $self->{'arg_adnom_model_'.$TYPE} = MegamBinary->new($path.'/dat/model/adnom_soon_'.$TYPE.'/model_0.megam');
    }

    # argument-identification model (intra-sentential zero-anaphora)
    for my $TYPE ('ga', 'o', 'ni') {
        $self->{'arg_intra_model_'.$TYPE} = MegamBinary->new($path.'/dat/model/zero_soon_intra_'.$TYPE.'/model_0.megam');
    }

    # argument-identification model (inter-sentential zero-anaphora)
    for my $TYPE ('ga', 'o', 'ni') {
        $self->{'arg_inter_model_'.$TYPE} = MegamBinary->new($path.'/dat/model/zero_soon_inter_'.$TYPE.'/model_0.megam');
    }

    # anaphoricity-determination model (zero-anaphora)
    for my $TYPE ('ga', 'o', 'ni') {
        $self->{'arg_ad_model_'.$TYPE} = MegamBinary->new($path.'/dat/model/zero_ana_scm_'.$TYPE.'/model_0.megam');
    }
    
    return $self;

}

sub analyze {
    my $self = shift;
    my $sent_ref = shift;

    return '' unless $sent_ref;

    $self->_mark_predicates($sent_ref);

    my @res = ();

    push @res, $self->_detect_args_dependants($sent_ref);

    push @res, $self->_detect_args_adnom($sent_ref);

    push @res, $self->_detect_args_zero($sent_ref);

    return \@res;
}

# ----------------------------------------
# mark predicates
sub _mark_predicates {
    my $self = shift;
    my $sent_ref = shift;
    my $pid = 1;
    for my $sent (@{$sent_ref}) {
	my @bunsetsu = @{$sent->bunsetsu};
	for my $bunsetsu (@bunsetsu) {
	    my $score = $self->{detect_pred_model}->predict(&_ext_fe_mark_predicates($bunsetsu, \@bunsetsu));
	    my $fe = &_ext_fe_mark_predicates($bunsetsu, \@bunsetsu);
	    if ($score > 0.5) {
		$bunsetsu->pred_id($pid++);
		$bunsetsu->head_morph->{attrs}->{type} = 'pred';
	    }
	}
    }
    return;
}

sub _ext_fe_mark_predicates {
    my ($bunsetsu, $b_ref) = @_;
    my %fe = ();

    $fe{'auto_pred'} = 1 if ($bunsetsu->_pred);
    $fe{'head_pos_'.$bunsetsu->head_morph->pos} = 1;
#    $fe{'head_bf_'.$bunsetsu->head_morph->bf} = 1;
    $fe{'head_cf_'.$bunsetsu->head_morph->cf} = 1 if $bunsetsu->head_morph->cf;
    
    my @m = @{$bunsetsu->morph}; my $m_num = @m;
    for (my $i=$bunsetsu->head+1;$i<$m_num;$i++) {
	$fe{'func_bf_'.$m[$i]->bf} = 1;
    }
    my @b = @{$b_ref}; my $b_num = @b;
    $fe{'sent_begin'} = 1 if ($bunsetsu->id == 0);
    $fe{'sent_end'} = 1 if ($b_num -1 == $bunsetsu->id);
    
    my %d_case = ();
    for my $d (map $b[$_], @{$bunsetsu->dtr}) {
	$d_case{$d->_case} = 1;
    }
    for my $c (sort keys %d_case) {
	$fe{'dtr_case_'.$c} = 1;
    }
    
    return join ' ', map $_.' '.$fe{$_}, sort keys %fe;
}

# ----------------------------------------
# detect arguments in dependents

sub _detect_args_dependants {
    my $self = shift;
    my $sent_ref = shift;

    my @elm = ();
    my $cl = Center->new();
    for my $sent (@{$sent_ref}) {
	my @bunsetsu = @{$sent->bunsetsu};
	for my $pred (@bunsetsu) {
	    if ($pred->is_pred) {
		my @cand = &_ext_candidate_dependants($pred->id, \@bunsetsu);
		for my $cand (@cand) {
		    for my $TYPE ('ga', 'o', 'ni') {
			my $score = $self->{'arg_depend_model_'.$TYPE}->predict(&_ext_fe_arg_dependants($pred, $cand, \@bunsetsu, $sent_ref, $cl, $self->{'ncv_model'}, $TYPE));
			my $elm;
			$elm->{val} = 'w'.$pred->sid.'/'.$pred->id.'_'.$cand->sid.'/'.$cand->id.'_'.$TYPE;
			$elm->{score} = $score;
			push @elm, $elm;
			# debug..
#			print STDERR $score."\t".$cand->str."\t".$TYPE."\t".$pred->_pred."\n";
		    }
		}
	    }
	    $cl->add($pred) if $pred->is_cand_all;
	}
    }
    return @elm;
}

sub _ext_candidate_dependants {
    my ($bid, $b_ref) = @_;
    return map $b_ref->[$_], @{$b_ref->[$bid]->dtr};
}

sub _ext_fe_arg_dependants {
#     my ($pred, $cand, $b_ref, $t, $cl, $mi_model, $c) = @_;
    return &_ext_fe_soon(@_);
}


# ----------------------------------------
# detect arguments in adnominal clause

sub _detect_args_adnom {
    my $self = shift;
    my $sent_ref = shift;
    my $cl = Center->new(); # not updated in this subroutine
    my @elm = ();
    for my $sent (@{$sent_ref}) {
	my @bunsetsu = @{$sent->bunsetsu};
	for my $pred (@bunsetsu) {
	    next unless ($pred->is_pred);
	    my $cand = &_ext_candidate_adnom($pred->id, $sent);
	    next unless $cand;
	    for my $TYPE ('ga', 'o', 'ni') {
		my $score = $self->{'arg_adnom_model_'.$TYPE}->predict(&_ext_fe_arg_adnom($pred, $cand, \@bunsetsu, $sent_ref, $cl, $self->{'ncv_model'}, $TYPE));
		# print STDERR $score."\n";
		my $elm;
		$elm->{val} = 'w'.$pred->sid.'/'.$pred->id.'_'.$cand->sid.'/'.$cand->id.'_'.$TYPE;
		$elm->{score} = $score;
		push @elm, $elm;
	    }
	}
    }
    return @elm;
}

sub _ext_candidate_adnom {
    my ($bid, $sent) = @_;
    my @bunsetsu = @{$sent->bunsetsu};
    my $pred = $bunsetsu[$bid];
    return '' if ($pred->dep ne '-1');
    return $bunsetsu[$pred->dep];
}

sub _ext_fe_arg_adnom {
#     my ($pred, $cand, $b_ref, $t, $cl, $mi_model, $c) = @_;
    return &_ext_fe_soon(@_);
}

# ----------------------------------------
# detect arguments of zero-anaphora

sub _detect_args_zero {
    my $self = shift;
    my $sent_ref = shift; 
    my @sent = @{$sent_ref}; my $s_num = @sent;
    my @cand = ();
    my $cl = Center->new();
    my @elm = ();
    for (my $sid=0;$sid<$s_num;$sid++) {
	my $sent = $sent[$sid];
	my @bunsetsu = @{$sent->bunsetsu};
	for my $pred (@bunsetsu) {
	    if ($pred->is_pred) {
		my @c = &_ext_candidate_zero($sent, $pred, \@cand);
		my %type2elm = ();
		for my $c (@c) {
		    for my $TYPE ('ga', 'o', 'ni') {
#			print STDERR "check3-1\n";
			my $fe = &_ext_fe_args_zero($pred, $c, \@bunsetsu, $sent_ref, $cl, $self->{'ncv_model'}, $TYPE);
			my $score;
			if ($pred->sid == $c->sid) {
			    $score = $self->{'arg_intra_model_'.$TYPE}->predict($fe);
			} else {
			    $score = $self->{'arg_inter_model_'.$TYPE}->predict($fe);
			}
			my $elm;
			$elm->{val} = 'x'.$pred->sid.'/'.$pred->id.'_'.$c->sid.'/'.$c->id.'_'.$TYPE;
			$elm->{score} = $score;
			$elm->{cand} = $c;
			push @elm, $elm;

			push @{$type2elm{$TYPE}}, $elm;
		    }
		}
		for my $TYPE (keys %type2elm) {
		    my $ant = (sort { $b->{score} <=> $a->{score} } @{$type2elm{$TYPE}})[0]->{cand};
		    my $fe = &_ext_fe_ana_zero($pred, $ant, \@bunsetsu, $sent_ref, $cl, $self->{'ncv_model'}, $TYPE);
		    my $score = $self->{'arg_ad_model_'.$TYPE}->predict($fe);
		    my $elm;
		    $elm->{val} = 'y'.$pred->sid.'/'.$pred->id.'_'.$TYPE;
		    $elm->{score} = $score;
		    push @elm, $elm;
		}
	    }
	    $cl->add($pred) if $pred->is_cand_all;
	}
#	print STDERR 'opt_n: '.$self->{opt}->{n}."\n";
	@cand = &_update_candidates($sid, \@bunsetsu, \@cand, $self->{opt}->{n});
#	print STDERR 'cand_num: '.scalar(@cand)."\n";
    }
    return @elm;
}

sub _ext_candidate_zero {
    my ($sent, $pred, $cand_ref) = @_;

    my %dep = ();
    $dep{$pred->dep} = 1 if $pred->dep ne '-1';
    for (@{$pred->dtr}) { $dep{$_} = 1; }

    my @cand = @{$cand_ref};
    my @b = @{$sent->bunsetsu}; my $b_num = @b;
    for (my $i=0;$i<$b_num;$i++) {
        next if $b[$i]->id == $pred->id;
        push @cand, $b[$i] if $b[$i]->is_cand_all and !$dep{$b[$i]->id};
    }
    return @cand;
}

sub _update_candidates {
    my ($sid, $b_ref, $cand_ref, $opt_n) = @_;
    my @cand = ();
    for my $cand (@{$cand_ref}) {
	push @cand, $cand if ($sid - $cand->sid) <= $opt_n;
    }
    for my $b (@{$b_ref}) {
	push @cand, $b if $b->is_cand_all;
    }
    return @cand;
}


sub _ext_fe_args_zero {
    return &_ext_fe_soon(@_);
}

sub _ext_fe_ana_zero {
    my ($pred, $cand, $b_ref, $t, $cl, $mi_model, $c) = @_;

    my @fe = ();
    if ($cand) {
	push @fe, &_ext_fe_soon($pred, $cand, $b_ref, $t, $cl, $mi_model, $c);
    }

    my $subj_pre = 0;
    my $topic_pre = 0;
    for my $b (@{$b_ref}) {
	last if $pred->id == $b->id;
        $subj_pre = 1 if $b->_case eq 'が';
        $topic_pre = 1 if $b->_case eq 'は';
    }
    push @fe, 'subj_pre_m 1' if $subj_pre;
    push @fe, 'topic_pre_m 1' if $topic_pre;

    push @fe, 'first_sent 1'       if $pred->sid == 0;
    push @fe, 'first_morph_in_s 1' if $pred->id == 1;

    push @fe, 'pred_lemma_'.$pred->_pred.' 1' if $pred->_pred;
    push @fe, 'pred_pos_'.$pred->head_pos.' 1';
    push @fe, 'pred_case_'.$pred->_case.' 1';

    if ($pred->dep ne '-1') {
        my $db = $b_ref->[$pred->dep];
        push @fe, 'dep_lemma_'.$pred->head_pos.' 1';
        push @fe, 'dep_pos_'.$pred->head_pos.' 1';
        push @fe, 'dep_case_'.$pred->_case.' 1';
    }

    for my $db (@{$pred->dtr}) {
        push @fe, 'dtr_lemma_'.$pred->head_pos.' 1';
        push @fe, 'dtr_pos_'.$pred->head_pos.' 1';
        push @fe, 'dtr_case_'.$pred->_case.' 1';
    }

    my %func_pos = (); my %func_bf = ();
    my $cur_p = $pred; my @cp = @{$b_ref};
    while (1) {
        my @m = @{$cur_p->morph}; my $m_num = @m;
        for (my $j=$cur_p->head_n+1;$j<$m_num;$j++) {
            $func_bf{$m[$j]->bf}++; $func_pos{$m[$j]->pos}++;
        }
        last if $cur_p->dep eq '-1';
        last if $cur_p->dep == $cp[$cur_p->dep]->dep;
        $cur_p = $cp[$cur_p->dep];
    }
    push @fe, map {'zero_ana_in_path_func_pos_'.$_.' '.$func_pos{$_}} sort keys %func_pos;
    push @fe, map {'zero_ana_in_path_func_bf_'.$_.' '.$func_bf{$_}}  sort keys %func_bf;

    return join ' ', @fe;
}



# ----------------------------------------
# common
sub _ext_fe_soon {
    my ($pred, $cand, $b_ref, $sent_ref, $cl, $mi_model, $c) = @_;
    my @fe = ();
#     my $cand_str = $cand->head_n_bf;
#     my $pred_str = $pred->head_n_bf;
#     push @fe, 'lemma_pair_'.$cand_str.'_'.$pred_str.' 1';
    push @fe, 'head_lemma_'.$cand->bf_ext.' 1';

    push @fe, 'first_sent 1' if $cand->sid == 0;
    push @fe, 'first_mentioned 1' if $cand->FIRST_MENTIONED;
    push @fe, 'cand_pos_'.$cand->head_n_pos.' 1';
    push @fe, 'cand_case_'.$cand->_case.' 1';
    my $ne = $cand->head_n_ne; $ne =~ s/^(B|I|E)-//;
    push @fe, 'cand_ne_'.$ne.' 1' if $ne ne 'O';
    if ($pred->sid - $cand->sid) {
	push @fe, 'sentdist '.($pred->sid - $cand->sid);
    } elsif ($pred->sid == $cand->sid) {
	if ($cand->id < $pred->id) {
	    push @fe, 'cand_precedes_pred 1';
	} else {
	    push @fe, 'pred_precedes_cand 1';
	}
    }

    my $poss_flg = 0;
    my $det_flg = 0;
    my $demon_flg = 0;
    if ($cand->id != 0 and $b_ref->[$cand->id -1]) {
	my $pre_b = $b_ref->[$cand->id -1];
	$det_flg = 1   if $pre_b->str =~ /^(その|それらの)$/;
	$demon_flg = 1 if $pre_b->str =~ /^(この|あの|これらの|あれらの)$/;
	$poss_flg = 1  if $pre_b->str =~ /^(私の|彼の|彼らの|彼女の|彼女らの|私たちの|私達の)$/;
    }
    push @fe, 'cand_demon 1' if $demon_flg == 1;
    push @fe, 'cand_det 1'   if $det_flg   == 1;
    push @fe, 'cand_poss 1'  if $poss_flg  == 1;

    push @fe, 'cl_rank '. $cl->rank($cand)  if $cl->rank($cand);
    push @fe, 'cl_order '.$cl->order($cand) if $cl->order($cand);

    my $case = ($c eq 'ga')? 'が' : ($c eq 'ni')? 'に' : ($c eq 'o')? 'を' : die $!;
    my $mi = $mi_model->calc_mi($cand->bf_ext, $case.' '.$pred->_pred);
    push @fe, 'mi '.$mi if ($mi);

    # path features
    if ($cand->sid == $pred->sid) {
        &main::mark_path($pred, $cand, $sent_ref->[$pred->sid]);
        my %func_pos = (); my %func_bf = ();
        my @b = @{$sent_ref->[$pred->sid]->bunsetsu}; my $b_num = @b;
        for (my $i=0;$i<$b_num;$i++) {
            next unless ($b[$i]->in_path);
            my @m = @{$b[$i]->morph}; my $m_num = @m;
            for (my $j=$b[$i]->head_n+1;$j<$m_num;$j++) {
                $func_bf{$m[$j]->bf}++; $func_pos{$m[$j]->pos}++;
            }
        }
        push @fe, map {'in_path_func_pos_'.$_.' '.$func_pos{$_}} sort keys %func_pos;
        push @fe, map {'in_path_func_bf_'.$_.' '.$func_bf{$_}}  sort keys %func_bf;
    } else {
        my %func_pos = (); my %func_bf = ();
        my $cur_c = $cand; my @cb = @{$sent_ref->[$cand->sid]->bunsetsu};
#	print STDERR 'b cand: '."\n";
        while (1) {
            my @m = @{$cur_c->morph}; my $m_num = @m;
            for (my $j=$cur_c->head_n+1;$j<$m_num;$j++) {
                $func_bf{$m[$j]->bf}++; $func_pos{$m[$j]->pos}++;
            }
            last if $cur_c->dep eq '-1';
#	    print STDERR $cur_c->dep."\n";
	    last if $cur_c->dep == $cb[$cur_c->dep]->dep;
            $cur_c = $cb[$cur_c->dep];
        }
#	print STDERR 'e cand: '."\n";
        my $cur_p = $pred; my @cp = @{$sent_ref->[$pred->sid]->bunsetsu};
#	print STDERR 'b pred: '."\n";
        while (1) {
            my @m = @{$cur_p->morph}; my $m_num = @m;
            for (my $j=$cur_p->head_n+1;$j<$m_num;$j++) {
                $func_bf{$m[$j]->bf}++; $func_pos{$m[$j]->pos}++;
            }
            last if $cur_p->dep eq '-1';
	    last if $cur_p->dep == $cp[$cur_p->dep]->dep;
            $cur_p = $cp[$cur_p->dep];
        }
#	print STDERR 'e pred: '."\n";
        push @fe, map {'in_path_func_pos_'.$_.' '.$func_pos{$_}} sort keys %func_pos;
        push @fe, map {'in_path_func_bf_'.$_.' '.$func_bf{$_}}  sort keys %func_bf;
    }

#     my $f_num = @fe;
#     for (my $i=0;$i<$f_num;$i++) {
#         $fe[$i] = $prefix.$fe[$i];
#     }
    return join ' ', @fe;
}

1;


