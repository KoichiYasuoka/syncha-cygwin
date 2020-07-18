use strict;
use warnings;

require 'megam_binary.pl';
require 'center.pl';

package Coreference;

use utf8;
use open ':utf8';

sub new {
    my $type = shift;
    my $self = {};
    bless $self;
    my $path = shift;
    my $opt_ref = shift;

    $self->{opt} = $opt_ref;

    # corefrence resolution model
    $self->{coref_model}    = MegamBinary->new($path.'/dat/model/coref_ant/model_0.megam');
    $self->{ana_model}      = MegamBinary->new($path.'/dat/model/coref_ana/model_0.megam');
    $self->{np_cache_model} = MegamBinary->new($path.'/dat/model/coref_cache/model_0.megam');

    $self->{np_pzn} = &main::open_tsv($path.'/dat/cooc/Pzn_coref.tsv');

    return $self;
}

sub analyze {
    my $self = shift;
    my $sent_ref = shift;

    return '' unless $sent_ref;

    my @sent = @{$sent_ref}; my $sent_num = @sent;
    my $cl = Center->new;
    my @cache = ();
    my @conj = ();

    my $EQ_MAX = 1;

    for (my $sid=0;$sid<$sent_num;$sid++) {

	my @cand = @cache;

	my @bs = @{$sent[$sid]->bunsetsu};
	for my $bs (@bs) {

	    # collect conjunctions 
	    push @{$conj[$sid]}, $bs->head_bf if ($bs->head_pos =~ /接続詞/); ###

	    next unless $bs->is_cand; # ignore non-candidate antecedent
	    
	    # resolution process
	    if (@cand) {
		my $ana_res = $self->{ana_model}->predict(&_ext_fe_np_anaphoricity($bs, $sent[$sid], \@cand, $self->{np_pzn}));
		my @ant = ();
		for my $cand (@cand) {
		    my $ant_res = $self->{coref_model}->predict(&_ext_fe_np_coreference($bs, $cand, $sent[$cand->sid]->bunsetsu, $self->{np_pzn}));
		    my $ant; $ant->{bs} = $cand; $ant->{score} = ($ana_res + $ant_res) / 2;
		    push @ant, $ant;
		}
		my $ant = (sort {$b->{score} <=> $a->{score}} @ant)[0];
		if ($ant->{score} > 0.5) {
		    my $eq_id = ($ant->{bs}->head_n_eq)? $ant->{bs}->head_n_eq : $EQ_MAX++;
		    $ant->{bs}->head_n_eq($eq_id);
		    $bs->head_n_eq($eq_id);

		    # for outputs
		    $ant->{bs}->head_n_morph->{attrs}->{eq} = $eq_id;
		    $bs->head_n_morph->{attrs}->{eq} = $eq_id;
		}
	    }

	    push @cand, $bs; # add new candidate
	    $cl->add($bs); # update Cf 
	}

	# caching process
	my @tmp = (); 
	for my $bs (@cand) {
	    $bs->cached(1) if $bs->sid != $sid;
	    my $tmp; $tmp->{bs} = $bs;
	    $tmp->{score} = $self->{np_cache_model}->predict(&_ext_fe_np_cache($bs, $cl, $sid, \@conj, $sent[$bs->sid]->bunsetsu));
	    push @tmp, $tmp;
	}
	my @srtd = sort {$b->{score} <=> $a->{score}} @tmp;
	@cache = (); # init
	for (my $i=0;$i<$self->{opt}{c};$i++) {
	    push @cache, $srtd[$i]->{bs} if $srtd[$i];
	}
    }

    return;
}

sub _ext_fe_np_anaphoricity {
    my ($ana, $s, $cand_ref, $n2v_ref) = @_;
    my @fe = ();

    my $ana_v = $n2v_ref->{$ana->bf_ext};
    if ($ana_v) {
	push @fe, map 'ana_v_'.$_, split ' ', $ana_v;
    }

    my @b = @{$s->bunsetsu}; my $b_num = @b;
    my $subj_pre = 0;
    for my $b (@b) {
	$subj_pre = 1 if $b->_case eq 'が';
    }
    push @fe, 'subj_pre_m:1' if $subj_pre;

    push @fe, 'first_sent:1'       if $ana->sid == 0;
    push @fe, 'first_morph_in_s:1' if $ana->id == 1;

#     push @fe, 'np_lemma_'.$ana->_pred.':1' if $ana->_pred;
    my $ne = $ana->head_n_morph->ne;
    if ($ne ne 'O') {
	$ne =~ s/[BIE]-//;
	push @fe, 'np_ne_'.$ne.':1';
    }
#    push @fe, 'np_lemma_'.$ana->bf_ext.':1';
    push @fe, 'np_pos_'.$ana->head_pos.':1';
    push @fe, 'np_case_'.$ana->_case.':1';

    if ($ana->dep ne '-1') {
	my $db = $b[$ana->dep];
	push @fe, 'dep_lemma_'.$ana->head_pos.':1';
	push @fe, 'dep_pos_'.$ana->head_pos.':1';
	push @fe, 'dep_case_'.$ana->_case.':1';
    }

    for my $db (@{$ana->dtr}) {
	push @fe, 'dtr_lemma_'.$ana->head_pos.':1';
	push @fe, 'dtr_pos_'.$ana->head_pos.':1';
	push @fe, 'dtr_case_'.$ana->_case.':1';
    }

    my $comp_match = 0;
    my $head_match = 0;
    my $regex_match = 0;
    for my $cand (@{$cand_ref}) {
	my $ana_str = $ana->bf_str;
	my $cand_str = $cand->bf_str;
	my $ana_head_str = $ana->head_n_bf;
	my $cand_head_str = $cand->head_n_bf;
	$comp_match = 1 if $ana_str eq $cand_str;
	$head_match = 1 if $ana_head_str eq $cand_head_str;
	$regex_match = 1 if $cand_head_str =~ /$ana_head_str/;
    }
    push @fe, 'comp_match:1' if $comp_match;
    push @fe, 'head_match:1' if $head_match;
    push @fe, 'regex_match:1' if $regex_match;

    grep s/\:/ /g, @fe;

    return join ' ', @fe;
}

sub _ext_fe_np_coreference {
    my ($ana, $cand, $b_ref, $n2v_ref) = @_;

    my @fe = ();

#     my $cand_str = $cand->head_n_bf;
#     my $ana_str = $ana->head_n_bf;
#     push @fe, 'lemma_pair_'.$cand_str.'_'.$ana_str.':1';

    my $ana_v = $n2v_ref->{$ana->bf_ext};
    if ($ana_v) {
	push @fe, map 'ana_v_'.$_, split ' ', $ana_v;
    }
    my $cand_v = $n2v_ref->{$cand->bf_ext};
    if ($cand_v) {
	push @fe, map 'cand_v_'.$_, split ' ', $cand_v;
    }

    push @fe, 'first_sent:1' if $cand->sid == 0;
    push @fe, 'first_mentioned:1' if $cand->FIRST_MENTIONED;
    push @fe, 'cand_pos_'.$cand->head_n_pos.':1';
    push @fe, 'cand_case_'.$cand->_case.':1';
    my $ne = $cand->head_n_ne; $ne =~ s/^(B|I|E)-//;
    push @fe, 'cand_ne_'.$ne.':1' if $ne ne 'O';
    if ($ana->sid - $cand->sid) {
	push @fe, 'sentdist:'.($ana->sid - $cand->sid);
    } elsif ($ana->sid == $cand->sid) {
	if ($cand->id < $ana->id) {
	    push @fe, 'cand_precedes_pred:1';
	} else {
	    push @fe, 'pred_precedes_cand:1';
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
    push @fe, 'cand_demon:1' if $demon_flg == 1;
    push @fe, 'cand_det:1'   if $det_flg   == 1;
    push @fe, 'cand_poss:1'  if $poss_flg  == 1;

    # str_match
    my $ana_str = $ana->bf_str;
    my $cand_str = $cand->bf_str;
    my $ana_head_str = $ana->head_n_bf;
    my $cand_head_str = $cand->head_n_bf;
    push @fe, 'comp_match:1' if $ana_str eq $cand_str;
    push @fe, 'head_match:1' if $ana_head_str eq $cand_head_str;
    push @fe, 'regex_match:1' if $cand_head_str =~ /$ana_head_str/;

    grep s/\:/ /g, @fe;
    return join ' ', @fe;
}

sub _ext_fe_np_cache {
    my ($bs, $cl, $sid, $conj_ref, $bs_ref) = @_;
    
    my @fe = ();

    push @fe, '_first_sent 1' if ($bs->sid == 0);
    push @fe, '_case_'.$bs->_case.' 1' if ($bs->_case);
    push @fe, '_pos_'.$bs->head_pos.' 1';

#     push @fe, '_head_bf'.$bs->head_bf.':1';

    push @fe, '_cached 1' if ($bs->cached);

    my $cl_rank  = $cl->rank($bs);
    my $cl_order = $cl->order($bs);
    push @fe, '_cl_rank_'.$cl_rank.' 1'   if ($cl_rank);
    push @fe, '_cl_order_'.$cl_order.' 1' if ($cl_order);

    my $cur_sid = (defined $bs->referred_sid)? $bs->referred_sid : $bs->sid;
    my $diff = $sid - $cur_sid;
    push @fe, '_sent_diff '.$diff;

    push @fe, '_chain_num '.$bs->chain_num if ($bs->chain_num);

    push @fe, '_in_q 1' if ($bs->in_q);
    push @fe, '_emphasis 1' if ($bs->emphasis);
    push @fe, '_pred 1' if ($bs->_pred);

    push @fe, '_depend_last_bunsetsu 1' if ($bs->dep ne '-1' and $bs_ref->[$bs->dep]->dep eq '-1');

    for (my $i=$bs->sid;$i<=$sid;$i++) {
	if ($conj_ref->[$i]) {
	    for my $conj (@{$conj_ref->[$i]}) {
		push @fe, '_conj_'.$conj.' 1';
	    }
	}
    }

#     my $bs_num = @{$bs_ref};
#     if ($bs->dep ne '-1' and $bs->_case eq 'の') {
# 	if ($bs_ref->[$bs->dep]->_case) {
# 	    push @fe, '_dep_case_'.$bs_ref->[$bs->dep]->_case.' 1';
# 	}
#     }

    push @fe, '_end_bunsetsu 1' if ($bs->dep eq '-1');

    return join ' ', @fe;
}

1;
