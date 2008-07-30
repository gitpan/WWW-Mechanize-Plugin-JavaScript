#!perl

# I have not got round to writing a complete set of tests yet. For now I’m
# just testing for fixed bugs and other changes.

use strict; use warnings;
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
	');
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

