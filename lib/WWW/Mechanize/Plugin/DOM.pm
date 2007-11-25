package WWW::Mechanize::Plugin::DOM;

# DOM is in a separate module from JavaScript because other scripting
# languages may use DOM as well. Anyone have time to implement Acme::Chef
# bindings for Mech? :-)

$VERSION = '0.001';

use strict;
use warnings;

use Encode qw'encode decode';
use HTML::DOM 0.009;
use HTTP::Headers::Util 'split_header_words';
use Scalar::Util 'weaken';


sub init { # expected to return a plugin object that the mech object will
           # use to communicate with the plugin.

	my ($package, $mech) = @_;

	my $self = bless {
		script_handlers => {},
		event_attr_handlers => {},
	}, $package;

	$mech->add_handler(
		parse_html => \&_parse_html
	);
	$mech->add_handler( get_content =>
	    sub {
	        my $mech = shift;
	        $mech->is_html or WWW::Mechanize::next_handler;
	        my $stuff =
	            $mech->plugin('DOM')->tree->documentElement->as_HTML;
	        defined $$self{charset} ? encode $$self{charset}, $stuff :
			$stuff;
	    }
	);
	$mech->add_handler( get_text_content =>
	    sub {
	        my $mech = shift;
	        $mech->is_html or WWW::Mechanize::next_handler;
	        my $stuff =
	            $mech->plugin('DOM')->tree->documentElement->as_text;
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
				#     (.009)
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
			    my($tree, $elem) = @_;

			    my $lang = $elem->attr('type');
			    defined $lang
			        or $lang = $elem->attr('language');
			    defined $lang or $lang = $script_type;

			    my $uri;
			    my($inline, $code, ) = 0;
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
			    }
			    else {
			        $code = $elem->firstChild->data;
			        ++$inline;
			        $uri = $mech->uri;
			    };
	
			    SCRIPT_HANDLER: {
			    while(my($lang_re,$handler) = each
			          %{$$self{script_handlers}}) {
			        next if $lang_re eq 'default';
			        $lang =~ $lang_re and
			            &$handler($tree, $code,
					$uri, 1, $inline),
			        # ~~~ That line number (1) is currently
			        #    invalid for almost all inline scripts.
			            last SCRIPT_HANDLER;
			    } # end of while
			    &{ $$self{script_handlers}{default} ||
			        return }($tree, $code,
					$uri, 1, $inline);
			        # ~~~ That line number (1) is currently
			        #    invalid for almost all inline scripts.
			    } # end of S_H
			});

			$tree->elem_handler(noscript => sub {
				$_[1]->detach#->delete;
				# ~~~ delete currently stops it from work-
				#     ing; I need to looook into this.
			});
		}

		if(%{$$self{event_attr_handlers}}) {
			$tree->event_attr_handler(sub {
				my($elem, $event, $code) = @_;
				my $lang = $elem->attr('language');
				defined $lang or $lang = $script_type;

				HANDLER: {
				if(defined $lang) {
				while(my($lang_re,$handler) = each
				    %{$$self{event_attr_handlers}}) {
					next if $lang_re eq 'default';
					$lang =~ $lang_re and
					    &$handler($elem, $event,$code),
					    last HANDLER;
				}} # end of if-while
				&{ $$self{event_attr_handlers}{default} ||
					return }($elem, $event,$code);
				} # end of HANDLER
			});
		}
	}
	# ~~~ Should we use the content of <noscript> elems if no script
	#     handler is provided but an event attribute handler *is*
	#     provided? (Now who would be crazy enough to do that?)
	if(!%{$$self{script_handlers}}) {
		$tree->elem_handler(noscript => sub {
			$_[1]->replace_with_content->delete;
			# ~~~ why does this need delete?
		});
	}

	# Find out the encoding:
	$$self{charset} = my $cs = {
		map @$_,
		split_header_words $mech->response->header('Content-Type')
	 }->{charset};

	$tree->write(defined $cs ? decode $cs, $src : $src);
	$tree->close;

	return 1;
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

sub tree { $_[0]{tree} }

sub DESTROY {
	($_[0]{tree}||return)->delete;
}


=head1 NAME

WWW::Mechanize::Plugin::DOM - HTML Document Object Model plugin for Mech

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
          my($dom_tree, $code, $url, $line, $is_inline) = @_;
          # ... code to run the script ...
  }

  sub event_attr_handler {
          my($elem, $event_name, $code) = @_;
          # ... code that returns a coderef ...
  }

  $m->plugin('DOM')->tree; # DOM tree for the current page

=head1 DESCRIPTION

blah blah blah

(event_attr|script)_handlers => {default => ... } is used when the script 
elem has no
'type' or 'language' attribute, and there is no Content-Script-Type header.

=head1 BUGS

The line number passed to script handlers is currently always 1,
which is usually wrong 
if the
script is inline.
