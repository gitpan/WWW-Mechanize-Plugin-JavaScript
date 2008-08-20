#!perl -w

# This test makes sure that the DOM plugin can load without
# WWW::Mechanize’s having been loaded first. I found this wasn’t working
# when I tried to use pmvers.

print "1..1\n";
print "not " unless eval{require WWW::Mechanize::Plugin::DOM};
print "ok 1\n";
