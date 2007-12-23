#!/usr/bin/perl -w

require 5.006;
use ExtUtils::MakeMaker;

# I’m keeping these separate, in case these modules should ever be dis-
# tributed individually:
%dom_prq = (
	Encode              => 0,
	HTML::DOM           =>  .010, # content_offset
	HTTP::Headers::Util => 0,
	LWP::Simple         => 0, # temporary prerq
	Scalar::Util        => 0,
	strict              => 0,
	URI                 => 0,
	warnings            => 0,
);
%js_prq = (
	CSS::DOM::Interface  => 0,
	HTML::DOM::Interface => 0,
	Scalar::Util         => 0,
	strict               => 0,
	Time::HiRes          => 0,
	URI                  => 0,
	warnings             => 0,
# for testing:
	Test::More => 0,
	URI::file  => 0,
);
%je_prq = (
	Carp                 => 0,
	HTML::DOM::Interface => 0,
	JE                   =>  .019, # scalar context for methods passed
	Scalar::Util         => 0,      # to bind_class
	strict               => 0,
	warnings             => 0,
);

for(\(%dom_prq, %js_prq, %je_prq)) {
	for $k(keys %$_) {
		$prq{$k} = $$_{$k}
			unless exists $prq{$k} and $$_{$k} < $prq{$k};
	}
}

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
