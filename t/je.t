#!perl

# I have not got round to writing a complete set of tests yet. For now I’m
# just testing for fixed bugs and other changes.

use strict; use warnings;
use lib 't';
use Test::More;

use HTML::DOM::Interface ':all';
use URI::file;
use WWW::Mechanize;

# blank page for playing with JS; some tests need their own, though
my $js = (my $m = new WWW::Mechanize)->use_plugin('JavaScript',
	engine => 'JE'
);
$m->get(URI::file->new_abs( 't/blank.html' ));
$js->new_function($_ => \&$_) for qw 'is ok';

use tests 2; # third arg to new_function
{
	$js->new_function(foo => sub { return 72 }, 'String');
	$js->new_function(bar => sub { return 72 }, 'Number');
	is ($js->eval('typeof foo()'), 'string', 'third arg passed ...');
	is ($js->eval('typeof bar()'), 'number', '... to new_function');
}

use tests 1; # types of bound read-only properties
{
	is $m->plugin('JavaScript')->eval(
		'typeof document.nodeType'
	), 'number', 'types of bound read-only properties';
}

use tests 1; # unwrap
{
	sub Foo::Bar::baz{
		return join ',', map ref||(defined()?$_:'^^'),@_
	};
	$js->bind_classes({
		'Foo::Bar' => 'Bar', 
		Bar => {
			baz => METHOD | STR
		}
	});
	$js->set('baz', bless[], 'Foo::Bar');
	is($js->eval('baz.baz(null, undefined, 3, "4", baz)'),
	   'Foo::Bar,^^,^^,JE::Number,JE::String,Foo::Bar', 'unwrap');
}

use tests 4; # null DOMString
{
	sub Phoo::Bar::bar {
		return (undef,765)[!!pop];
	}
	sub Phoo::Bar::baz { "heelo" }
	sub Phoo::Bar::nullbaz {}
	$js->bind_classes({
		'Phoo::Bar' => 'Phoo', 
		Phoo => {
			bar => METHOD | STR,
			baz => STR,
			nullbaz => STR,
		}
	});
	$js->set('baz', bless[], 'Phoo::Bar');
	ok($js->eval('baz.bar(0) === null'),
		'undef --> null conversion for a DOMString retval');
	ok($js->eval('baz.bar(1) === "765"'),
		'any --> string conversion for a DOMString retval');
	ok($js->eval('baz.nullbaz === null'),
		'undef --> null conversion when getting a DOMString prop');
	ok($js->eval('baz.baz === "heelo"'),
		'any --> string conversion when getting a DOMString prop');
}

use tests 2; # window wrappers
{
	ok $js->eval('window === top'),
		'windows are wrapped up in global objects';
	ok $js->eval('window === document.defaultView'),
		'window === document.defaultView';
}

use tests 3; # frames
{
	$js->eval(q|
		document.write("<iframe id=i src='data:text/html,'>")
		document.close()
	|);
	ok $js->eval('frames[0] && "document" in frames[0] &&
			frames[0].document.defaultView == frames[0]'),
		'frame access by array index', or diag $@;
	ok $js->eval('frames.i && "document" in frames.i'),
		'frame access by name';
	ok $js->eval('frames.i === frames[0]'),
		'the two methods return the same object';
}
