use strict;
use warnings;
use utf8;
# use open ':utf8';

package Text;

sub new {
    my $self = {};
    my $type = shift;
    bless $self, $type;

    my $in = shift;
    my @in = split '\n', $in;
    my $docinfo = shift @in;
    pop @in; pop @in unless $in[-1]; # end document
    my ($doc_id) = ($docinfo =~ /begin document (.*)/);
    unshift @in, $docinfo unless ($docinfo =~ /begin document (.*)/);
    $self->{id} = $doc_id;

    my @s = (); my $sid = 0;
    my $ss = '';
    for my $elm (@in) {
	if ($elm =~ /EOS/) {
	    push @s, Sentence->new($ss, $sid++);
	    $ss = '';
	} else {
	    $ss .= $elm."\n";
	}
    }
    $self->sentence(\@s);

    return $self;
}

sub id {
    my $self = shift;
    if (@_) {
	$self->{id} = $_[0];
    } else {
	return $self->{id};
    }
}

sub sentence {
    my $self = shift;
    if (@_) {
	$self->{sentence} = $_[0];
    } else {
	return $self->{sentence};
    }
}

package Sentence;

sub new {
    my $self = {}; 
    my $type = shift;
    bless $self, $type;

    my $raw_sentence = shift;
    my $sid = shift;
#      print STDERR 'sid: ', $sid, "\n";
    $raw_sentence =~ s|EOS\n||sm;
    
    $self->id($sid);

    my @raw_chunk = split '\* ', $raw_sentence;
    shift @raw_chunk; # null data

    my @bunsetsu = ();
    my %dtr = ();
    my $bid = 0;
    for my $raw_chunk (@raw_chunk) {
#	print STDERR 'raw: '.$raw_chunk."\n";
	my ($seg_info, @raw_morph) = split '\n', $raw_chunk;
	my $cur_bunsetsu = Bunsetsu->new();	$cur_bunsetsu->{sid} = $sid;
	($cur_bunsetsu->{id},   $cur_bunsetsu->{dep},
	 $cur_bunsetsu->{dep_type},
	 $cur_bunsetsu->{head}, $cur_bunsetsu->{func}, $cur_bunsetsu->{dep_wei}) =
	     ($seg_info =~ m|(\d+) (-?\d+)(\w) (\d+)/(\d+) ([\.\d]+)?|);
	push @{$dtr{$cur_bunsetsu->{dep}}}, $cur_bunsetsu->{id};

	$cur_bunsetsu->{bid} = $cur_bunsetsu->{id};
	$cur_bunsetsu->{dtr} = 
	    ($dtr{$cur_bunsetsu->{id}})? $dtr{$cur_bunsetsu->{id}} : [];
	my @morph = ();
	for my $raw_morph (@raw_morph) {
	    if ($raw_morph =~ /^\!/) {
		my $tmp = $raw_morph; $tmp =~ s/^\! //;
		my ($name, $val) = split '\:', $tmp;
		if ($name eq 'PRED_ID') {
		    $cur_bunsetsu->{type} = 'pred';
		} elsif ($name eq 'ID') {
		    $cur_bunsetsu->{'ID'} = $val;
		} else {
		    $name = lc($name); $val = lc($val);
		    $cur_bunsetsu->{$name} = $val;
		}
	    } else {
		my $cur_morph = Morpheme->new($raw_morph, $cur_bunsetsu);
		push @morph, $cur_morph;
	    }
	}
	my $m_num = @morph;
	for (my $i=0;$i<$m_num;$i++) {
 	    $morph[$i]->mid($i); 
	    $morph[$i]->bid($bid);
 	    $morph[$i]->sid($sid); 
	}
	$bid++;
	$cur_bunsetsu->morph(\@morph);

	$cur_bunsetsu->bf_ext($morph[$cur_bunsetsu->head]->bf_ext);
	$cur_bunsetsu = $cur_bunsetsu->detect_head_n();
	$cur_bunsetsu = $cur_bunsetsu->change_head();

	# add 'eq' and 'id' tag
	if ($morph[$cur_bunsetsu->head_n]->{remain}) {
	    my @r = split ' ', $morph[$cur_bunsetsu->head_n]->{remain};
	    for my $r (@r) {
		$cur_bunsetsu->eq($1)   if ($r =~ m|^eq=\"(.*?)\"|);
		$cur_bunsetsu->ID($1)   if ($r =~ m|^id=\"(.*?)\"|);
		$cur_bunsetsu->type($1) if ($r =~ m|^type=\"(.*?)\"|);
		$cur_bunsetsu->ga($1)   if ($r =~ m|^ga=\"(.*?)\"|);
		$cur_bunsetsu->o($1)    if ($r =~ m|^o=\"(.*?)\"|);
		$cur_bunsetsu->ni($1)   if ($r =~ m|^ni=\"(.*?)\"|);
	    }
	}

	push @bunsetsu, $cur_bunsetsu;
    }

    for (reverse @bunsetsu) {
	$_->_pred($_->ext_pred(\@bunsetsu));
	$_->_case($_->ext_case());
	$_->check_alt();
    }
#     print STDERR scalar(@bunsetsu), "\n";
    # print STDERR 'raw: ', $raw_sentence, "\n" unless $bunsetsu[0];
    $bunsetsu[0]->sent_begin(1);
    $bunsetsu[-1]->sent_end(1);

    my $in_q = 0; my $b_num = @bunsetsu;
    for (my $bid=0;$bid<$b_num;$bid++) {
	my $begin_paren = 0;
	my $end_paren   = 0;
	for (@{$bunsetsu[$bid]->morph}) {
	    $in_q++ if ($_->bf eq '「');
	    $begin_paren = 1 if ($_->bf eq '「');
	    $in_q-- if ($_->bf eq '」');
	    $end_paren =   1 if ($_->bf eq '」');
	    $_->in_q($in_q);
	}
	$bunsetsu[$bid]->in_q($bunsetsu[$bid]->morph->[$bunsetsu[$bid]->head]->in_q);
	$bunsetsu[$bid]->emphasis(1) if ($begin_paren and $end_paren);
    }

    $self->mark_clause_end(\@bunsetsu);

    for (my $bid=0;$bid<$b_num;$bid++) {
	if ($bunsetsu[$bid]->is_cand_all) {
	    $bunsetsu[$bid]->FIRST_MENTIONED(1);
	    last;
	}
    }

    $self->bunsetsu(\@bunsetsu);


    
    return $self;
}

sub mark_clause_end {
    my $self = shift;
    my @b = @_;
    return;
}

sub bunsetsu {
    my $self = shift;
    if (@_) {
	$self->{bunsetsu} = $_[0];
    } else {
	return $self->{bunsetsu};
    }
}

sub str {
    my $self = shift;
    return join '', map $_->str, @{$self->bunsetsu};
}

## miscs

sub id {
    my $self = shift;
    if (@_) {
	$self->{id} = $_[0];
    } else {
	return $self->{id};
    }
}

sub ID {
    my $self = shift;
    if (@_) {
	$self->{ID} = $_[0];
    } else {
	return $self->{ID};
    }
}

sub puts {
    my $self = shift;
    my $out = '';
#     $out .= '# S-ID:'. $self->id. "\n";
    my @B = @{$self->bunsetsu};
    for my $b (@B) {
        $out .= $b->puts;
    }
    $out .= "EOS\n";
    return $out;
}

package Bunsetsu;

sub new {
    my $self = {};
    my $type = shift;
    bless $self, $type;

    return $self;
}

sub morph {
    my $self = shift;
    if (@_) {
	$self->{morph} = $_[0];
    } else {
	return $self->{morph};
    }
}

sub dtr {
    my $self = shift;
    if (@_) {
	$self->{dtr} = $_[0];
    } else {
	return $self->{dtr};
    }
}

# sub prev {
#     my $self = shift;
#     if (@_) {
# 	$self->{prev} = $_[0];
#     } else {
# 	return $self->{prev};
#     }
# }

# sub next {
#     my $self = shift;
#     if (@_) {
# 	$self->{next} = $_[0];
#     } else {
# 	return $self->{next};
#     }
# }

# sub parent {
#     my $self = shift;
#     if (@_) {
# 	$self->{parent} = $_[0];
#     } else {
# 	return $self->{parent};
#     }
# }

sub id {
    my $self = shift;
    if (@_) {
	$self->{id} = $_[0];
    } else {
	return $self->{id};
    }
}

sub bid {
    my $self = shift;
    if (@_) {
	$self->{id} = $_[0];
    } else {
	return $self->{id};
    }
}

sub sid {
    my $self = shift;
    if (defined $_[0]) {
	$self->{sid} = $_[0];
    } else {
	return $self->{sid};
    }
}

sub dep {
    my $self = shift;
    if (@_) {
	$self->{dep} = $_[0];
    } else {
	return $self->{dep};
    }
}

sub dep_type {
    my $self = shift;
    if (@_) {
	$self->{dep_type} = $_[0];
    } else {
	return $self->{dep_type};
    }
}

sub head {
    my $self = shift;
    if (@_) {
	$self->{head} = $_[0];
    } else {
	return $self->{head};
    }
}

sub head_cp {
    my $self = shift;
    if (@_) {
	$self->{head_cp} = $_[0];
    } else {
	return $self->{head_cp};
    }
}

sub func {
    my $self = shift;
    if (@_) {
	$self->{func} = $_[0];
    } else {
	return $self->{func};
    }
}

sub dep_wei {
    my $self = shift;
    if (@_) {
	$self->{dep_wei} = $_[0];
    } else {
	return $self->{dep_wei};
    }
}

sub str {
    my $self = shift;
    return join '', map $_->wf, @{$self->morph};
}

# misc

sub str_cnt {
    my $self = shift;
    my $str = '';
    for (my $i=0;$i<=$self->head;$i++) {
	$str .= $self->morph->[$i]->wf;
    }
    return $str;
}

sub rank_g {
    my $self = shift;
    if (@_) {
	$self->{rank_g} = $_[0];
    } else {
	return $self->{rank_g};
    }
}

sub score_g {
    my $self = shift;
    if (@_) {
	$self->{score_g} = $_[0];
    } else {
	return $self->{score_g};
    }
}

sub rank_l {
    my $self = shift;
    if (@_) {
	$self->{rank_l} = $_[0];
    } else {
	return $self->{rank_l};
    }
}

sub score_l {
    my $self = shift;
    if (@_) {
	$self->{score_l} = $_[0];
    } else {
	return $self->{score_l};
    }
}

sub referred_sid {
    my $self = shift;
    if (@_) {
	$self->{referred_sid} = $_[0];
    } elsif (defined $self->{referred_sid}) {
	return $self->{referred_sid};
    } else {
	return $self->{sid};
    }
}

sub referred_id {
    my $self = shift;
    if (@_) { 
	$self->{referred_id} = $_[0];
    } elsif (defined $self->{referred_id}) {
	return $self->{referred_id};
    } else {
	return $self->{id};
    }
}

sub referred_bid {
    my $self = shift;
    if (@_) { 
	$self->{referred_id} = $_[0];
    } elsif (defined $self->{referred_id}) {
	return $self->{referred_id};
    } else {
	return $self->{id};
    }
}


sub chain_num {
    my $self = shift;
    if (@_) {
	$self->{chain_num} = $_[0];
    } else {
	return $self->{chain_num};
    }
}

sub chain_num_incr {
    my $self = shift;
    if ($self->{chain_num}) {
	$self->{chain_num}++;
    } else {
	$self->{chain_num} = 1;
    }
}

sub cached {
    my $self = shift;
    if (@_) {
	$self->{cached} = $_[0];
    } else {
	return $self->{cached};
    }
}

sub global_cache_score {
    my $self = shift;
    if (@_) {
	$self->{global_cache_score} = $_[0];
    } else {
	return $self->{global_cache_score};
    }
}

sub local_cache_score {
    my $self = shift;
    if (@_) {
	$self->{local_cache_score} = $_[0]; 
    } else {
	return $self->{local_cache_score};
    }
}

sub score {
    my $self = shift;
    if (@_) {
	$self->{score} = $_[0];
    } else {
	return $self->{score};
    }
}

sub in_q {
    my $self = shift;
    if (@_) {
	$self->{in_q} = $_[0];
    } else {
	return $self->{in_q};
    }
}

sub emphasis {
    my $self = shift;
    if (@_) {
	$self->{emphasis} = 1;
    } else { 
	return $self->{emphasis};
    }
}

sub check_noun {
    my $self = shift;

    return ($self->morph->[$self->head_n]->pos =~ /^(名詞|未知語)/)? 1 : 0;
    
#     if (defined $self->head_cp) {
# 	return ($self->morph->[$self->head_cp]->pos =~ /^名詞/)? 1 : 0;
#     } else {
# 	return ($self->morph->[$self->head]->pos =~ /^名詞/)? 1 : 0;
#     }
}

sub check_noun_ext {
    my $self = shift;

    return 1 if ($self->morph->[$self->head_n]->pos =~ /^(名詞|未知語)/);
    return 1 if ($self->_case =~ /^(?:は|が|を|に|から|へ|と|より|まで|で)$/);
    return 0;
}

sub is_cand {
    my $self = shift;
    return 1 if $self->head_n_pos =~ /^(名詞|未知語)/;
    return 0;
}

sub is_cand_all {
    my $self = shift;
    return 1 if $self->head_n_pos =~ /^(名詞|未知語)/;
#     return 1 if $self->is_pred and $self->ga;
    return 0;
}

sub is_noun {
    my $self = shift;
    return $self->_noun if (defined $self->_noun);
    $self->_noun($self->check_noun);
    return $self->_noun;
}

sub is_noun_ext {
    my $self = shift;
    return $self->_noun_ext if (defined $self->_noun_ext);
    $self->_noun_ext($self->check_noun_ext);
    return $self->_noun_ext;
}

sub _noun {
    my $self = shift;
    if (@_) {
	$self->{_noun} = $_[0];
    } else {
	return $self->{_noun};
    }
}

sub _noun_ext {
    my $self = shift;
    if (@_) {
	$self->{_noun_ext} = $_[0];
    } else {
	return $self->{_noun_ext};
    }
}

sub change_head {
    my $self = shift;
    my @m = @{$self->morph}; my $head = $self->head;
    for (my $i=0;$i<$head;$i++) {
	if ($m[$i]->pos =~ /(?:動詞|形容詞)-自立/) {
	    $self->head($i);
	    $self->head_cp($head);
	    return $self;
	} elsif ($m[$i]->pos =~ /^名詞/ and $m[$i+1] and $m[$i+1]->pos =~ /^(助動詞|記号-読点)/) {
	    $self->head($i);
	    $self->head_cp($head);
	    return $self;
	} elsif ($m[$i]->pos =~ /^名詞-接尾/ and $m[$i+1] and $m[$i+1]->pos =~ /^接続詞/) {
	    $self->head($i);
	    $self->head_cp($head);
	    return $self;
	}
    }
    $self->head_cp($head);
    return $self;
}

sub detect_head_n {
    my $self = shift;
    my @m = @{$self->morph}; my $head = $self->head;
    my $m_num = @m;
    for (my $i=$head+1;$i<$m_num;$i++) {
	$head = $i if ($m[$i]->pos =~ /^名詞/);
    }
    $head-- if ($head != 0 and $m[$head]->pos =~ /名詞-接尾/ and
		$m[$head]->wf =~ /^(ほど|側|)$/);
    $self->head_n($head);
    return $self;
}

sub head_n {
    my $self = shift;
    if (@_) {
	$self->{head_n} = $_[0];
    } else {
	return $self->{head_n};
    }
}


sub _pred {
    my $self = shift;
    if (@_) {
	$self->{_pred} = $_[0];
    } else {
	return $self->{_pred};
    }
}

sub ext_pred {
    my $self = shift; my $b_ref = shift;
    my $pm = ($self->head != 0)? $self->morph->[$self->head-1] : '';
    my $hm = $self->morph->[$self->head];
#      print STDERR 'm: ', ref($hm), "\t", $hm->pos, "\n";
    my $nm = ($self->head != scalar(@{$self->morph}))?
	$self->morph->[$self->head+1] : '';

    if ($hm->pos =~ /^(動詞|形容詞)-自立/) {
	my $pos = $1;

	if ($pos eq '動詞' and $pm and $hm->bf eq 'する'
	    and ($pm->pos eq '名詞-サ変接続' or 
		 ($pm->pos eq '名詞-形容動詞語幹' and $pm->bf =~ /^(?:安定|不自由|迷惑|無理)$/))) {
	    return $pm->bf.$hm->bf;
	}
	return $hm->bf; # その他の動詞 or 形容詞
#     } elsif ($hm->pos eq '名詞-形容動詞語幹' and
    } elsif ($hm->pos =~ /^名詞/ and
	     $nm and $nm->bf =~ /^(?:だ|です)$/) {
	return $hm->bf.$nm->bf;
    } elsif ($hm->pos =~ /名詞-(?:接尾-)?サ変接続/) {
# 	print STDERR 'pos: ', $hm->pos, "\n";
	if ($self->dep eq '-1') {
 	    return $hm->bf.'する';
 	} elsif ($nm and $nm->pos =~ /記号-読点/ and $b_ref->[$self->dep]->_pred) {
 	    return $hm->bf.'する';
 	}
    }

    if ($hm->pos eq '連体詞' and $hm->bf eq '大きな') {
	return '大きい';
    }
    if ($hm->pos eq '連体詞' and $hm->bf eq '小さな') {
	return '小さい';
    }
    if ($hm->pos eq '連体詞' and $hm->bf eq '同じ') {
	return '同じだ';
    }
#     if ($hm->pos eq '連体詞' and $hm->bf eq '確固たる') {
# 	return '確固だ';
#     }
#     if ($hm->pos eq '連体詞' and $hm->bf eq 'いろんあ') {
# 	return 'いろんな';
#     }
    if ($hm->pos eq '名詞-形容動詞語幹') {
	return $hm->bf.'だ';
    }
    if ($hm->bf eq '生まれ') {
	return '生まれる';
    }
    if ($hm->bf eq 'ある' and $hm->pos =~ /(助動詞|連体詞)/) {
	return $hm->bf;
    }
    if ($hm->pos eq '名詞-接尾-助数詞') {
	return $self->head_bf.'だ';
    }
    if ($hm->pos eq '名詞-一般' and $nm and $nm->bf eq '。') {
	return $hm->bf.'だ';
    }
    if ($hm->pos eq '動詞-非自立' and $hm->bf eq 'なる'){
	return 'なる';
    }
    if ($hm->pos eq '助動詞' and $hm->bf eq 'ない'){
	return 'ない';
    }
    if ($hm->pos =~ /^副詞/ and $nm and $nm->bf eq '。') {
	return $hm->bf.'だ';
    }

    for my $d (map $b_ref->[$_], @{$self->dtr}) {
	for my $m (@{$d->morph}) {
	    if ($m->bf =~ /^(は|が|も|を|に|から|へ|と|より|まで|で)$/ and
		$m->pos =~ /^助詞-(?!接続助詞)/) {
		if ($self->head_pos =~ /^名詞/) {
		    return $self->head_bf.'だ';
		} else {
# 		    return '';
		}
	    }
	}
    }

    # データ作成時のみ
#     if ($hm->pos =~ /^名詞/) {
# 	return $self->head_bf.'だ';
#     }
#     if ($hm->pos =~ /^形容詞/) {
# 	return $self->head_bf;
#     }
#     if ($hm->pos =~ /^副詞/) {
# 	return $self->head_bf.'だ';
#     }
#     if ($hm->pos =~ /^(動詞|連体詞|助動詞)/) {
# 	return $self->head_bf;
#     }
#     if ($hm->pos =~ /^(未知語|接続詞|感動詞)/) {
# 	return $self->head_bf.'だ';
#     }
    return '';
}

sub is_pred {
    my $self = shift;
#    return 1 if $self->{type} and $self->{type} eq 'pred';
    return 1 if $self->pred_id;
    return 0;
}

sub pred_id {
    my $self = shift;
    if (@_) {
	$self->{pred_id} = $_[0];
    } else {
	return $self->{pred_id};
    }
}

sub _case {
    my $self = shift;
    if (@_) {
	$self->{_case} = $_[0];
    } else {
	return $self->{_case};
    }
}

sub ext_case {
    my $self = shift;
    my $case = '';
    for my $m (@{$self->morph}) {
	if ($m->pos =~ /助詞-格助詞-一般/
	    and $m->wf !~ /^(か|だけ|こそ|など|のみ)$/) {
	    $case .= $m->wf;
	} elsif ($m->pos =~ /助詞-係助詞/) {
	    $case .= $m->wf;
	} elsif ($m->pos =~ /^助詞-格助詞-連語/) {
	    $case .= $m->wf;
#  	    $case .= $rengo{$m->WF};
	} elsif ($m->pos =~ /^助詞(?!-接続助詞)/ and
		 $m->wf !~ /^(か|だけ|こそ|など|のみ)$/) {
	    $case .= $m->wf;
	}
    }
    return ($case)? $case : 'φ';
}

sub head_pos {
    my $self = shift;
    return $self->morph->[$self->head]->pos;
}

sub head_bf {
    my $self = shift;
    return $self->morph->[$self->head]->bf;
}

# sub head_n_bf {
#     my $self = shift;
#     return $self->morph->[$self->head_n]->bf;
# }

sub bf_str {
    my $self = shift;
    my @m = @{$self->morph};
    my @str = ();
    for (my $i=0;$i<=$self->head_n;$i++) {
	push @str, $m[$i]->bf;
    }
    return join '', @str;
}

sub head_n_pos {
    my $self = shift;
    return $self->morph->[$self->head_n]->pos;
}

sub head_n_bf {
    my $self = shift;
    return $self->morph->[$self->head_n]->bf;
}

sub head_n_ne {
    my $self = shift;
    return $self->morph->[$self->head_n]->ne;    
}

sub FIRST_MENTIONED {
    my $self = shift;
    if (@_) {
	$self->{FIRST_MENTIONED} = $_[0];
    } else {
	return $self->{FIRST_MENTIONED};
    }
}

sub sent_begin {
    my $self = shift;
    if (@_) {
	$self->{sent_begin} = $_[0];
    } else {
	return $self->{sent_begin};
    }
}

sub sent_end {
    my $self = shift;
    if (@_) {
	$self->{sent_end} = $_[0];
    } else {
	return $self->{sent_end};
    } 
}

# NTC info
sub ID {
    my $self = shift;
    if (@_) {
	$self->{ID} = $_[0];
    } else {
	return $self->{ID};
    }
}

sub eq {
    my $self = shift;
    if (@_) {
	$self->{eq} = $_[0];
    } else {
	return $self->{eq};
    }
}

sub GA {
    my $self = shift;
    if (@_) {
	$self->{GA} = $_[0];
    } else {
	return $self->{GA};
    }
}

sub O {
    my $self = shift;
    if (@_) {
	$self->{O} = $_[0];
	$self->{WO} = $_[0];
    } else {
	return $self->{O};
    }
}

sub WO {
    my $self = shift;
    if (@_) {
	$self->{WO} = $_[0];
    } else {
	return $self->{WO};
    }
}


sub o {
    my $self = shift;
    if (@_) {
	$self->{o} = $_[0];
	$self->{wo} = $_[0];
    } else {
	return $self->{o};
    }
}

sub wo {
    my $self = shift;
    if (@_) {
	$self->{wo} = $_[0];
    } else {
	return $self->{wo};
    }
}

sub ni {
    my $self = shift;
    if (@_) {
	$self->{ni} = $_[0];
    } else {
	return $self->{ni};
    }
}

sub TYPE {
    my $self = shift;
    if (@_) {
	$self->{TYPE} = $_[0];
    } else {
	return $self->{TYPE};
    }
}
sub type {
    my $self = shift;
    if (@_) {
	$self->{type} = $_[0];
    } else {
	return $self->{type};
    }
}

sub has_GA {
    my $self = shift;
    return 1 if ($self->{GA});
    return 0;
}

sub TYPE_is_pred {
    my $self = shift;
    return 1 if ($self->TYPE and $self->TYPE eq 'pred');
    return 0;
}

sub has_dep_rel_with {
    my $self = shift;
    my $arg = shift;
    if ($self->dep ne '-1') {
	return 1 if ($self->sid.':'.$self->dep eq $arg->sid.':'.$arg->id)
    }
    for my $d (@{$self->dtr}) {
	return 1 if ($self->sid.':'.$d eq $arg->sid.':'.$arg->id);
    }
    return 0;
}

sub add_dep_pred {
    my $self = shift;
    die "please set 1st arg of add_dep_pred\n".$! unless @_;
    my $pred = shift;
    push @{$self->{dep_pred}}, $pred;
    return;
}

sub dep_pred {
    my $self = shift;
    return (ref($self->{dep_pred}) eq 'ARRAY')? $self->{dep_pred} : [];
}

# sub has_dep_pred {
# }


sub EQ {
    my $self = shift;
    if (@_) {
	$self->{EQ} = $_[0];
    } else {
	return $self->{EQ};
    }
}

sub bf_ext {
    my $self = shift;
    if (@_) {
	$self->{bf_ext} = $_[0];
    } else {
	return $self->{bf_ext};
    }
}

sub dep_verb_add {
    my $self = shift;
    if (@_) {
	$self->{dep_verb}{$_} = 1;
    } else {
	die "please set arg in dep_verb_add\n".$!;
    }
}

sub dep_verb {
    my $self = shift;
    if ($self->{dep_verb}) {
	return keys %{$self->{dep_verb}};
    } else {
	return ();
    }
}

sub check_alt {
    my $self = shift;
    for my $m (@{$self->morph}) {
	$self->{passive}   = 1 if ($m->bf =~ /^(?:れる|られる)$/);
	$self->{causative} = 1 if ($m->bf =~ /^(?:せる|させる)$/);
	$self->{alt_func}{$m->bf} = 1 if ($m->bf =~ /^(ほしい|もらう|いただく|たい|くれる|下さる|くださる|やる|あげる)$/);
    }
    return;
}

sub passive {
    my $self = shift;
    if (@_) {
	$self->{passive} = 1;
    } else {
	return $self->{passive};
    }
}

sub causative {
    my $self = shift;
    if (@_) {
	$self->{causative} = 1;
    } else {
	return $self->{causative};
    }
}

sub alt_func {
    my $self = shift;
    if ($self->{alt_func}) {
	my @a = keys %{$self->{alt_func}};
	return \@a;
    } else {
	return [];
    }
}

sub has_dep {
    my $self = shift;
    return 1 if ($self->dep ne '-1');
    return 0;
}

sub in_path {
    my $self = shift;
    if (@_) {
	$self->{in_path} = $_[0];
    } else {
	return $self->{in_path};
    }
}

sub puts {
    my $self = shift;
    my @mor = @{$self->morph};
    my $out = '';
    $out .= '* '.$self->id.' '.$self->dep.$self->dep_type.' '.
	$self->head.'/'.$self->func;
    $out .= ' '.$self->{dep_wei} if (defined $self->{dep_wei});
    $out .= "\n";
    for my $m (@mor) {
        $out .= $m->puts;
    }
    return $out;
}

sub ga {
    my $self = shift;
    if (@_) {
	$self->{ga} = $_[0];
    } else {
	return $self->{ga};
    }
}

sub eq_ID {
    my ($self, $ID) = @_;
#     if ($self->{ID}) {
# 	for (@{$self->{ID}}) {
# 	    return 1 if $_ eq $ID;
# 	}
#     }
    return 1 if $self->is_pred and $self->ga and $self->ga eq $ID;
    return 0;
}

sub eq_eq {
    my ($self, $b) = @_;
    my %eq = ();
    for my $m (@{$self->morph}) {
	$eq{$m->eq} = 1 if $m->eq;
    }
    for my $m (@{$b->morph}) {
	return 1 if $m->eq and $eq{$m->eq};
    }
#    return 1 if $self->eq and $b->eq and $self->eq == $b->eq;
    return 0;
}

sub eq_ID_ref {
    my ($self, $ID_ref) = @_;
    for my $ID (keys %{$ID_ref}) {
	for my $b (@{$ID_ref->{$ID}}) {
	    return 1 if $self->eq_ID_b($b);
	}
    }
    return 0; 
}

sub is_ga_of {
    my ($self, $ga_id, $eq2id_ref) = @_;
    my @cm = @{$self->morph}; my $cm_num = @cm;
    return 0 unless $ga_id;
    for my $cm (@cm) {
	return 1 if $cm->id and $cm->id eq $ga_id;
	return 1 if $cm->eq and $eq2id_ref->{$cm->eq} and 
    	            $eq2id_ref->{$cm->eq}{$ga_id};
#    	            $eq2id_ref->{$cm->eq} eq $ga_id;
    }
#     return 1 if $b->is_pred and $b->ga and $self->eq_ID($b->ga);
    return 0;
}

sub is_case_of {
    my ($self, $case_id, $eq2id_ref) = @_;
    my @cm = @{$self->morph}; my $cm_num = @cm;
    return 0 unless $case_id;
    for my $cm (@cm) {
	return 1 if $cm->id and $cm->id eq $case_id;
	return 1 if $cm->eq and $eq2id_ref->{$cm->eq} and 
    	            $eq2id_ref->{$cm->eq}{$case_id};
    }
    return 0;
}



sub mention {
    my $self = shift;
    if (@_) {
	$self->{mention} = $_[0];
    } else {
	return $self->{mention};
    }
}

sub head_morph {
    my $self = shift;
    return $self->morph->[$self->head];
}

sub head_n_morph {
    my $self = shift;
    return $self->morph->[$self->head_n];
}

sub head_n_eq {
    my $self = shift;
    if (@_) {
	$self->head_n_morph->eq($_[0]);
    } else {
	return $self->head_n_morph->eq;
    }
}

package Morpheme;

sub new {
    my $self = {};
    my $type = shift;
    bless $self, $type;

    my $raw_morph = shift;

    my $cur_bunsetsu = shift;

    my @remain;
    my @raw_morph = split '\t', $raw_morph;
    if (scalar(@raw_morph) == 3 or scalar(@raw_morph) == 2) {

        $self->{wf} = $raw_morph[0];
        $self->{ne} = $raw_morph[2];
        my @info = split ',', $raw_morph[1];
        $self->{read} = $info[7];
        $self->{read2} = ($info[8])? $info[8] : '';
	$self->{misc1} = ($info[9])? $info[9] : ''; 
	$self->{misc2} = ($info[10])? $info[10] : ''; 
        $self->{bf}   = $info[6];
        $self->{cf}   = $info[5]; $self->{cf} = '' if ($self->{cf} eq '*');
        $self->{ct}   = $info[4]; $self->{ct} = '' if ($self->{ct} eq '*');
        $self->{pos}  = $info[0].'-'.$info[1].'-'.$info[2].'-'.$info[3];
	$self->{pos1} = $info[0]; $self->{pos2} = $info[1];
	$self->{pos3} = $info[2]; $self->{pos4} = $info[3];
        $self->{pos} =~ s/-\*//g;

        $self->{read} = '' unless $self->{read};
	$self->{bf_org} = $self->{bf};
        $self->{bf} = $self->{wf} if ($self->{bf} eq '*');
    } else {
        ($self->{wf},  $self->{read}, $self->{bf},
         $self->{pos}, $self->{ct},
         $self->{cf},  $self->{ne}, @remain) = @raw_morph;
    }

    $self->{remain} = join "\t", @remain;
    $self->{bf} = $self->{wf} unless $self->{bf};
    $self->bf_ext(&ext_bf_extent($self->bf, $self->pos, $self->ne));
#     print STDERR $self->bf."\n";
#     print STDERR $self->bf_ext."\n";


    $self->{wo} = $self->{o} if ($self->{o});

    return $self;
}

sub wf {
    my $self = shift;
    if (@_) {
	$self->{wf} = $_[0];
    } else {
	return $self->{wf};
    }
}

sub read {
    my $self = shift;
    if (@_) {
	$self->{read} = $_[0];
    } else {
	return $self->{read};
    }
}

sub bf {
    my $self = shift;
    if (@_) {
	$self->{bf} = $_[0];
    } else {
	return $self->{bf};
    }
}

sub ext_bf_extent {
    my ($bf, $pos, $ne) = @_;
    if ($pos =~ /固有名詞-(一般|人名|組織|地域)/) {
	return '＜固有名詞'.$1.'＞';
#     } elsif ($ne =~ /PERSON/) {
# 	return '＜固有名詞人名＞';
#     } elsif ($ne =~ /LOCATION/) {
# 	return '＜固有名詞地域＞';
#     } elsif ($ne =~ /ORGANIZATION/) {
# 	return '＜固有名詞組織＞';
#     } elsif ($ne =~ /ARTIFACT/) {
# 	return '＜固有名詞一般＞';
    }
    return $bf;
}


sub bf_ext {
    my $self = shift;
    if (@_) {
	$self->{bf_ext} = $_[0];
    } else {
	return $self->{bf_ext};
    }
}

sub pos {
    my $self = shift;
    if (@_) {
	$self->{pos} = $_[0];
    } else {
	return $self->{pos};
    }
}

# sub pos1 {
#     my $self = shift;
#     if (@_) {
# 	$self->{pos1} = $_[0];
#     } else {
# 	return $self->{pos1};
#     }
# }

# sub pos1 {
#     my $self = shift;
#     if (@_) {
# 	$self->{pos1} = $_[0];
#     } else {
# 	return $self->{pos1};
#     }
# }

# sub pos2 {
#     my $self = shift;
#     if (@_) {
# 	$self->{pos2} = $_[0];
#     } else {
# 	return $self->{pos2};
#     }
# }

# sub pos3 {
#     my $self = shift;
#     if (@_) {
# 	$self->{pos3} = $_[0];
#     } else {
# 	return $self->{pos3};
#     }
# }

# sub pos4 {
#     my $self = shift;
#     if (@_) {
# 	$self->{pos4} = $_[0];
#     } else {
# 	return $self->{pos4};
#     }
# }


sub ct {
    my $self = shift;
    if (@_) {
	$self->{ct} = $_[0];
    } else {
	return $self->{ct};
    }
}

sub cf {
    my $self = shift;
    if (@_) {
	$self->{cf} = $_[0];
    } else {
	return $self->{cf};
    }
}

sub ne {
    my $self = shift;
    if (@_) {
	$self->{ne} = $_[0];
    } else {
	return $self->{ne};
    }
}

sub in_q {
    my $self = shift;
    if (@_) {
	$self->{in_q} = $_[0];
    } else {
	return $self->{in_q};
    }
}

# sub check_aux {
#     my $m = shift;
#     return 1 if ($m->BF =~ /^(?:れる|られる|せる|させる|ほしい|もらう|いただく|
#                               たい|くれる|下さる|くださる|やる|あげる)$/x);
#     return 0;
# }


# sub prev {
#     my $self = shift;
#     if (@_) {
# 	$self->{prev} = $_[0];
#     } else {
# 	return $self->{prev};
#     }
# }

# sub next {
#     my $self = shift;
#     if (@_) {
# 	$self->{next} = $_[0];
#     } else {
# 	return $self->{next};
#     }
# }

sub parent {
    my $self = shift;
    if (@_) {
	$self->{parent} = $_[0];
    } else {
	return $self->{parent};
    }
}

sub id {
    my $self = shift;
    if (@_) {
	$self->{id} = $_[0];
    } else {
	return $self->{id};
    }
}

sub eq {
    my $self = shift;
    if (@_) {
	$self->{eq} = $_[0];
    } else {
	return $self->{eq};
    }
}

sub type {
    my $self = shift;
    if (@_) {
	$self->{type} = $_[0];
    } else {
	return $self->{type};
    }
}

sub ga {
    my $self = shift;
    if (@_) {
	$self->{ga} = $_[0];
    } else {
	return $self->{ga};
    }
}

sub wo {
    my $self = shift;
    if (@_) {
	$self->{wo} = $_[0];
    } else {
	return $self->{wo};
    }
}

sub o {
    my $self = shift;
    if (@_) {
	$self->{o} = $_[0];
    } else {
	return $self->{o};
    }
}

sub ni {
    my $self = shift;
    if (@_) {
	$self->{ni} = $_[0];
    } else {
	return $self->{ni};
    }
}

sub puts_old {
    my $self = shift;
    my $out = '';
    $out .= $self->wf.   "\t";
    $out .= $self->read. "\t";
    $out .= $self->bf.   "\t";
    $out .= $self->pos.  "\t";
    if ($self->ct) {
        $out .= $self->ct. "\t";
    } else {
        $out .= "_\t";
    }
    if ($self->cf) {
        $out .= $self->cf;
    } else {
	$out .= "_";
    }
    if ($self->ne) {
        $out .= "\t". $self->ne;
    } else {
	$out .= "\t_";
    }
    if ($self->{remain}) {
	$self->{remain} =~ s/^ //;
        $out .= "\t".$self->{remain};
    } else {
        $out .= "\t_";
    }
    $out .= "\n";
    return $out;
}

sub puts {
    my $self = shift;
#     my $out = $self->wf."\t".$self->{pos1}.','.$self->{pos2}.','.$self->{pos3}.','.$self->{pos4}.','.$self->ct.','.$self->cf.','.$self->{bf_org}.','.$self->read.','.$self->{read2}.','.$self->{misc1}.','.$self->{misc2}."\t".$self->ne."\t".$self->attrs."\n";
    my $out = $self->wf."\t".$self->{pos1}.','.$self->{pos2}.','.$self->{pos3}.','.$self->{pos4}.','.$self->ct.','.$self->cf.','.$self->{bf_org}.','.$self->read.','.$self->{read2}.','.$self->{misc1}.','.$self->{misc2}."\t".$self->ne."\t".$self->attrs."\n";
    return $out;
}

sub is_cand {
    my $self = shift;
    return 1 if $self->pos =~ /^(名詞|未知語)/;
    return 0;
}

sub is_ga_of {
    my ($self, $ga_id, $eq2id_ref) = @_;
    return 0 unless $ga_id;
    return 1 if $self->id and $self->id eq $ga_id;
    return 1 if $self->eq and $eq2id_ref->{$self->eq} and 
	        $eq2id_ref->{$self->eq}{$ga_id};
    return 0;
}

sub mid {
    my $self = shift;
    if (@_) {
	$self->{mid} = $_[0];
    } else {
	return $self->{mid};
    }
}

sub sid {
    my $self = shift;
    if (@_) {
	$self->{sid} = $_[0];
    } else {
	return $self->{sid};
    }
}

sub bid {
    my $self = shift;
    if (@_) {
	$self->{bid} = $_[0];
    } else {
	return $self->{bid};
    }
}

sub attrs {
    my $self = shift;

    return '' unless $self->{attrs};
    my $ref = $self->{attrs};
    return join ' ', map $_.'="'.$ref->{$_}.'"', sort keys %{$ref};
}

sub eventnoun_id {
    my $self = shift;
    if (@_) {
	$self->{eventnoun_id} = $_[0];
    } else {
	return $self->{eventnoun_id};
    } 
}

sub is_eventnoun {
    my $self = shift;
    return 1 if $self->eventnoun_id;
    return 0;
}

sub sbm {
    my $self = shift;
    return $self->sid.'/'.$self->bid.'/'.$self->mid;
}

sub is_noun_sahen {
    my $self = shift;
    return 1 if $self->pos =~ /^名詞-サ変接続/;
    return 0;
}

1;
