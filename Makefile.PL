#!/usr/bin/perl

BEGIN{ require 5.006; }
use ExtUtils::MakeMaker;

# I’m keeping these separate, in case these modules should ever be dis-
# tributed individually:
%dom_prq = (
	Carp                          => 0,
	Encode                        => 0,
	Hash::Util::FieldHash::Compat => 0,
	HTML::DOM                     =>  .021, # contentWindow
	HTML::DOM::Collection         => 0,
	HTML::DOM::Interface          =>  .019, # EventTarget
	HTML::DOM::NodeList::Magic    =>  .020, # 2nd arg to new
	HTML::DOM::View               =>  .018, # inside-out; writa-
	HTTP::Headers::Util           => 0,     # ble document
	overload                      => 0,
	Scalar::Util                  => 0,
	strict                        => 0,
	Time::HiRes                   => 0,
	URI                           => 0,
	warnings                      => 0,
# for testing:
	lib         => 0,
	Scalar'Util => 1.09, # refaddr
	Test::More  => 0,
	URI::file   => 0,
);
%js_prq = (
	CSS::DOM::Interface  => 0,
	Encode               => 0,
	HTML::DOM::Interface => 0,
	Scalar::Util         => 0,
	strict               => 0,
	URI::Escape          => 0,
	warnings             => 0,
#	WWW::Mechanize::Plugin::DOM   =>  .005, # Window
# for testing:
	lib        => 0,
	Test::More => 0,
	URI::file  => 0,
);
%je_prq = (
	Carp                          => 0,
	Hash::Util::FieldHash::Compat => 0,
	HTML::DOM::Interface          => 0,
	JE                            =>  .022, # bind_class’s
	Scalar::Util                  => 0,     # unwrap option
	strict                        => 0,
	warnings                      => 0,
#	WWW::Mechanize::Plugin::DOM   =>  .007, # top
# for testing:
	lib        => 0,
	Test::More => 0,
	URI::file  => 0,
);

for(\(%dom_prq, %js_prq, %je_prq)) {
	for $k(keys %$_) {
		$prq{$k} = $$_{$k}
			unless exists $prq{$k} and $$_{$k} < $prq{$k};
	}
}

eval{require WWW::Mechanize}
	&& exists &WWW::Mechanize::abort
	&& !exists &WWW::Mechanize::next_handler
or $prq{WWW::Mechanize} = 9999, print <<, "\n" ;
This module requires the experimental version of WWW::Mechanize that
is to be found at the following URL (revision 506 or higher):
http://www-mechanize.googlecode.com/svn/wm/branches/plugins/

WriteMakefile(
    NAME                => 'WWW::Mechanize::Plugin::JavaScript',
    AUTHOR              => 'Father Chrysostomos <sprout & cpan . org>',
    VERSION_FROM        => 'lib/WWW/Mechanize/Plugin/JavaScript.pm',
    ABSTRACT_FROM       => 'lib/WWW/Mechanize/Plugin/JavaScript.pm',
    PL_FILES            => {},
    PREREQ_PM           => \%prq,
    dist               => { COMPRESS => 'gzip -9f', SUFFIX => 'gz',
                            TAR => 'COPYFILE_DISABLE=1 tar' },
    clean              => { FILES => 'WWW-Mechanize-Plugin-JavaScript-*' },
);
