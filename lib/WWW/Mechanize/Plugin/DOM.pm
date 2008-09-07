package WWW::Mechanize::Plugin::DOM;

# DOM is in a separate module from JavaScript because other scripting
# languages may use DOM as well. Anyone have time to implement Acme::Chef
# bindings for Mech? :-)

$VERSION = '0.005';

use 5.006;

use strict;
use warnings;

use Encode qw'encode decode';
use Hash::Util::FieldHash::Compat 'fieldhash';
use HTML::DOM 0.010;
use HTTP::Headers::Util 'split_header_words';
use Scalar::Util 'weaken';
no WWW::Mechanize ();
no WWW::Mechanize::Plugin::DOM::Window ();

fieldhash my %parathia; # keyed by mech

sub init { # expected to return a plugin object that the mech object will
           # use to communicate with the plugin.

	my ($package, $mech) = @_;

	my $self = bless {
		script_handlers => {},
		event_attr_handlers => {},
		s => 1, # scriptable
	}, $package;

	$mech->add_handler(
		parse_html => \&_parse_html
	);
	$mech->add_handler( get_content =>
	    sub {
	        my $mech = shift;
	        $mech->is_html or WWW::Mechanize::next_handler;
	        my $stuff = (my $self = $mech->plugin('DOM'))
	            ->tree->documentElement->as_HTML;
	        defined $$self{charset} ? encode $$self{charset}, $stuff :
			$stuff;
	    }
	);
	$mech->add_handler( get_text_content =>
	    sub {
	        my $mech = shift;
	        $mech->is_html or WWW::Mechanize::next_handler;
	        my $stuff = (my $self = $mech->plugin('DOM'))
	            ->tree->documentElement->as_text;
	        defined $$self{charset} ? encode $$self{charset}, $stuff :
			$stuff;
	    }
	);
	$mech->add_handler( extract_forms =>
		sub {
			shift->plugin('DOM')->tree->forms
		}
	);
	# ~~~ finish the various handlers

#	$self->options(@opts);

	$self;
}

sub _parse_html {
	my ($mech,$src) = @_;
	weaken $mech;
	my $self = $mech->plugin('DOM');
	weaken $self;

	$$self{tree} = my $tree = new HTML::DOM
			response => $mech->response,
			cookie_jar => $mech->cookie_jar;

	$tree->error_handler(sub{$mech->warn($@)});

	# ~~~ Do I need to add support for event hooks here?
	$tree->default_event_handler(sub {
		my $event = shift;
		my $type = $event->type;
		my $tag = (my $target = $event->target)->tag;
		# ~~~ I need to finish adding all these cases
		if($type eq 'click' && $tag eq 'input') {
			my $input_type = $target->type;
			if($input_type eq 'submit') {
				# ~~~ Should cases like this go into
				#     HTML::DOM? How would that fit into
				#     the current API? Or would the API
				#     have to be reworked?
				$target->form->submit;
			}
			elsif($input_type eq 'reset') {
				$target->form->reset;
				# ~~~ not currently supported by HTML::DOM
				#     (.010)
			}
		}
		if($type eq 'submit' && $tag eq 'form') {
			$mech->request($target->make_request);
		}
	});

	if(%{$$self{script_handlers}} || %{$$self{event_attr_handlers}}) {
		my $script_type = $mech->response->header(
			'Content-Script-Type');
		defined $script_type or $tree->elem_handler(meta =>
		    sub {
			my($tree, $elem) = @_;
			return unless lc $elem->attr('http-equiv')
				eq 'content-script-type';
			$script_type = $elem->attr('content');
		});

		if(%{$$self{script_handlers}}) {
			$tree->elem_handler(script => sub {
			    return unless $self->{s};
			    my($tree, $elem) = @_;

			    my $lang = $elem->attr('type');
			    defined $lang
			        or $lang = $elem->attr('language');
			    defined $lang or $lang = $script_type;

			    my $uri;
			    my($inline, $code, $line) = 0;
			    if($uri = $elem->attr('src')) {
			        # ~~~ Is there some way to get the
			        #     Mech object to do this with-
			        #    out pushing the page stack?
			        require LWP::Simple;
			        require URI;
			        my $base = $mech->base;
   			        $uri = URI->new_abs( $uri, $base )
			            if $base;
			        defined(
			           $code = LWP::Simple::get($uri)
			        ) or $mech->warn("couldn't get script $uri"),return;
			        # ~~~ I probably need to provide better
			        #     diagnostics. Maybe I can't use
			        #     LWP::Simple.
			        
			        $line = 1;
			    }
			    else {
			        $code = $elem->firstChild->data;
			        ++$inline;
			        $uri = $mech->uri;
			        $line = _line_no(
					$src,$elem->content_offset
			        );
			    };
	
			    SCRIPT_HANDLER: {
			    if(defined $lang) {
			    while(my($lang_re,$handler) = each
			          %{$$self{script_handlers}}) {
			        next if $lang_re eq 'default';
			        $lang =~ $lang_re and
			            &$handler($mech, $tree, $code,
					$uri, $line, $inline),
			            # reset iterator:
			            keys %{$$self{script_handlers}},
			            last SCRIPT_HANDLER;
			    }} # end of if-while
			    &{ $$self{script_handlers}{default} ||
			        return }($mech,$tree, $code,
					$uri, $line, $inline);
			    } # end of S_H
			});

			$tree->elem_handler(noscript => sub {
				return unless $self->{s};
				$_[1]->detach#->delete;
				# ~~~ delete currently stops it from work-
				#     ing; I need to looook into this.
			});
		}

		if(%{$$self{event_attr_handlers}}) {
			$tree->event_attr_handler(sub {
				my($elem, $event, $code, $offset) = @_;
				my $lang = $elem->attr('language');
				defined $lang or $lang = $script_type;

			        my $uri = $mech->uri;
			        my $line = defined $offset ? _line_no(
					$src, $offset
			        ) : undef;

				HANDLER: {
				if(defined $lang) {
				while(my($lang_re,$handler) = each
				    %{$$self{event_attr_handlers}}) {
					next if $lang_re eq 'default';
					$lang =~ $lang_re and
					  &$handler($mech, $elem,
				              $event,$code,$uri,$line),
					  # reset the hash iterator:
					  keys
					    %{$$self{event_attr_handlers}},
					  last HANDLER;
				}} # end of if-while
				&{ $$self{event_attr_handlers}{default} ||
				    return }(
					$mech,$elem,$event,$code,$uri,$line
				);
				} # end of HANDLER
			});
		}
	}
	# ~~~ Should we use the content of <noscript> elems if no script
	#     handler is provided but an event attribute handler *is*
	#     provided? (Now who would be crazy enough to do that?)
	$tree->elem_handler(noscript => sub {
		return if $self->{s} && %{$$self{script_handlers}};
		$_[1]->replace_with_content->delete;
		# ~~~ why does this need delete?
	});

	$tree->defaultView(
		my $view = $parathia{$mech} ||=
			new WWW'Mechanize'Plugin'DOM'Window $mech
	);
	$view->document($tree);

	# Find out the encoding:
	$$self{charset} = my $cs = {
		map @$_,
		split_header_words $mech->response->header('Content-Type')
	 }->{charset};

	$tree->write(defined $cs ? decode $cs, $src : $src);
	$tree->close;

	$tree->body->trigger_event('load');
	# ~~~ Problem: Ever since JavaScript 1.0000000, the
	#     (un)load events on the body attribute have associated event
	#     handlers with the Window object. But the DOM 2 Events spec
	#     doesn’t provide for events on the window (view) at all; only
	#     on Nodes. The load event is supposed to be triggered on the
	#     document. In HTML 5 (10 June 2008 draft), what we are doing
	#     here is correct. In
	#     Safari & FF 3, the body element’s attributes create event
	#     handlers on the window, which are called with the document as
	#     the event’s target.

	return 1;
}

sub _line_no {
	my ($src,$offset) = @_;
	return 1 + (() =
		substr($src,0,$offset)
		    =~ /\cm\cj?|[\cj\x{2028}\x{2029}]/g
	);
}

sub options {
	my($self,%opts) = @_;
	for (keys %opts) {
		if($_ eq 'script_handlers') {
			%{$$self{script_handlers}} = (
				%{$$self{script_handlers}}, %{$opts{$_}}
			);
		}
		elsif($_ eq 'event_attr_handlers') {
			%{$$self{event_attr_handlers}} = (
			    %{$$self{event_attr_handlers}},
			    %{$opts{$_}}
			);
		}
		else {
			require Carp;
			Carp::croak(
			    "$_ is not a valid option for the DOM plugin"
			);
		}
	}
}

sub clone {
	my $self = shift;
	bless { map +($_=>$$self{$_}), qw[
		script_handlers event_attr_handlers s
	]}, ref $self
}

sub tree { $_[0]{tree} }
sub window { $_[0]{tree}->defaultView }

sub scripts_enabled {
	my $old = (my $self = shift)->{s};
	$self->{s} = shift if @_;
	$old
}

sub check_timers {
	# ~~~ temporary hack
	shift->window->_check_timeouts;
}


=head1 NAME

WWW::Mechanize::Plugin::DOM - HTML Document Object Model plugin for Mech

=head1 VERSION

0.005 (alpha)

=head1 SYNOPSIS

  use WWW::Mechanize;

  my $m = new WWW::Mechanize;

  $m->use_plugin('DOM',
      script_handlers => {
          default => \&script_handler,
          qr/(?:^|\/)(?:x-)?javascript/ => \&script_handler,
      },
      event_attr_handlers => {
          default => \&event_attr_handler,
          qr/(?:^|\/)(?:x-)?javascript/ => \&event_attr_handler,
      },
  );

  sub script_handler {
          my($mech, $dom_tree, $code, $url, $line, $is_inline) = @_;
          # ... code to run the script ...
  }

  sub event_attr_handler {
          my($mech, $elem, $event_name, $code, $url, $line) = @_;
          # ... code that returns a coderef ...
  }

  $m->plugin('DOM')->tree; # DOM tree for the current page
  $m->plugin('DOM')->window; # Window object

=head1 DESCRIPTION

This is a plugin for L<WWW::Mechanize> that provides support for the HTML
Document Object Model. This is a part of the 
L<WWW::Mechanize::Plugin::JavaScript> distribution, but it can be used on
its own.

=head1 USAGE

To enable this plugin, use Mech's C<use_plugin> method, as shown in the
synopsis.

To access the DOM tree, use C<< $mech->plugin('DOM')->tree >>, which 
returns an HTML::DOM object.

You may provide a subroutine that runs an inline script like this:

  $mech->use_plugin('DOM',
      script_handlers => {
          qr/.../ => sub { ... },
          qr/.../ => sub { ... },
          # etc
      }
  );

And a subroutine for turning HTML event attributes into subroutines, like
this:

  $mech->use_plugin('DOM',
      event_attr_handlers => {
          qr/.../ => sub { ... },
          qr/.../ => sub { ... },
          # etc
     }
  );

In both cases, the C<qr/.../> should be a regular expression that matches
the scripting language to which the handler applies, or the string
'default'. The scripting language will be either a MIME type or the
contents of the C<language> attribute if a script element's C<type>
attribute is not present. The subroutine specified as the 'default' will be
used if there is no handler for the scripting language in question or if
there is no Content-Script-Type header and, for 
C<script_handlers>, the script element has no
'type' or 'language' attribute.

Each time you move to another page with WWW::Mechanize, a different copy
of the DOM plugin object is created. So, if you must refer to it in a 
callback
routine, don't use a closure, but get it from the C<$mech> object that is
passed as the first argument.

The line number passed to an event attribute handler requires L<HTML::DOM>
0.012 or higher. It will be C<undef> will lower versions.

=head1 METHODS

This is the usual boring list of methods. Those that are described above
are listed here without descriptions.

=item window

This returns the window object.

=item tree

This returns the DOM tree (aka the document object).

=item check_timers

This evaluates the code associated with each timeout registered with 
the window's C<setTimeout> function,
if the appropriate interval has elapsed.

=item scripts_enabled ( $new_val )

This returns a boolean indicating whether scripts are enabled. It is true
by default. You can disable scripts by passing a false value.

B<Bug:> This does not
disable event handlers that are already registered.

=head1 THE 'LOAD' EVENT

Currently the (on)load event is triggered when the page finishes parsing.
This plugin assumes that you're not going to be loading any images, etc.

=head1 THE C<%Interface> HASH

If you are creating your own script binding, you'll probably want to access
the hash named C<%WWW::Mechanize::Plugin::DOM::Interface>, which lists, in
a machine-readable format, the interface members of the location and
navigator objects. It follows the same format as
L<%HTML::DOM::Interface|HTML::DOM::Interface>.

See also L<WWW::Mechanize::Plugin::DOM::Window/THE C<%Interface> HASH> for
a list of members of the window object.

=head1 PREREQUISITES

L<HTML::DOM> 0.019 or later

L<WWW::Mechanize>

The current stable release of L<WWW::Mechanize> does not support plugins. 
See
L<WWW::Mechanize::Plugin::JavaScript> for more info.

L<constant::lexical>

L<Hash::Util::FieldHash::Compat>

=head1 BUGS

=over 4

=item *

The onunload event is not yet supported. The window object is not yet part
of the event dispatch chain. Some events
do not yet do everything they are supposed to; e.g., a link's C<click>
method does not go to the next page.

=item *

This plugin does not yet provide WWW::Mechanize with all the necessary
callback routines (for C<extract_images>, etc.).

=item *

Currently, external scripts referenced within a page are always read as
Latin-1. This will be fixed.

=item *

The location object's C<replace> method does not currently work correctly
if the current page is the first page. In that case it acts like an
assignment to C<href>.

=item *

Disabling scripts does not currently affect event handlers that are already
registered.

=item *

The C<window> method dies if the page is not HTML.

=back

=head1 AUTHOR & COPYRIGHT

Copyright (C) 2007 Father Chrysostomos
<C<< join '@', sprout => join '.', reverse org => 'cpan' >>E<gt>

This program is free software; you may redistribute it and/or modify
it under the same terms as perl.

=head1 SEE ALSO

L<WWW::Mechanize::Plugin::DOM::Window>

L<WWW::Mechanize::Plugin::DOM::Location>

L<WWW::Mechanize::Plugin::JavaScript>

L<WWW::Mechanize>

L<HTML::DOM>
