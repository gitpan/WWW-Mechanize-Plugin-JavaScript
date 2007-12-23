#!perl

# I have not got round to writing a complete set of tests yet. For now I’m
# just testing for fixed bugs.

BEGIN {
	eval {
		require WWW::Mechanize;
		WWW::Mechanize->can('use_plugin');
	} or require Test::More, import Test::More skip_all =>
		'You can\'t test this without the experimental version of Mech (see the docs).';

}

use strict; use warnings;
our $tests;
BEGIN { ++$INC{'tests.pm'} }
sub tests'VERSION { $tests += pop };
use Test::More;
plan tests => $tests;

use URI::file;

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

use tests 1; # line numbers for inline scripts
{
	my $warning;
	local $SIG{__WARN__} = sub { $warning = shift;};

	(my $m = new WWW::Mechanize)->use_plugin('JavaScript');
	$m->get(URI::file->new_abs( 't/die.html' ));
	like $warning, qr/line 8(?!\d)/, 'line numbers for inline scripts';
}

#die "Are you going to finish writing this?";

# ~~~ I need to write tests for everything listed in the Changes file.
