use 5.010;
use strict;
use warnings;

use RT::Extension::EscalationSets::Test
    testing => 'RT::Action::EscalationSets',
    config => $ENV{RT_ADD_CONFIG} || '',
    tests => undef,
    nodb => 1;
#use RT::Extension::EscalationSets::Test tests => undef, config=>'Set($DatabaseType, "Pg");', server_ok => 1;
require RT::Extension::EscalationSets::MockTransaction;

use constant DATE_FORMAT => '%Y-%m-%d %T';

## UNIX timestamp 0:
use constant NOT_SET => '1970-01-01 00:00:00';

use_ok('RT::Action::EscalationSets');
use_ok('Date::Manip::Date');

# Now 
my $now = RT::Extension::EscalationSets::str_to_dm(Val => 'now', ToTz => 'UTC');

my $ac = new RT::Action::EscalationSets;

##


my $res = $ac->esets_delta('-2 minutes', '-2 minutes', $now);
isnt($res, undef);
ok( $res->value() eq '0:0:0:0:0:0:0', 'delta1==delta2 -> 0' );

$res = $ac->esets_delta('-2 minutes', '3 minutes', $now);
isnt($res, undef);
ok( $res->value() eq '0:0:0:0:0:5:0', 'delta2=delta1+5minutes -> 5 minutes' );


done_testing();