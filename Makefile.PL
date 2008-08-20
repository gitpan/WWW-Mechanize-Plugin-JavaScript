#!/usr/bin/perl

require 5.006;
use ExtUtils::MakeMaker;

# I’m keeping these separate, in case these modules should ever be dis-
# tributed individually:
%dom_prq = (
	Carp                => 0,
	Encode              => 0,
	HTML::DOM           =>  .010, # content_offset
	HTTP::Headers::Util => 0,
	LWP::Simple         => 0, # temporary prerq
	Scalar::Util        => 0,
	strict              => 0,
	URI                 => 0,
	warnings            => 0,
# for testing:
	lib        => 0,
	Test::More => 0,
	URI::file  => 0,
);
%js_prq = (
	CSS::DOM::Interface  => 0,
	HTML::DOM::Interface => 0,
	overload             => 0,
	Scalar::Util         => 0,
	strict               => 0,
	Time::HiRes          => 0,
	URI                  => 0,
	warnings             => 0,
# for testing:
	lib        => 0,
	Test::More => 0,
	URI::file  => 0,
);
%je_prq = (
	Carp                 => 0,
	HTML::DOM::Interface => 0,
	JE                   =>  .022, # bind_class’s unwrap option
	Scalar::Util         => 0,   
	strict               => 0,
	warnings             => 0,
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
	&& WWW::Mechanize->can('use_plugin')
or $prq{WWW::Mechanize} = 9999, print <<, "\n" ;
This module requires the experimental version of WWW::Mechanize that
is to be found at the following URL:
http://www-mechanize.googlecode.com/svn/branches/plugins/

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
