package WWW::Mechanize::Plugin::JavaScript::JE;

use strict;   # :-(
use warnings; # :-(

use Carp 'croak';
use Hash::Util::FieldHash::Compat 'fieldhash';
use HTML::DOM::Interface ':all'; # for the constants
use JE 0.022;
use Scalar::Util qw'weaken';
use WWW::Mechanize::Plugin::DOM;

our $VERSION = '0.004';
our @ISA = 'JE';

fieldhash my %parathia;

# No need to implement eval since JE's method
# is sufficient

my @types;
$types[BOOL] = Boolean =>;
$types[STR ] = String  =>;
$types[NUM ] = Number  =>;
$types[OBJ ] = null    =>;

sub new {
	my $self = SUPER::new{shift};
	$parathia{$self} = shift;;
	
	my $i = \%WWW'Mechanize'Plugin'DOM'Window'Interface;
	for(grep !/^_/ && $$i{$_} & METHOD, =>=> keys %$i) {
		my $method = $_;
		my $type = $$i{$_};
		$self->new_method($_ => sub {
			my $parathi = $parathia{my $self = shift};
			# undocumented JE method:
			$self->_cast(
				scalar $parathi->$method(@_),
				$types[$type&TYPE]
			);
		});
	}
	for(grep !/^_/ && !($$i{$_}&METHOD) =>=> keys %$i) {
		my $name = $_;
		next if $name =~ /^(?:window|self)\z/; # for efficiency
		my $type = $$i{$_};
		if ($type & READONLY) {
			$self->prop({
				name => $_,
				readonly => 1,
				fetch => sub {
					my $self = shift;
					$parathia{$self}->$name;
					$self->_cast(
						scalar
						  $parathia{$self}->$name,
						$types[$type&TYPE]
					);
				},
			});
		}
		else {
			$self->prop({
				name => $_,
				fetch => sub {
					my $self = shift;
					$self->_cast(
						scalar
						  $parathia{$self}->$name,
						$types[$type&TYPE]
					);
				},
				store => sub {
					my $self = shift;
					$self->_cast(
						scalar
						  $parathia{$self}
						    ->$name(shift),
						$types[$type&TYPE]
					);
				},
			});
		}
	}

	$self->prop('window' => $self);
	$self->prop('self' => $self);
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

sub bind_classes {
	my($self, $classes) = @_;
	my @defer;
	for (grep /::/, keys %$classes) {
		my $i = $$classes{$$classes{$_}}; # interface info
		my @args = (
			unwrap  => 1,
			package => $_,
			name    => $$classes{$_},
			methods => [ map 
			   $$i{$_} & VOID ? $_ : "$_:$types[$$i{$_} & TYPE]",
			   grep !/^_/ && $$i{$_} & METHOD, keys %$i ],
			props => { map 
			   $$i{$_} & READONLY
			      ? ($_ =>{fetch=>"$_:$types[$$i{$_} & TYPE]"})
			      : ($_ => "$_:$types[$$i{$_} & TYPE]"),
			   grep !/^_/ && !($$i{$_} & METHOD), keys %$i  },
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
#			use Data::Dumper; print Dumper \@args if $_ !~ /HTML|CSS/;
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
	my ($w, $code, $elem, $url, $line) = @_;

	# ~~~ JE's interface needs to be improved. This is a mess:
	# ~~~ should this have $mech->warn instead of die?
	# We need the line break after $code, because there may be a sin-
	# gle-line comment at the end,  and no line break.  ("foo //bar"
	# would fail without  this,  because  the  })  would  be  com-
	# mented out too.)
	my $func =
		($w->compile("(function(){ $code\n })",$url,$line)||die $@)
		->execute($w, bless [
			$w,
			$elem->can('form') ? $w->upgrade($elem->form) : (),
			my $wrapper=($w->upgrade($elem))
		], 'JE::Scope');

	sub { my $ret = $func->apply($wrapper);
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

sub new_function {
	my($self, $name, $sub, $type) = @_;
	if(defined $type) {
		$self->new_function(
			$name => sub { $self->{$type}->($sub->(@_)) }
		);
		weaken $self;
	} else {
		shift->SUPER::new_function(@_);
	}
}


=cut


# ------------------ DOCS --------------------#

1;


=head1 NAME

WWW::Mechanize::Plugin::JavaScript::JE - JE backend for WMPJS

=head1 VERSION

0.004 (alpha)

=head1 DESCRIPTION

This little module is a bit of duct tape to connect the JavaScript plugin
for L<WWW::Mechanize> to the JE JavaScript engine. Don't use this module
directly. For usage, see
L<WWW::Mechanize::Plugin::JavaScript>.

=head1 BUGS

DOM members that are supposed to return a string or null (which is how a
DOMString is represented in JavaScript) currently always return a string.
In cases where it should be the null value, an empty string is returned
instead.

=head1 REQUIREMENTS

HTML::DOM 0.008 or later

JE 0.022 or later

=head1 SEE ALSO

=over 4

=item -

L<WWW::Mechanize::Plugin::JavaScript>

=item -

L<JE>

=item -

L<HTML::DOM>

=cut




