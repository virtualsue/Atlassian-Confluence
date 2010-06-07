use inc::Module::Install;

name     'Atlassian-Confluence';
all_from 'lib/Atlassian/Confluence.pm';
author   q{Sue Spence <sue_cpan@pennine.com>};
license  'perl';

build_requires 'Test::More';

auto_install;

WriteAll;

