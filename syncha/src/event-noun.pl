require 'calc_mi.pl';
require 'cab.pl';
require 'center.pl';
require 'common.pl';
require 'megam_binary.pl';

use strict;
use warnings;
# use utf8;
# use open ':utf8';


package EventNoun;

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

    # event-noun detection model
    $self->{detect_noun_model} = MegamBinary->new($path.'/dat/model/noun_detect/model_0.megam');

    # argument-detection model 
    # (skip now. consider later)

    # argument-identification model (in the same bunsetsul)
    for my $TYPE ('ga', 'o', 'ni') {
        $self->{'arg_in_b_model_'.$TYPE} = MegamBinary->new($path.'/dat/model/noun_soon_in_b_'.$TYPE.'/model_0.megam');
    }

    # argument-identification model (intra-sentential)
    for my $TYPE ('ga', 'o', 'ni') {
        $self->{'arg_intra_model_'.$TYPE} = MegamBinary->new($path.'/dat/model/noun_soon_intra_'.$TYPE.'/model_0.megam');
    }

    # argument-identification model (inter-sentential)
    for my $TYPE ('ga', 'o', 'ni') {
        $self->{'arg_inter_model_'.$TYPE} = MegamBinary->new($path.'/dat/model/noun_soon_inter_'.$TYPE.'/model_0.megam');
    }

    # anaphoricity-determination model (event-noun)
    for my $TYPE ('ga', 'o', 'ni') {
        $self->{'arg_ad_model_'.$TYPE} = MegamBinary->new($path.'/dat/model/noun_ana_scm_'.$TYPE.'/model_0.megam');
    }

    return $self;
}

sub analyze {
    my $self = shift;
    my $sent_ref = shift;

    return '' unless $sent_ref;

    $self->_mark_eventnoun($sent_ref);

    my @res = ();

    push @res, $self->_detect_args_noun($sent_ref);

    return \@res;
}

# ----------------------------------------
# mark event-nouns
sub _mark_eventnoun {
    my $self = shift;
    my $sent_ref = shift;
    my $eid = 1;
    for my $sent (@{$sent_ref}) {
	my @bunsetsu = @{$sent->bunsetsu};
	for my $bunsetsu (@bunsetsu) {
	    my @morph = @{$bunsetsu->morph}; my $m_num = @morph;
	    for (my $mid=0;$mid<$m_num;$mid++) {
		next unless $morph[$mid]->is_noun_sahen;
		my $score = $self->{detect_noun_model}->predict(&_ext_fe_mark_eventnoun($morph[$mid], $mid, $bunsetsu, \@bunsetsu));
		if ($score > 0.5) {
		    $morph[$mid]->eventnoun_id($eid++); 
		    $morph[$mid]->{attrs}->{type} = 'noun'; 
		}
#		print STDERR '', ($morph[$mid]->is_eventnoun)."\t".$morph[$mid]->bf."\t".$score."\n";
	    }
	}
    }
    return;
}

sub _ext_fe_mark_eventnoun {
    my ($nm, $nm_i, $nb, $b_ref) = @_;

    my @fe = ();
#    push @fe, 'noun_bf_'.$nm->bf.' 1';
    my @nm = @{$nb->morph}; my $nm_num = @nm;
    push @fe, 'noun_head 1' if $nm_i == $nb->head_n;

    for (my $i=0;$i<$nm_i;$i++) {
        push @fe, 'pre_bf_'.$nm[$i]->bf.' 1';
    }
    for (my $i=$nm_i+1;$i<=$nb->head_n;$i++) {
        push @fe, 'post_bf_'.$nm[$i]->bf.' 1';
    }
    push @fe, 'pre_adj_bf_'.$nm[$nm_i-1]->bf.' 1' if $nm_i != 0;
    push @fe, 'pre_adj_pos_'.$nm[$nm_i-1]->pos.' 1' if $nm_i != 0;
    push @fe, 'post_adj_bf_'.$nm[$nm_i+1]->bf.' 1' if $nm_i != $nm_num-1 and $nm_i != $nb->head_n;
    push @fe, 'post_adj_pos_'.$nm[$nm_i+1]->pos.' 1' if $nm_i != $nm_num-1 and $nm_i != $nb->head_n;

    if ($nm_i == $nb->head_n) {
        push @fe, 'case_'.$nb->_case.' 1';
        if ($nb->dep ne '-1') {
            my $d = $b_ref->[$nb->dep];
            push @fe, 'dep_head_pos_'.$d->head_pos.' 1';
            push @fe, 'dep_head_bf_'.$d->head_bf.' 1';
            my @dm = @{$d->morph}; my $dm_num = @dm;
            for (my $i=$d->head+1;$i<$dm_num;$i++) {
                push @fe, 'dep_func_pos_'.$dm[$i]->pos.' 1';
                push @fe, 'dep_func_bf_'.$dm[$i]->bf.' 1';
            }
        }
    }

    return join ' ', @fe;
}

# ----------------------------------------
# detect arguments of event-nouns
sub _detect_args_noun {
    my $self = shift;
    my $sent_ref = shift;
    my @sent = @{$sent_ref}; my $s_num = @sent;

    my @cand = ();
    my $cl = Center->new();
    my @elm = ();
    for (my $sid=0;$sid<$s_num;$sid++) {
	my $sent = $sent[$sid];
	my @bunsetsu = @{$sent->bunsetsu}; 
	for my $bunsetsu (@bunsetsu) {
	    my @morph = @{$bunsetsu->morph}; my $m_num = @morph;
	    for (my $mid=0;$mid<$m_num;$mid++) {
		next unless $morph[$mid]->is_eventnoun;
		my $en = $morph[$mid];
		my @c = &_ext_candidate_noun($sent, $bunsetsu, $mid, \@cand);
		my %type2elm = ();
		for my $c (@c) {
		    for my $TYPE ('ga', 'o', 'ni') {
			my $fe = &_ext_fe_args_noun($en, $bunsetsu, $c, \@bunsetsu, $sent_ref, $cl, $self->{ncv_model}, $TYPE);
			my $score;
			if ($bunsetsu->sid == $c->sid) {
			    if ($c->bid == $en->bid) {
				$score = $self->{'arg_in_b_model_'.$TYPE}->predict($fe);
			    } else {
				$score = $self->{'arg_intra_model_'.$TYPE}->predict($fe);
			    }
			} else { 
			    $score = $self->{'arg_inter_model_'.$TYPE}->predict($fe);
			}

			my $elm;
			if (ref($c) eq 'Bunsetsu') {
#			    print STDERR $score."\t".$en->sbm."\t".$TYPE."\t".$c->sid.'/'.$c->id."\n";
			    $elm->{val} = 'x'.$en->sbm.'_'.$c->sid.'/'.$c->id.'_'.$TYPE;
			} elsif (ref($c) eq 'Morpheme') {
#			    print STDERR $score."\t".$en->sbm."\t".$TYPE."\t".$c->sbm."\n";
			    $elm->{val} = 'x'.$en->sbm.'_'.$c->sbm.'_'.$TYPE;
			}
			$elm->{score} = $score;
			$elm->{cand} = $c;
			push @elm, $elm;

			push @{$type2elm{$TYPE}}, $elm;
		    }
		}
# 		for my $TYPE (keys %type2elm) {
# 		    my $ant = (sort { $b->{score} <=> $a->{score} } @{$type2elm{$TYPE}})[0]->{cand};
# 		    my $fe = &_ext_fe_ana_noun($en, $bunsetsu, $en->mid, $sent, \@c, $ant, \@bunsetsu, $sent_ref, $cl, $self->{ncv_model}, $TYPE);
# 		    my $score = $self->{'arg_ad_model_'.$TYPE}->predict($fe);
# 		    my $elm;
# 		    $elm->{val} = 'y'.$en->sbm.'_'.$TYPE;
# 		    $elm->{score} = $score;
# 		    push @elm, $elm;
# 		}
	    }
	    $cl->add($bunsetsu) if $bunsetsu->is_cand_all;
	}
	@cand = &_update_candidates($sid, \@bunsetsu, \@cand, $self->{opt}->{n});
#	print STDERR 'cand_num: '.scalar(@cand)."\n";
    }
    return @elm;
}

sub _ext_candidate_noun {
    my ($s, $nb, $mid, $cand_ref) = @_;
    my @cand = @{$cand_ref};
    my @b = @{$s->bunsetsu}; my $b_num = @b;
    for (my $i=0;$i<$b_num;$i++) {
        if ($i== $nb->id) {
            my @nm = @{$nb->morph}; my $nm_num = @nm;
            for (my $j=0;$j<$nm_num;$j++) {
                next if $j == $mid;
                push @cand, $nm[$j] if $nm[$j]->is_cand;
            }
        } else {
            push @cand, $b[$i] if $b[$i]->is_cand_all;
        }
    }
    return @cand;
}

sub _ext_fe_args_noun {
    my ($nm, $nb, $cand, $b_ref, $sent_ref, $cl, $mi_model, $c) = @_;
    my @fe = ();

    if (ref($cand) eq 'Bunsetsu') {

        ## begin: path feature
        if ($cand->sid == $nb->sid) {
            &main::mark_path($nb, $cand, $sent_ref->[$nb->sid]);
            my %func_pos = (); my %func_bf = ();
            my @b = @{$sent_ref->[$nb->sid]->bunsetsu}; my $b_num = @b;
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
            while (1) {
                my @m = @{$cur_c->morph}; my $m_num = @m;
                for (my $j=$cur_c->head_n+1;$j<$m_num;$j++) {
                    $func_bf{$m[$j]->bf}++; $func_pos{$m[$j]->pos}++;
                }
                last if $cur_c->dep eq '-1';
                last if $cur_c->dep == $cb[$cur_c->dep]->dep;
                $cur_c = $cb[$cur_c->dep];
            }
            my $cur_p = $nb; my @cp = @{$sent_ref->[$nb->sid]->bunsetsu};
            while (1) {
                my @m = @{$cur_p->morph}; my $m_num = @m;
                for (my $j=$cur_p->head_n+1;$j<$m_num;$j++) {
                    $func_bf{$m[$j]->bf}++; $func_pos{$m[$j]->pos}++;
                }
                last if $cur_p->dep eq '-1';
                last if $cur_p->dep == $cp[$cur_p->dep]->dep;
                $cur_p = $cp[$cur_p->dep];
            }
            push @fe, map {'in_path_func_pos_'.$_.' '.$func_pos{$_}} sort keys %func_pos;
            push @fe, map {'in_path_func_bf_'.$_.' '.$func_bf{$_}}  sort keys %func_bf;
        }
        ## end: path feature

        push @fe, 'first_sent 1' if $cand->sid == 0;
        push @fe, 'first_mentioned 1' if $cand->FIRST_MENTIONED;
        push @fe, 'cand_pos_'.$cand->head_n_pos.' 1';
        push @fe, 'cand_case_'.$cand->_case.' 1';
        my $ne = $cand->head_n_ne; $ne =~ s/^(B|I|E)-//;
        push @fe, 'cand_ne_'.$ne.' 1' if $ne ne 'O';

        if ($nb->sid - $cand->sid) {
            push @fe, 'sentdist '.($nb->sid - $cand->sid);
        } elsif ($nb->sid == $cand->sid) {
            if ($cand->id < $nb->id) {
                push @fe, 'cand_precedes_pred 1';
            } else {
                push @fe, 'pred_precedes_cand 1';
            }

            if ($cand->dep == $nb->id) {
                push @fe, 'cand_depned_noun 1';
            } elsif ($nb->dep == $cand->id) {
                push @fe, 'noun_depned_cand 1';
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

    } elsif (ref($cand) eq 'Morpheme') {
        push @fe, 'in_b_adj_pre 1'  if ($nm->mid -1 == $cand->mid );
        push @fe, 'in_b_pre 1'  if ($nm->mid > $cand->mid );
        push @fe, 'in_b_adj_post 1' if ($nm->mid == $cand->mid -1 );
        push @fe, 'in_b_post 1' if ($nm->mid < $cand->mid );
        push @fe, 'cand_pos_'.$cand->pos.' 1';
        my $ne = $cand->ne; $ne =~ s/^(B|I|E)-//;
        push @fe, 'cand_ne_'.$ne.' 1' if $ne ne 'O';

    } else { # ref($cand) ne 'Morpheme' and ref($cand) ne 'Bunsetsu'
        die $!;
    }

    push @fe, 'head_lemma_'.$cand->bf_ext.' 1';

    my $case = ($c eq 'ga')? 'が' : ($c eq 'ni')? 'に' : ($c eq 'o')? 'を' : die $!;
    my $mi = $mi_model->calc_mi($cand->bf_ext, $case.':'.$nm->bf.'する');
    push @fe, 'mi '.$mi if ($mi);
    return join ' ', @fe;

}

sub _ext_fe_ana_noun {
    my ($nm, $nb, $nm_i, $s, $cand_ref, $ant, $b_ref, $sent_ref, $cl, $mi_model, $case) = @_;
    my @fe = ();
    my $fe = &_ext_fe_mark_eventnoun($nm, $nm_i, $nb, $b_ref);
    my @tmp = split ' ', $fe;
    while (@tmp) {
	my $name = shift @tmp; my $val = shift @tmp;
	push @fe, 'detect_'.$name.' '.$val;
    }
    if ($ant) {
        push @fe, &_ext_fe_args_noun($nm, $nb, $ant, $b_ref, $sent_ref, $cl, $mi_model, $case);
    }
    return join ' ', @fe;
    
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

1;
