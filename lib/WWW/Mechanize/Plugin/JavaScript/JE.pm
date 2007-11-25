package WWW::Mechanize::Plugin::JavaScript::JE;

use strict;   # :-(
use warnings; # :-(

use Carp 'croak';
use HTML::DOM::Interface ':all'; # for the constants
use JE 0.019;
use Scalar::Util qw'weaken';

our $VERSION = '0.001';
our @ISA = 'JE';

# No need to implement eval and new_function, since JE's methods
# are sufficient

sub new {
	my $self = SUPER::new{shift};
	$self->prop('window' => $self);
}

sub set {
	my $obj = shift;
	my $val = pop;
	croak "Not enough arguments for W:M:P:JS:JE->set" unless @_;
	my $prop = pop;
	for (@_) {
		my $next_obj = $obj->{$_};
		defined $next_obj or
			$obj->{$_} = {},
			$obj = $obj->{$_}, next;
		$obj = $next_obj;
	}
	$obj->{$prop} = $val;
	return;
}

my @types;
$types[BOOL] = Boolean =>;
$types[STR ] = String  =>;
$types[NUM ] = Number  =>;
$types[OBJ ] = null    =>;

sub bind_classes {
	my($self, $classes) = @_;
	my @defer;
	for (grep /::/, keys %$classes) {
		my $i = $$classes{$$classes{$_}}; # interface info
		my @args = (
			package => $_,
			name    => $$classes{$_},
			methods => [ map 
			   $$i{$_} & VOID ? $_ : "$_:$types[$$i{$_} & TYPE]",
			   grep !/^_/ && $$i{$_} & METHOD, keys %$i ],
			props => [ map 
			   $$i{$_} & VOID ? $_ : "$_:$types[$$i{$_} & TYPE]",
			   grep !/^_/ && !($$i{$_} & METHOD), keys %$i ],
			hash  => $$i{_hash},
			array => $$i{_array},
			exists $$i{_isa} ? (isa => $$i{_isa}) : (),
			exists $$i{_constructor}
				? (constructor => $$i{_constructor})
				: (),
		);
		my $make_constants;
		if(exists $$i{_constants}){
		  my $p = $_;
		  $make_constants = sub { for(@{$$i{_constants}}){
			/([^:]+\z)/;
			$self->{$$classes{$p}}{$1} =
			# ~~~ to be replaced simply with 'eval' when JE's
			#     upgrading is improved:
				$self->upgrade(eval)->to_number;
		}}}
		if (exists $$i{_isa} and !exists $self->{$$i{_isa}}) {
			push @defer, [\@args, $$i{_isa}, $make_constants]
		} else {
			#use DDS; Dump \@args if $_ =~ /Location/;
			$self->bind_class(@args);
			defined $make_constants and &$make_constants;
		}
	}
	while(@defer) {
		my @copy = @defer;
		@defer = ();
		for (@copy) {
			if(exists $self->{$$_[1]}) { # $$_[1] == superclass
				$self->bind_class(@{$$_[0]});
				&{$$_[2] or next}
			}
			else {
				push @defer, $_;
			}
		}
	}
	return;
}

sub event2sub {
	my ($w, $code, $elem) = @_;

# for debugging
#	if($code =~ /allitems.value/) {
#		$w->new_function(warn => sub { warn @_});
#		$code = '
#			var m ="";
#			for(var i=0;i<items.length;i++){
#				warn (items.options);
#				m += items.options[i].value + " ";
#				warn ("still here " + i);
#			}
#			warn ("done the list");
#			m = m.substring(0,m.length-1);
#			warn ("choppped");
#			allitems.value=m
#			warn ("assigned");
#		';
#	}

	# ~~~ JE's interface needs to be improved. This is a mess:
	# ~~~ should this have $mech->warn instead of die?
	# We need the line break after $code, because there may be a sin-
	# gle-line comment at the end,  and no line break.  ("foo //bar"
	# would fail without  this,  because  the  })  would  be  com-
	# mented out too.)
	my $func = ($w->compile("(function(){ $code\n })") || die $@)
		->execute($w, bless [$w, $w->upgrade($elem)], 'JE::Scope');

	sub { my $ret = $func->();
	      return typeof $ret eq 'undefined' ? undef : $ret };
}

sub define_setter {
	my $obj = shift;
	my $cref = pop;
	my $prop = pop;
	for (@_) {
		my $next_obj = $obj->{$_};
		defined $next_obj or
			$obj->{$_} = {},
			$obj = $obj->{$_}, next;
		$obj = $next_obj;
	}
	$obj->prop({name=>$prop, store=>sub{$cref->($_[1])}});
	return;
}


=begin comment

(old stuff that used to be in W:M:P:JS--might be useful for reference
 for a while)

sub new {
	my $self = SUPER::new{shift};
	my $mech = shift;

	#weaken $mech;

	# ~~~ I need to finish all these class bindings.

	# Base class, so we don't need to add Node's methods to every
	# single class
	$self->bind_class(
		package => 'HTML::DOM::Node',
		name    => 'Node',
		methods => [qw/ insertBefore replaceChild removeChild
                          appendChild hasChildNodes cloneNode
		    addEventListener removeEventListener dispatchEvent /],
		props   => [qw/ nodeName nodeValue nodeType parentNode
                     childNodes firstChild lastChild previousSibling
                     nextSibling attributes ownerDocument /],
	);

	$self->bind_class(
		package => 'HTML::DOM',
		name    => 'HTMLDocument',
		methods => [qw/ createElement createDocumentFragment
		               createTextNode createComment
		             createCDATASection createProcessingInstruction
		          createAttribute createEntityReference
		      getElementsByTagName open close write writeln
		   getElementById getElementsByName /],
		props => [ qw/ doctype implementation
		                  documentElement title referrer
		                    domain URL body images applets
		                      links forms anchors cookie /],
		isa => 'Node',
	);

	$self->bind_class(
		package => 'HTML::DOM::Element',
		name    => 'HTMLElement',
		isa => 'Node',
	);

	$self->bind_class(
		package => 'HTML::DOM::Element::Body',
		name    => 'HTMLBodyElement',
		props => [qw/ aLink background bgColor link
		                           text vLink /],
		isa => 'HTMLElement',
	);

	$self->bind_class(
		package => 'HTML::DOM::NodeList',
		wrapper   => sub {
			WWW::Mechanize::Plugin::JavaScript::NodeList
			 ->new(@_);
		},
		name    => 'NodeList',
	);
	$self->new_function(NodeList => sub {
		die 'NodeList cannot be instantiated.';
	})->prop('prototype')
	  ->new_method(item => sub { shift->value->[shift] });
	

	$self->bind_class(
		package => 'HTML::DOM::Collection',
		wrapper   => sub {
			WWW::Mechanize::Plugin::JavaScript::HTMLCollection
			 ->new(@_);
		},
		name    => 'HTMLCollection',
	);
	my $hc_proto = $self->new_function(NodeList => sub {
		die 'NodeList cannot be instantiated.';
	})->prop('prototype');
	$hc_proto->new_method(item => sub { shift->value->[shift] });
	$hc_proto->new_method(namedItem => sub { shift->value->{shift} });


	# ~~~ I also need to finish all these properties

	$self->{document} = shift;
	$self->{navigator}{userAgent} = $mech->agent;
	$self->{window} = $self;
}

# ------------ NODE LIST CLASS -----------------#

package WWW::Mechanize::Plugin::JavaScript::JNodeList;

our $VERSION = '0.000002';
our @ISA = 'JE::Object';


sub new {
	my ($w, $nl) = @_; # window, nodelist
	
	my $self = JE::Object::Array->new($w);
	$self->prototype($w->prop('NodeList')->prop('prototype'));
	$$$self{WMPDOM_nodelist} = $nl;
}

sub prop {
	my ($self, $name, $val) =  (shift, @_);
	my $guts = $$self;

	if ($name =~ /^(?:0|[1-9]\d*)\z/ and $name < 4294967295) {
		return $$guts{WMPDOM_nodelist}[$name];
	}
	$self->SUPER::prop(@_);
}

sub is_enum {
	my ($self,$name) = @_;
	if ($name =~ /^(?:0|[1-9]\d*)\z/ and $name < 4294967295) {
		return defined $$$self{WMPDOM_nodelist}[$name];
	}
	SUPER::is_enum $self $name;
}

sub keys {
	my $self = shift;
	0..$#{$$$self{WMPDOM_nodelist}}, SUPER::keys $self;
}

sub delete { !1 }

sub value { $${$_[0]}{WMPDOM_nodelist} };

sub exists {
	my ($self, $name) =  (shift, @_);
	my $guts = $$self;

	if ($name =~ /^(?:0|[1-9]\d*)\z/ and $name < 4294967295) {
		return defined $$guts{WMPDOM_nodelist}[$name];
	}
	$self->SUPER::exists(@_);
}

sub class { 'NodeList' }


# ------------ HTML COLLECTION CLASS -----------------#

package WWW::Mechanize::Plugin::JavaScript::HTMLCollection;
# (long package name!)

our $VERSION = '0.000002';
our @ISA = 'WWW::Mechanize::Plugin::JavaScript::NodeList';

# ~~~ finish this class

=end comment

=cut


# ------------------ DOCS --------------------#

1;


=head1 NAME

WWW::Mechanize::Plugin::JavaScript::JE - JE backend for WMPJS

=head1 DESCRIPTION

This little module is a bit of duct tape to connect the JavaScript plugin
for L<WWW::Mechanize> to the JE JavaScript engine. Don't use this module
directly. For usage, see
L<WWW::Mechanize::Plugin::JavaScript>.

=head1 REQUIREMENTS

HTML::DOM 0.009 or later

JE 0.019 or later

=head1 SEE ALSO

=over 4

=item -

L<WWW::Mechanize::Plugin::JavaScript>

=item -

L<JE>

=item -

L<HTML::DOM>

=cut




