#!perl -w

# I have not got round to writing a complete set of tests yet. For now I’m
# just testing for fixed bugs and other changes.

use strict; use warnings;
use lib 't';
use Test::More;

use utf8;

use URI::data;
use URI::file;
use WWW::Mechanize;

sub data_url {
	my $u = new URI 'data:';
	$u->media_type('text/html');
	$u->data(shift);
	$u
}

use tests 4; # interface for callback routines
for my $lang ('default', qr//) {
	my $test_name = ref $lang ? 'with re' : $lang;
	my @result;
	my $event_triggered;
	(my $m = new WWW::Mechanize)->use_plugin('DOM' =>
		script_handlers => {
			$lang => sub {
				push @result, "script",
				  map ref eq "URI::file" ? $_ : ref||$_, @_
			}
		},
		event_attr_handlers => {
			$lang => sub {
				push @result, "event",
				 map ref eq "URI::file" ? $_ : ref||$_, @_;
				sub { ++$event_triggered }
			}
		},
	);
	my $uri = URI::file->new_abs( 't/dom-callbacks.html' );
	my $script_uri = URI::file->new_abs( 't/dom-test-script' );
	$m->get($uri);
	is_deeply \@result, [
		script =>
			'WWW::Mechanize',
			'HTML::DOM',
			"<!--\nthis is a short script\n-->",
			"$uri",
			 3,
			 1, # not normative; it just has to be true
		script =>
			'WWW::Mechanize',
			'HTML::DOM',
			"This is an external script.\n",
			"$script_uri",
			 1,
			 0, # not normative; it just has to be false
		event =>
			'WWW::Mechanize',
			'HTML::DOM::Element::A',
			'click',
			'bar',
			"$uri",
			 8,
		event =>
			'WWW::Mechanize',
			'HTML::DOM::Element::A',
			'click',
			'baz',
			"$uri",
			 9,
	], "callbacks ($test_name)";
	$m->plugin('DOM')->tree->getElementsByTagName('a')->[0]->
		trigger_event('click');
	is $event_triggered, 1, "event handlers ($test_name)";
}

use tests 1; # warnings caused by script tags and event handlers
{            # with no language
	my $warnings = 0;
	local $SIG{__WARN__} = sub { ++$warnings;};

	(my $m = new WWW::Mechanize)->use_plugin('DOM',
		script_handlers => {
			'foo' => sub {}
		},
		event_attr_handlers => {
			'foo' => sub {}
		},
	);
	$m->get(URI::file->new_abs( 't/dom-no-lang.html' ));
	is $warnings, 0, 'absence of a script language causes no warnings';
}

use tests 2; # charset
{     
	(my $m = new WWW::Mechanize)->use_plugin('DOM');
	$m->get(URI::file->new_abs( 't/dom-charset.html' ));
	is $m->plugin('DOM')->tree->title,
		'Ce mai faceţ?', 'charset';
	local $^W;
	$m->get(URI::file->new_abs( 't/dom-charset2.html' ));
	is $m->plugin('DOM')->tree->title,
		'Αὐτὴ ἡ σελίδα χρησιμοποιεῖ «UTF-8»', 'charset 2';
}

use tests 2; # get_text_content with different charsets
{            # (bug in 0.002)
	(my $m = new WWW::Mechanize)->use_plugin('DOM');
	$m->get(URI::file->new_abs( 't/dom-charset.html' ));
	like $m->content(format=>'text'), qr/Ce mai face\376\?/,
		 'get_text_content';
	local $^W;
	$m->get(URI::file->new_abs( 't/dom-charset2.html' ));
	my $qr = qr/
		\316\221\341\275\220\317\204\341\275\264\302\240\341
		\274\241[ ]\317\203\316\265\316\273\341\275\267\316\264\316
		\261[ ]\317\207\317\201\316\267\317\203\316\271\316\274\316
		\277\317\200\316\277\316\271\316\265\341\277\226[ ]\302\253
		UTF-8\302\273/x;
	like $m->content(format=>'text'), $qr,
		 'get_text_content on subsequent page';
}

use tests 2; # on(un)load
{
	my $events = '';
	(my $m = new WWW::Mechanize)->use_plugin('DOM' =>
		event_attr_handlers => {
			default => sub {
				my $code = $_[3];
				sub { $events .= $code }
			}
		},
	);
	$m->get(URI::file->new_abs( 't/dom-onload.html' ));
	is $events, 'onlode', '<body onload=...';
	$m->get(new_abs URI'file 't/blank.html');
	SKIP:{skip"unimplemented",1;is $events, 'onlodeonunlode'}
}

use tests 1; # window
{
	my $p = (my $m = new WWW::Mechanize)->use_plugin('DOM');
	$m->get(URI::file->new_abs( 't/blank.html' ));
	isa_ok $p->window, 'WWW::Mechanize::Plugin::DOM::Window';
}

use tests 4; # scripts_enabled
{
	my $script_src;

	my $p = (my $m = new WWW::Mechanize)->use_plugin('DOM' =>
		script_handlers => {
			default => sub {
				$script_src = $_[2]
			}
		}
	);
	ok $p->scripts_enabled, 'scripts enabled by default';

	my $url = data_url(<<'END');
		<HTML><head><title>oetneotne</title></head>
		<script>this is a script</script>
END
	$p->scripts_enabled(0);
	$m->get($url);
	is $script_src, undef, 'disabling scripts works';
	$m->get($url);
	is $script_src, undef, 'the disabled settings survives a ->get';
	$m->plugin("DOM")->scripts_enabled(1);
	$m->get($url);
	is $script_src, 'this is a script', 're-enabling scripts works';
}
