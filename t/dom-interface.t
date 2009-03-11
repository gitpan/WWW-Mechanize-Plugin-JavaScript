#!perl -w

use strict; use warnings; no warnings 'once';
use lib 't';
use Test::More;

require WWW::Mechanize::Plugin::DOM;

use tests 1; # Changes in 0.013

ok exists $WWW::Mechanize::Plugin::DOM::Window::Interface{parent},
 'parent';
