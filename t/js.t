#!perl

# I have not got round to writing a complete set of tests yet. For now I’m
# just testing for fixed bugs and other changes.

use strict; use warnings; use utf8;
use lib 't';
use Test::More;

use URI::file;
use WWW::Mechanize;

# blank page for playing with JS; some tests need their own, though
my $js = (my $m = new WWW::Mechanize)->use_plugin('JavaScript');
$m->get(URI::file->new_abs( 't/blank.html' ));
$js->new_function($_ => \&$_) for qw 'is ok';

use tests 1; # class binding bug
{
	my $m;
	ok eval {
	($m = new WWW::Mechanize)
	 ->use_plugin('JavaScript', engine => 'JE')
	 ->bind_classes({
		'My::Package' => 'foo',
		'foo' => {}
	 }); 1
	}, 'bind_classes works before a page is fetched';
}

use tests 2; # line numbers for inline scripts
{
	my $warning;
	local $SIG{__WARN__} = sub { $warning = shift;};

	(my $m = new WWW::Mechanize)->use_plugin('JavaScript',
		engine => "JE");
	$m->get(URI::file->new_abs( 't/js-die.html' ));
	like $warning, qr/line 8(?!\d)/, 'line numbers for inline scripts';
	SKIP :{
		skip "requires HTML::DOM 0.012 or higher", 1
			if HTML::DOM->VERSION < 0.012;
		$m->plugin('DOM')->tree->getElementsByTagName('a')->[0]->
			trigger_event('click');
		like $warning, qr/line 11(?!\d)/,
			'line numbers for event attributes';
	}
}

use tests 2; # timeouts
{
	$js->eval('
		_ = "nothing"
		setTimeout("_=42",5000)
		clearTimeout(setTimeout("_=43",5100))
	');
	$js->check_timeouts;
	is $js->eval('this._'), 'nothing', 'before timeout';
	diag('pausing (timeout test)');
	sleep 6;
	$js->check_timeouts;
	is $js->eval('_'), '42', 'timeout';
}

use tests 1; # screen
{
	$js->eval('
		is(typeof this.screen, "object","screen object");
	');
}

use tests 2; # open
{
	$js->eval('
		open("foo"); // this will be a 404
	');
	like $m->uri, qr/foo$/, 'url after open()';
	$m->back;
	# ~~~ This is temporary. Once I have support for multiple windows,
	#     this test will have to be changed.
	like $m->uri, qr/blank\.html$/, 'open() adds to the history';
}

use tests 2; # navigator
{
	$js->eval('
		is(typeof this.navigator, "object","navigator object");
		is(navigator.appName,"WWW::Mechanize","navigator.appName");
	') or diag $@;
}

use tests 2; # multiple JS environments
{
	$m->get(URI::file->new_abs( 't/js-script.html' ));
	$m->get(URI::file->new_abs( 't/js-script2.html' ));
	is $m->plugin('JavaScript')->eval('foo'), 'baz',
		'which JS env are we in after going to another page?';
	$m->back;
	is $m->plugin('JavaScript')->eval('foo'), 'bar',
		'and which one after we go back?';
	$m->back;
}

use tests 1; # location stringification
{
	$js->eval(
		'is(location, location.href, "location stringification")'
	);
}

use tests 2; # javascript:
{
	my $uri = $m->uri;
	$m->get("Javascript:%20foo=%22ba%ca%80%22");
	is $js->eval('foo'), 'baʀ', 'javascript: URLs are executed';
diag $@ if $@;
	is $m->uri, $uri, '  and do not affect the page stack'
		or diag $m->response->as_string;
}

use tests 2; # custom functions for alert, etc.
{
	my $which = '';
	(my $m = new WWW::Mechanize)->use_plugin('JavaScript',
		alert => sub { $which .= "alert($_[0])" },
		confirm => sub { $which .= "confirm($_[0])" },
		prompt => sub { $which .= "prompt($_[0])" }
	);
	$m->get("data:text/html,");

	$m->plugin("JavaScript")->eval('
		alert("foo"), confirm("bar"), prompt("baz")
	');
	is $which , 'alert(foo)confirm(bar)prompt(baz)',
		'custom alert, etc.';

	$which = '';
	$m->plugin('JavaScript')->options(
		alert => sub { $which .= "sleepy($_[0])" },
		confirm => sub { $which .= "deny($_[0])" },
		prompt => sub { $which .= "tardy($_[0])" }
	);
	$m->plugin("JavaScript")->eval('
		alert("foo"), confirm("bar"), prompt("baz")
	');
	is $which , 'sleepy(foo)deny(bar)tardy(baz)',
	  'resetting custom alert, etc., after the JS env is created';
}

use tests 1; # non-HTML pages
{
	is eval{(my $m = new WWW::Mechanize)->use_plugin('JavaScript')
	         ->eval("35")}, 35,
	  'JS is available even when the page is not HTML';
}

