package WWW::Mechanize::Plugin::DOM::Window;

use strict; use warnings; no warnings qw 'utf8 parenthesis';

our $VERSION = '0.014';

use Hash::Util::FieldHash::Compat 'fieldhash';
use HTML::DOM::Interface 0.019 ':all';
use HTML::DOM::NodeList::Magic;
use HTML::DOM::View 0.018;
use Scalar::Util 'weaken';
use Time::HiRes 'time';

our @ISA = qw[ HTML::DOM::View
               HTML::DOM::EventTarget ];

no constant 1.03 ();
use constant::lexical +{ do {
	my $x; map +($_=>$x++), qw[
		lert cnfm prmp loco meck topp frms prnt
	]  # we use ‘meck’ so as not to conflict with the method
}};

use overload fallback=>1, (qw/@{} %{}/, ('_frames_collection')x2)[0,3,1,2];

fieldhash my %timeouts; # keyed by document
fieldhash my %navi;     # keyed by mech

# This does not follow the same format as %HTML::DOM::Interface; this cor-
# responds to the format of hashes *within* %H:D:I. The other format does
# not apply here, since we can’t bind the class like other classes. This
# needs to be bound to the global  object  (at  least  in  JavaScript).
our %Interface = (
	%{$HTML::DOM::Interface{AbstractView}},
	%{$HTML::DOM::Interface{EventTarget}},
	alert => VOID|METHOD,
	confirm => BOOL|METHOD,
	prompt => STR|METHOD,
	location => OBJ,
	setTimeout => NUM|METHOD,
	clearTimeout => NUM|METHOD,
	open => OBJ|METHOD,
	window => OBJ|READONLY,
	self => OBJ|READONLY,
	navigator => OBJ|READONLY,
	top => OBJ|READONLY,
	frames => OBJ|READONLY,
	length => NUM|READONLY,
	parent => OBJ|READONLY,
);

sub new {
	my $self = bless\[], shift;
	weaken($$self->[meck] = my $mech = shift);
	$$self->[loco] = ('WWW::Mechanize::Plugin::DOM::Location')->new(
				$mech
			);
	$self;
}

sub alert {
	my $self = shift;
	&{$$self->[lert]||sub{print @_,"\n";()}}(@_);
}
sub confirm {
	my $self = shift;
	($$self->[cnfm]||$$self->[meck]->die(
		"There is no default confirm function"
	 ))->(@_)
}
sub prompt {
	my $self = shift;
	($$self->[prmp]||$$self->[meck]->die(
		"There is no default prompt function"
	 ))->(@_)
}

sub set_alert_function   { $${$_[0]}[lert]     = $_[1]; }
sub set_confirm_function { $${$_[0]}[cnfm] = $_[1]; }
sub set_prompt_function  { $${$_[0]}[prmp] = $_[1]; }

sub location {
	my $self = shift;
	$$self->[loco]->href(@_) if @_;
	$$self->[loco];
}

sub navigator {
	my $mech = ${+shift}->[meck];
	$navi{$mech} ||=
		new WWW::Mechanize::Plugin::DOM::Navigator:: $mech;
}

sub setTimeout {
	my $doc = shift->document;
	my $time = time;
	my ($code, $ms) = @_;
	$ms /= 1000;
	my $t_o = $timeouts{$doc}||=[];
	$$t_o[my $id = @$t_o] =
		[$ms+$time, $code];
	return $id;
}

sub clearTimeout {
	delete $timeouts{shift->document}[shift];
	return;
}

sub open {
	${+shift}->[meck]->get(shift);
			# ~~~ Just a placeholder for now.
	return;
}

# ~~~ This really doesn’t belong here, but in DOM.pm. But it needs to
# access the same info as the timeout methods above. Maybe those should
# delegate to DOM.pm methods.
sub _check_timeouts {
	my $time = time;
	my $self = shift;
	local *_;
	my $t_o = $timeouts{$self->document}||return;
	for my $id(0..$#$t_o) {
		next unless $_ = $$t_o[$id];
		$$_[0] <= $time and
			($$self->[meck]->plugin('JavaScript')||return)
				->eval($$_[1]),
			delete $$t_o[$id];
	}
	return
}

# ~~~ This may be moved to Plugin::DOM proper later.
sub _count_timers {
 	my $self =  shift;
	my $t_o = $timeouts{$self->document}||return 0;
	my $count;
	for my $id(0..$#$t_o) {
		next unless $_ = $$t_o[$id];
		++$count
	}
	$count;
}

sub window { $_[0] }
*self = *frames = *window;
sub length { $_[0]->_frames_collection->length }

sub top {
	my $self = shift;
	$$self->[topp] || do {
		my $parent = $self;
		while() {
			$$parent->[prnt] or
			 weaken( $$self->[topp] = $parent), last;
			$parent = $$parent->[prnt];
		}
		$$self->[topp]
	};
}

sub parent {
	my $self = shift;
	$$self->[prnt] || $self;
}

sub _set_parent { weaken( ${$_[0]}->[prnt] = $_[1] ) }

sub event_listeners_enabled {
	${+shift}->[meck]->plugin("DOM")->scripts_enabled
}

sub _frames_collection {
	my $self = shift;
	$$self->[frms] ||= do{
		my $doc = $self->document;
		WWW::Mechanize::Plugin::DOM::Frames->new(
		HTML::DOM::NodeList::Magic->new(
		    sub { $doc->look_down(_tag => qr/^i?frame\z/) },
		    $doc
		))
	}
}

# ~~~ Will we need this?
#sub _reset_frames_collection { delete ${+shift}->[frms] }

sub document {
	my $self = shift;
	@_ || return $self->SUPER::document;
	delete $$self->[frms];
	$self->SUPER::document(@_);
}

sub mech { $${+shift}[meck] }


package WWW::Mechanize::Plugin::DOM::Location;

use URI;
use HTML::DOM::Interface qw'STR METHOD VOID';
use Scalar::Util 'weaken';

our $VERSION = '0.014';

use overload fallback => 1, '""' => sub{${+shift}->uri};

$$_{~~__PACKAGE__} = 'Location',
$$_{Location} = {
	hash => STR,
	host => STR,
	hostname => STR,
	href => STR,
	pathname => STR,
	port => STR,
	protocol => STR,
	search => STR,
	reload => VOID|METHOD,
	replace => VOID|METHOD,
}
for \%WWW::Mechanize::Plugin::DOM::Interface;

sub new { # usage: new .....::Location $uri, $mech
	my $class = shift;
	weaken (my $mech = shift);
	my $self = bless \$mech, $class;
	$self;
}

sub hash {
	my $loc = shift;
	my $old = (my $uri = $$loc->uri)->fragment;
	$old = "#$old" if defined $old;
	if (@_){
		shift() =~ /#?(.*)/s;
		(my $uri_copy = $uri->clone)->fragment($1);
		$uri_copy->eq($uri) or $$loc->get($uri);
	}
	$old||''
}

sub host {
	my $loc = shift;
	if (@_) {
		(my $uri = $$loc->uri->clone)->host(shift);
		$$loc->get($uri);
	}
	else {
		$$loc->uri->host;
	}
}

sub hostname {
	my $loc = shift;
	if (@_) {
		(my $uri = $$loc->uri->clone)->host_port(shift);
		$$loc->get($uri);
	}
	else {
		$$loc->uri->host_port;
	}
}

sub href {
	my $loc = shift;
	if (@_) {
		$$loc->get(shift);
	}
	else {
		$$loc->uri->as_string;
	}
}

sub pathname {
	my $loc = shift;
	if (@_) {
		(my $uri = $$loc->uri->clone)->path(shift);
		$$loc->get($uri);
	}
	else {
		$$loc->uri->path;
	}
}

sub port {
	my $loc = shift;
	if (@_) {
		(my $uri = $$loc->uri->clone)->port(shift);
		$$loc->get($uri);
	}
	else {
		$$loc->uri->port;
	}
}

sub protocol {
	my $loc = shift;
	if (@_) {
		shift() =~ /(.*):?/s;
		(my $uri = $$loc->uri->clone)->scheme($1);
		$$loc->get($uri);
	}
	else {
		$$loc->uri->scheme . ':';
	}
}

sub search {
	my $loc = shift;
	if (@_){
		shift() =~ /(\??)(.*)/s;
		(my $uri_copy = (my $uri = $$loc->uri)->clone)->query(
			$1&&length$2 ? $2 : undef
		);
		$uri_copy->eq($uri) or $$loc->get($uri);
	} else {
		my $q = $$loc->uri->query;
		defined $q ? "?$q" : "";
	}
}


# ~~~ Safari doesn't support forceGet. Do I need to?
sub reload  { # args (forceGet) 
	${+shift}->reload
}
sub replace { # args (URL)
	my $mech = ${+shift};
	$mech->back();
	$mech->get(shift);
}


package WWW::Mechanize::Plugin::DOM::Navigator;

use HTML::DOM::Interface qw'STR READONLY';
use Scalar::Util 'weaken';

our $VERSION = '0.014';

$$_{~~__PACKAGE__} = 'Navigator',
$$_{Navigator} = {
	appName => STR|READONLY,
	appVersion => STR|READONLY,
	userAgent => STR|READONLY,
}
for \%WWW::Mechanize::Plugin::DOM::Interface;

no constant 1.03 ();
use constant::lexical {
	mech => 0,
	name => 1,
	vers => 2,
};

sub new {
	weaken((my $self = bless[],pop)->[mech] = pop);
	$self;
}

sub appName {
	my $self = shift;
	my $old = $self->[name];
	defined $old or $old = ref $self->[mech];
	@_ and $self->[name] = shift;
	return $old;
}

sub appVersion {
	my $self = shift;
	my $old = $self->[vers];
	if(!defined $old) {
		$old = $self->userAgent;
		$old =~ /(\d.*)/s
		? $old = $1
		: $old = ref($self->[mech])->VERSION;
	}
	@_ and $self->[vers] = shift;
	return $old;
}

sub userAgent {
	shift->[mech]->agent;
}


# ~~~ This is horribly inefficient and clunky. It probably needs to be
#     programmed in full here, or at least the ‘Collection’ part (a tiny
#     bit of copy&paste).
package WWW::Mechanize::Plugin::DOM::Frames;

our $VERSION = '0.014';

use HTML::DOM::Collection;
our @ISA = "HTML::DOM::Collection";

use overload fallback => 1,'@{}' => sub {
	[map $_->contentWindow, @{shift->${\'SUPER::(@{}'}}]
};

sub FETCH { (shift->SUPER::FETCH(@_)||return)->contentWindow }



# ------------------ DOCS --------------------#

1;


=head1 NAME

WWW::Mechanize::Plugin::DOM::Window - Window object for the DOM plugin

=head1 VERSION

Version 0.014

THIS MODULE IS DEPRECATED. Please use L<WWW::Scripter> instead.

=head1 DESCRIPTION

This module provides the window object. It inherits from 
L<HTML::DOM::View> and L<HTML::DOM::EventTarget>.

=head1 METHODS

=over

=item location

Returns the location object (see L<WWW::Mechanize::Plugin::DOM::Location>).
If you pass an argument, it sets the C<href>
attribute of the location object.

=item alert

=item confirm

=item prompt

Each of these calls the function assigned by one of the following methods:

=item set_alert_function

=item set_confirm_function

=item set_prompt_function

Use these to set the functions called by the above methods. There are no
default C<confirm> and C<prompt> functions. The default C<alert> prints to
the currently selected file handle, with a line break tacked on the end.

=item navigator

Returns the navigator object. This currently has three properties, 
C<appName>
(set to C<ref $mech>) C<appVersion> (C<< ref($mech)->VERSION >>) and 
C<userAgent> (same as C<< $mech->agent >>).

You can pass values to C<appName> and C<appVersion> to set them.

=item setTimeout ( $code, $ms );

This schedules the C<$code> to run after C<$ms> seconds have elapsed, 
returning a
number uniquely identifying the time-out. 

=item clearTimeout ( $timeout_id )

The cancels the time-out corresponding to the C<$timeout_id>.

=item open ( $url )

This is a temporary placeholder. Right now it ignores all its args
except the first, and goes to the given URL, such that C<< ->open(foo) >>
is equivalent to C<< ->location('foo') >>.

=item window

=item self

=item frames

These three return the window object itself.

=item top

Returns the 'top' window, which is the window itself if there are no
frames.

=item parent

Returns the parent frame, if there is one, or the window object itself
otherwise.

=item mech

This returns the L<WWW::Mechanize> object that corresponds to the window.

=item length

This returns the number of frames.

=back

=head1 FRAMES

You can access frames by index or by name by using the window object as an
array or hash, respectively.

=head1 THE C<%Interface> HASH

The hash named C<%WWW::Mechanize::Plugin::DOM::Window::Interface> lists the
interface members for the window object. It follows the same format as
hashes I<within> L<%HTML::DOM::Interface|HTML::DOM::Interface>, like this:

  (
      alert => VOID|METHOD,
      confirm => BOOL|METHOD,
      ...
  )

It does not include C<mech>.

=head1 SEE ALSO

=over 4

=item -

L<WWW::Mechanize>

=item -

L<WWW::Mechanize::Plugin::DOM>

=item -

L<WWW::Mechanize::Plugin::DOM::Location>

=item -

L<HTML::DOM::View>

=back
