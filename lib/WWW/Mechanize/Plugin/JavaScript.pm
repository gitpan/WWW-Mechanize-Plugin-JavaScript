package WWW::Mechanize::Plugin::JavaScript;

use strict;   # :-(
use warnings; # :-(

use Encode 'decode_utf8';
use Scalar::Util qw'weaken';
use URI::Escape 'uri_unescape';
no WWW::Mechanize ();

our $VERSION = '0.007';

# Attribute constants (array indices)
sub mech() { 0 }
sub jsbe() { 1 } # JavaScript back-end (object)
sub benm() { 2 } # Back-end name
sub init_cb() { 3 } # callback routine that's called whenever a new js
                    # environment is created
sub alert()   { 4 }
sub confirm() { 5 }
sub prompt()  { 6 }
sub cb() { 7 } # class bindings
sub tmout() { 8 } # timeouts

{no warnings; no strict;
undef *$_ for qw/mech jsbe benm init_cb
                alert confirm prompt tmout/} # These are PRIVATE constants!

sub init { # expected to return a plugin object that the mech object will
           # use to communicate with the plugin.

	my ($package, $mech) = @_;

	my $self = bless [$mech], $package;
	weaken $self->[mech];

	my $scripter = sub {
		my($mech,$doc,$code,$url,$line,$inline) = @_;

		$code =~ s/^\s*<!--[^\cm\cj\x{2028}\x{2029}]*(?x:
		         )(?:\cm\cj?|[\cj\x{2028}\x{2029}])//
			and ++$line if $inline;

#warn $code if $inline;
#warn $url unless $inline;
		
		my $be = $mech->plugin('JavaScript')->_start_engine;

		$be->eval($code, $url, $line);
		$@ and $mech->warn($@);
	};

	my $event_attribute_handler = sub {
		my($mech,$elem,undef,$code,$url,$line) = @_;

		my $func = $mech->plugin('JavaScript')->
			_start_engine->event2sub($code,$elem,$url,$line);

		sub {
			my $event_obj = shift;
			my $ret = &$func($event_obj);
			defined $ret and !$ret and
				$event_obj->preventDefault;
			# ~~~ I need to change this logic for whichever
			#     event has it reversed (don't remember which
			#     it was; I'll have to look it up!).
		};
	};

	$mech->use_plugin(DOM =>
		script_handlers => {
		    default => $scripter,
		    qr/(?:^|\/)(?:x-)?(?:ecma|j(?:ava)?)script[\d.]*\z/i =>
				$scripter,
		},
		event_attr_handlers => {
		    default => $event_attribute_handler,
		    qr/(?:^|\/)(?:x-)?(?:ecma|j(?:ava)?)script[\d.]*\z/i =>
				$event_attribute_handler,
		},
	);

	$mech->set_my_handler(request_preprepare => sub {
		my($request,$mech) = @_;
		$mech->plugin('JavaScript')->eval(
			decode_utf8 uri_unescape opaque {uri $request}
		);
		$@ and $mech->warn($@);
		WWW'Mechanize'abort;
	}, m_scheme => 'javascript');

	weaken $mech; # stop closures from preventing destruction

	$self;
}

sub options {
	my $self = shift;
	my %opts = @_;

	my $w;
	for(keys %opts) {
		if($_ eq 'engine') {
			if($self->[jsbe] &&
			   $self->[benm] ne $opts{$_}
			) {
			    $self->[mech]->die(
			        "Can't set JavaScript engine to " .
			        "'$opts{$_}' since $self->[benm] is " .
			        "already loaded.");;
			}
			$self->[benm] = $opts{$_};;
		}
		elsif($_ eq 'alert') {
			($w ||= $self->[mech]->plugin('DOM')->window)
				->set_alert_function($opts{$_});
		}
		elsif($_ eq 'confirm') {
			($w ||= $self->[mech]->plugin('DOM')->window)
				->set_confirm_function($opts{$_});
		}
		elsif($_ eq 'prompt') {
			($w ||= $self->[mech]->plugin('DOM')->window)
				->set_prompt_function($opts{$_});
		}
		elsif($_ eq 'init') {
			$self->[init_cb] = $opts{$_};
		}
		else {
			$self->[mech]->die(
			    "JavaScript plugin: Unrecognized option '$_'"
			);
		}
	}
}

sub _start_engine {
	my $self = shift;
	return $self->[jsbe] if $self->[jsbe];
	
	if(!$self->[benm]) {
	    # try this one first, since it's faster:
	    eval{require WWW::Mechanize::Plugin::JavaScript::SpiderMonkey};
	    if($@) {
	        require 
	            WWW::Mechanize::Plugin::JavaScript::JE;
                $self->[benm] = 'JE'
            }
	    else { $self->[benm] = 'SpiderMonkey' };
	}
	else {
		require "WWW/Mechanize/Plugin/JavaScript/" .
			"$$self[benm].pm";
	}

	$self->[jsbe] = "WWW::Mechanize::Plugin::JavaScript::$$self[benm]"
		-> new( my $w = $self->[mech]->plugin('DOM')->window );
	require HTML::DOM::Interface;
	require CSS::DOM::Interface;
	for ($$self[jsbe]) {
		$_->bind_classes(\%HTML::DOM::Interface);
		$_->bind_classes(\%CSS::DOM::Interface);
		$_->bind_classes(
		  \%WWW::Mechanize::Plugin::DOM::Interface
		);
		for my $__(@{$self->[cb]||[]}){
			$_->bind_classes($__)
		}
		$_->set(document => $self->[mech]->plugin('DOM')->tree);

		$_->set('screen', {});
			# ~~~ This doesn’t belong here. I need to get a
			#     wround to addy nit two the win dough object
			#     one sigh figger out zackly how it shoe be
			#     done.

	} # for $$self->[jsbe];
	{ ($self->[init_cb]||next)->($self); }
	weaken $self; # closures
	return $$self[jsbe];
}

sub bind_classes {
	my $plugin = shift;
	push @{$plugin->[cb]}, $_[0];
	$plugin->[jsbe] && $plugin->[jsbe]->bind_classes($_[0]);
}

for(qw/set eval new_function/) {
	no strict 'refs';
	*$_ = eval "sub { shift->_start_engine->$_(\@_) }";
}

sub check_timeouts {
	shift->[mech]->plugin("DOM")->check_timers;
}

# ~~~ This is experimental. The purposed for this is that code that relies
#     on a particular version of a JS back end can check to see which back
#     end is being used before doing Foo->VERSION($bar). The problem with
#     it is that it returns nothing unless the JS environment has already
#     been loaded. If we have it start the JS engine, we may load it and
#     then not use it.
sub engine { shift->[benm] }


# ------------------ DOCS --------------------#

1;


=head1 NAME

WWW::Mechanize::Plugin::JavaScript - JavaScript plugin for WWW::Mechanize

=head1 VERSION

Version 0.007 (alpha)

=head1 SYNOPSIS

  use WWW::Mechanize;
  $m = new WWW::Mechanize;
  
  $m->use_plugin('JavaScript');
  $m->get('http://www.cpan.org/');
  $m->get('javascript:alert("Hello!")'); # prints Hello!
                                         # (not yet implemented)
  $m->use_plugin(JavaScript =>
          engine  => 'SpiderMonkey',
          alert   => \&alert, # custom alert function
          confirm => \&confirm,
          prompt  => \&prompt,
          init    => \&init, # initialisation function
  );                         # for the JS environment
  
=head1 DESCRIPTION

This module is a plugin for L<WWW::Mechanize> that provides JavaScript
capabilities (who would have guessed?).

To load the plugin, just use L<WWW::Mechanize>'s C<use_plugin> method (note
that the current stable release of that module doesn't support this; see
L</PREREQUISITES>, below):

  $m = new WWW::Mechanize;
  $m->use_plugin('JavaScript');

You can pass options to the plugin via the C<use_plugin> method. It takes
hash-style arguments and they are as follows:

=over 4

=item engine

Which JavaScript back end to use. Currently, this module only supports
L<JE>, a pure-Perl JavaScript interpreter. Later it will support
SpiderMonkey via either L<JavaScript::SpiderMonkey> or 
L<JavaScript.pm|JavaScript>. If this option is
not specified, either SpiderMonkey or JE will be used, whichever is
available. It is possible to
write one's own bindings for a particular JavaScript engine. See below,
under L</BACK ENDS>. 

=item alert

Use this to provide a custom C<alert> function. The default one will print
its arguments followed by a new line.

=item confirm

Like C<alert>, but for the C<confirm> function instead. There is no 
default.

=item prompt

Likewise.

=item init

Pass to this option a reference to a subroutine and it will be run every
time a new JavaScript environment is initialised. This happens after the
functions above have been created. The first argument will
be the plugin object (more on that below). You can use this, for instance, 
to make your
own functions available to JavaScript.

=back

=head1 METHODS

L<WWW::Mechanize>'s C<use_plugin> method will return a plugin object. The
same object can be retrieved via C<< $m->plugin('JavaScript') >> after the
plugin is loaded. The following methods can be called on that object:

=over 4

=item eval

This evaluates the JavaScript code passed to it. You can optionally pass
two more arguments: the file name or URL, and the first line number.

=item new_function

This creates a new global JavaScript function out of a coderef. Pass the 
name as
the first argument and the code ref as the second.

=item set

Sets the named variable to the value given. If you want to assign to a
property of a property ... of a global property, pass each property name
as a separate argument:

  $m->plugin('JavaScript')->set(
          'document', 'location', 'href' => 'http://www.perl.org/'
  );

=item bind_classes

With this you can bind Perl classes to JavaScript, so that JavaScript can
handle objects of those classes. These class bindings will persist from one
page to the next.

You should pass a hash ref that has the
structure described in L<HTML::DOM::Interface>, except that this method
also accepts a C<< _constructor >> hash element, which should be set to the
name of the method to be called when the constructor function is called
within JavaScript; e.g., C<< _constructor => 'new' >>.

=item check_timeouts

This will evaluate the code associated with each timeout registered with 
the JS C<setTimeout> function,
if the appropriate interval has elapsed.

B<Warning:> This is deprecated and will be deleted in a future release. Use
the DOM plugins's C<check_timers> method instead.

=back

=head1 JAVASCRIPT FEATURES

The members of the HTML DOM that are available depend on the versions of
L<HTML::DOM> and L<CSS::DOM> installed. See L<HTML::DOM::Interface> and
L<CSS::DOM::Interface>.

For a list of the properties of the window object, see 
L<WWW::Mechanize::Plugin::DOM::Window>.

The JavaScript plugin itself provides just the C<screen> object, which is
empty. Later this may be moved to the DOM plugin's window object, but that
should make little difference to you, unless you are writing bindings for
another scripting language.

=head1 BACK ENDS

A back end has to be in the WWW::Mechanize::Plugin::JavaScript:: name
space. It will be C<require>d by this plugin implicitly when its name is
passed to the C<engine> option.

The following methods must be implemented:

=head2 Class methods

=over 4

=item new

This method is passed a window (L<WWW::Mechanize::Plugin::DOM::Window>)
object.

It has to create a JavaScript environment, in which the global object
delegates to the window object for the members listed in 
L<C<%WWW::Mechanize::Plugin::DOM::Window::Interface>|WWW::Mechanize::Plugin::DOM::Window/THE C<%Interface> HASH>
(that's quite a
mouthful, isn't it). When the window object is passed to the JavaScript environment, the global
object must be returned instead.

This method can optionally create C<window>, C<self> and C<frames>
properties
that refer to the global object, but this is not necessary. It might make
things a little more efficient.

Finally, it has to return an object that implements the interface below.

The back end has to do some magic to make sure that, when the global object
is passed to another JS environment, references to it automatically point
to a new global object when the user (or calling code) browses to another
page.

For instance, it could wrap up the global object in a proxy object
that delegates to whichever global object corresponds to the document.

=back

=head2 Object Methods

=over 4

=item eval

=item new_function

=item set

=item bind_classes

These correspond to those 
listed above for
the plugin object. Those methods are simply delegated to the back end, 
except that C<bind_classes> also does some caching if the back end hasn't
been initialised yet.

C<new_function> must also accept a third argument, indicating the return
type. This (when specified) will be the name of a JavaScript function that
does the type conversion. Only 'Number' is used right now.

=item event2sub ($code, $elem, $url, $first_line)

This method needs to turn the
event handler code in C<$code> into a
coderef, or an object that can be used as such, and then return it. That 
coderef will be
called with an HTML::DOM::Event object as its sole argument. It's return 
value, if
defined, will be used to determine whether the event's C<preventDefault>
method should be called.

=item define_setter

This will be called
with a list of property names representing the 'path' to the property. The
last argument will be a coderef that must be called with the value assigned
to the property.

B<Note:> This is actually not used right now. The requirement for this may
be removed some time before version 1.

=head1 PREREQUISITES

perl 5.8.3 or later (actually, this module doesn't use any features that
perl 5.6 doesn't provide, but its prerequisites require 5.8.3)

HTML::DOM 0.010 or later

JE 0.022 or later (when there is a SpiderMonkey binding available it will 
become optional)

The experimental version of WWW::Mechanize available at
L<http://www-mechanize.googlecode.com/svn/wm/branches/plugins/>, revision
506 or higher

CSS::DOM

=head1 BUGS

(See also L<WWW::Mechanize::Plugin::DOM/Bugs> and 
L<WWW::Mechanize::Plugin::JavaScript::JE/Bugs>.)

There is currently no system in place for preventing pages from different
sites from communicating with each other.

To report bugs, please e-mail the author.

=head1 AUTHOR & COPYRIGHT

Copyright (C) 2007-8 Father Chrysostomos
<C<< join '@', sprout => join '.', reverse org => 'cpan' >>E<gt>

This program is free software; you may redistribute it and/or modify
it under the same terms as perl.

=head1 SEE ALSO

=over 4

=item -

L<WWW::Mechanize>

=item -

L<WWW::Mechanize::Plugin::DOM>

=item -

L<HTML::DOM>

=item -

L<JE>

=item -

L<JavaScript.pm|JavaScript>

=item -

L<JavaScript::SpiderMonkey>

=back
