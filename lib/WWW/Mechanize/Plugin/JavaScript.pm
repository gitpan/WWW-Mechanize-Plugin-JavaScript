package WWW::Mechanize::Plugin::JavaScript;

use strict;   # :-(
use warnings; # :-(

use Scalar::Util qw'weaken';

our $VERSION = '0.001';

# Attribute constants (array indices)
sub mech() { 0 }
sub jsbe() { 1 } # JavaScript back-end (object)
sub benm() { 2 } # Back-end name
sub init_cb() { 3 } # callback routine that's called whenever a new js
                    # environment is created
sub alert()   { 4 }
sub confirm() { 5 }
sub prompt()  { 6 }

{no warnings; no strict;
undef *$_ for qw/mech jsbe benm init_cb
                  alert confirm prompt/} # These are PRIVATE constants!

sub init { # expected to return a plugin object that the mech object will
           # use to communicate with the plugin.

	my ($package, $mech) = @_;

	my $self = bless [$mech], $package;
	weaken $self->[mech];

	my $scripter = sub {
		my($doc,$code,$url,$line,$inline) = @_;

		$code =~ s/^\s*<!--[^\cm\cj\x{2028}\x{2029}]*(?x:
		         )(?:\cm\cj?|[\cj\x{2028}\x{2029}])// if $inline;

#warn $code if $inline;
#warn $url unless $inline;
		
		my $be = $self->_start_engine;

		$be->eval($code, $url, $line);
		$@ and $mech->warn($@);
	};

	my $event_attribute_handler = sub {
		my($elem,undef,$code) = @_;

		my $func = $self->_start_engine->event2sub($code, $elem);

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

	weaken $mech; # stop closures from preventing destruction

	$self;
}

sub options {
	my $self = shift;
	my %opts = @_;

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
			$self->[alert] = $opts{$_};
		}
		elsif($_ eq 'confirm') {
			$self->[confirm] = $opts{$_};
		}
		elsif($_ eq 'prompt') {
			$self->[prompt] = $opts{$_};
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
		-> new;
	require HTML::DOM::Interface;
	for ($$self[jsbe]) {
		$_->bind_classes(\%HTML::DOM::Interface);
		$_->bind_classes(
		  \%WWW::Mechanize::Plugin::JavaScript::Location::Interface
		);
		$_->set(document => $self->[mech]->plugin('DOM')->tree);
		$_->new_function(alert =>  # ~~~ reasonable default ?
			$$self[alert] || sub { print @_, "\n" });
		# ~~~ should we provide defaults for these two?
		{ $_->new_function(confirm => $$self[confirm] || next) }
		{ $_->new_function(prompt  => $$self[prompt ] || next) }

		# ~~~ need to finish the default window properties
		$_->set(document => location => my $l = 
			(__PACKAGE__.'::Location')->new(
				$$self[mech]->uri,
				$$self[mech]
			)
		);
		$_->set(location => $l);
		$_->define_setter(document => location => my $s = sub{
			$l->href(shift);
		});
		$_->define_setter(location => $s);
		$_->set(navigator => userAgent => $$self[mech]->agent);
	} # for $$self->[jsbe];
	{ ($self->[init_cb]||next)->($self); }
	return $$self[jsbe];
}

for(qw/bind_classes set eval new_function/) {
	no strict 'refs';
	*$_ = eval "sub { shift->_start_engine->$_(\@_) }";
}


package WWW::Mechanize::Plugin::JavaScript::Location;

use URI;
use HTML::DOM::Interface qw'STR METHOD VOID';
use Scalar::Util 'weaken';

our $VERSION = '0.001';

sub uri(){0};
sub mech(){1};
{no strict;undef *$_ for qw/uri mech STR METHOD VOID/;}

our %Interface = (
	__PACKAGE__, 'Location',
	Location => {
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
);

sub new { # usage: new .....::Location $uri, $mech
	my $class = shift;
	my $self = bless [@_], $class;
	$self->[uri] = new URI $self->[uri];
	weaken $self->[mech];
	$self;
}

sub hash {
	my $loc = shift;
	my $old = $loc->[uri]->fragment;
	$old = "#$old" unless !length $loc->[uri] and $loc->[uri] !~ /#\z/;
	if (@_){
		shift() =~ /#?(.*)/s;
		(my $uri = $loc->[uri]->clone)->fragment($1);
		$uri->eq($loc->[uri]) or $loc->[mech]->get($uri);
	}
	$old
}

sub host {
	my $loc = shift;
	if (@_) {
		(my $uri = $loc->[uri]->clone)->host(shift);
		$loc->[mech]->get($uri);
	}
	else {
		$loc->[uri]->host;
	}
}

sub hostname {
	my $loc = shift;
	if (@_) {
		(my $uri = $loc->[uri]->clone)->host_port(shift);
		$loc->[mech]->get($uri);
	}
	else {
		$loc->[uri]->host_port;
	}
}

sub href {
	my $loc = shift;
	if (@_) {
		$loc->[mech]->get(shift);
	}
	else {
		$loc->[uri]->as_string;
	}
}

sub pathname {
	my $loc = shift;
	if (@_) {
		(my $uri = $loc->[uri]->clone)->path(shift);
		$loc->[mech]->get($uri);
	}
	else {
		$loc->[uri]->path;
	}
}

sub port {
	my $loc = shift;
	if (@_) {
		(my $uri = $loc->[uri]->clone)->port(shift);
		$loc->[mech]->get($uri);
	}
	else {
		$loc->[uri]->port;
	}
}

sub protocol {
	my $loc = shift;
	if (@_) {
		shift() =~ /(.*):?/s;
		(my $uri = $loc->[uri]->clone)->scheme($1);
		$loc->[mech]->get($uri);
	}
	else {
		$loc->[uri]->scheme . ':';
	}
}

sub search {
	my $loc = shift;
	if (@_){
		shift() =~ /(\??)(.*)/s;
		(my $uri = $loc->[uri]->clone)->query(
			$1&&length$2 ? $2 : undef
		);
		$uri->eq($loc->[uri]) or $loc->[mech]->get($uri);
	} else {
		my $q = $loc->[uri]->query;
		defined $q ? "?$q" : "";
	}
}


# ~~~ Safari doesn't support forceGet. Do I need to?
sub reload  { # args (forceGet) 
	shift->[mech]->reload
}
sub replace { # args (URL)
	my $mech = shift->[mech];
	$mech->back();
	$mech->get(shift);
}


# ------------------ DOCS --------------------#

1;


=head1 NAME

WWW::Mechanize::Plugin::JavaScript - JavaScript plugin for WWW::Mechanize

=head1 VERSION

Version 0.001

B<WARNING:> This is an alpha release. The API is subject to change 
without
notice.

This set of modules is at a very early stage. Only a few features have
been implemented so far. Whether it will work for a particular case is
hard to say. Try it and see. (And patches are always welcome.)

=head1 SYNOPSIS

  use WWW::Mechanize;
  $m = new WWW::Mechanize;
  
  $m->use_plugin('JavaScript');
  $m->get('http://www.cpan.org/');
  $m->get('javascript:alert("Hello!")'); # prints Hello!
  
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
SpiderMonkey via the L<JavaScript::SpiderMonkey> module. If this option is
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
handle objects of those classes. You should pass a hash ref that has the
structure described in L<HTML::DOM::Interface>, except that this method
also accepts a C<< _constructor >> hash element, which should be set to the
name of the method to be called when the constructor function is called
within JavaScript; e.g., C<< _constructor => 'new' >>.

=back

=head1 BACK ENDS

A back end has to be in the WWW::Mechanize::Plugin::JavaScript:: name
space. It will be C<require>d by this plugin implicitly when its name is
passed to the C<engine> option.

It must provide a class method named C<new>. This method
simply has to create a JavaScript environment, with C<window> and C<self>
properties
that refer to the global object, and return an object.

The object must have methods corresponding to those listed above for
the plugin object. Those methods are simply delegated to the back end.

In addition, an object method named C<event2sub> must exist. It will be
passed the source code for an event handler as the first argument, and the
element to which it belongs as the second argument. It needs to turn that
event handler code into a
coderef, on an object that can be used as such, and then return it. That 
coderef will be
called with an HTML::DOM::Event object as its sole argument. It's return 
value, if
defined, will be used to determine whether the event's C<preventDefault>
method should be called.

You also need to provide a C<define_setter> method. This will be called
with a list of property names representing the 'path' to the property. The
last argument will be a coderef that must be called with the value assigned
to the property.

=head1 PREREQUISITES

perl 5.8.3 or later (actually, this module doesn't use any features that
perl 5.6 doesn't provide, but its prerequisites require 5.8.3)

HTML::DOM 0.009 or later

JE 0.019 or later (when there is a SpiderMonkey binding available it will 
become optional)

The experimental version of WWW::Mechanize available at
L<http://www-mechanize.googlecode.com/svn/branches/plugins/>

=head1 BUGS

Need plenty of placeholders here :-)

=over 4

=item *

=item *

=item *

=item *

=item *

=item *

=item *

=item *

=item *

=item *

=item *

=item *

=item *

=item *

=item *

=back

=head1 AUTHOR & COPYRIGHT

Copyright (C) 2007 Father Chrysostomos
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

L<JavaScript::SpiderMonkey>

=back
