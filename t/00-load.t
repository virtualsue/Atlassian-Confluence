#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Atlassian::Confluence' ) || print "Bail out!
";
}

diag( "Testing Atlassian::Confluence $Atlassian::Confluence::VERSION, Perl $], $^X" );
