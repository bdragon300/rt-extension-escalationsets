use 5.010;
use strict;
use warnings;

use RT::Extension::EscalationSets::Test
    testing => 'RT::Action::EscalationSets',
    config => $ENV{RT_ADD_CONFIG} || '',
    tests => undef;
require RT::Extension::EscalationSets::MockTransaction;
use RT::Extension::EscalationSets qw/str_to_dm/;
use RT::Extension::EscalationSets::TestFunc;

use constant DATE_FORMAT => '%Y-%m-%d %T';

## UNIX timestamp 0:
use constant NOT_SET => '1970-01-01 00:00:00';

use_ok('RT::Action::EscalationSets');
use_ok('Date::Manip::Date');

# Now 
my $now = str_to_dm(Val => 'now', ToTz => 'UTC');

my $ac = new RT::Action::EscalationSets;

my ( $baseurl, $m ) = RT::Test->started_ok();
##

subtest 'Equal deltas' => sub {
    my $ticket = new_ticket();
    
    my $res = $ac->esets_business_delta(['Created', '-2 minutes'], ['Created', '-2 minutes'], undef, $ticket);
    isnt($res, undef);
    ok( $res->value() eq '0:0:0:0:0:0:0', 'delta1==delta2 -> 0' );
};

subtest 'Delta difference' => sub {
    my $ticket = new_ticket();
    my $res = $ac->esets_business_delta(['Created', '-2 minutes'], ['Created', '3 minutes'], undef, $ticket);
    isnt($res, undef);
    ok( $res->value() eq '0:0:0:0:0:5:0', 'delta2=delta1+5minutes -> 5 minutes' );
};

subtest 'One date is unset' => sub {
    my $ticket = new_ticket();
    
    $ticket->SetStarts(NOT_SET);
    
    my $res = $ac->esets_business_delta(['Created', '-2 minutes'], ['Starts', '3 minutes'], undef, $ticket);
    is($res, undef);
    
    $res = $ac->esets_business_delta(['Starts', '-2 minutes'], ['Created', '3 minutes'], undef, $ticket);
    is($res, undef);
};

undef $m;

done_testing();