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

subtest 'get_lvl_expired_dates' => sub {
    my $ticket = new_ticket();
    $ticket->SetResolved(increase_date($now, '-5 minutes')->printf(DATE_FORMAT));
    $ticket->SetStarts($now->printf(DATE_FORMAT));
    $ticket->SetDue(increase_date($now, '11 minutes')->printf(DATE_FORMAT));
    $ticket->SetStarted(NOT_SET);

    my %test_levels = (
        1 => {Resolved => '2 minutes'},
        2 => {Starts => '5 minutes'},
        3 => {Due => '-4 minutes'},
        4 => {Told => '6 minutes'}, # Told is undef by default
        5 => {Started => '7 minutes'},
    );

    my $res = $ac->get_lvl_expired_dates(\%test_levels, undef, $ticket);

    isnt($res, undef, 'return not undef');

    cmp_ok($res->{'1'}->printf(DATE_FORMAT), 'eq', increase_date($now, '-3 minutes')->printf(DATE_FORMAT));
    cmp_ok($res->{'2'}->printf(DATE_FORMAT), 'eq', increase_date($now, '5 minutes')->printf(DATE_FORMAT));
    cmp_ok($res->{'3'}->printf(DATE_FORMAT), 'eq', increase_date($now, '7 minutes')->printf(DATE_FORMAT));
    is($res->{'4'}, undef);
    is($res->{'5'}, undef);
};

subtest 'get_lvl (no level)' => sub {
    my %expired_dates = (
        test1 => increase_date($now, '10 minutes'),
        2 => increase_date($now, '1 seconds'),
        9 => increase_date($now, '4 days'),
    );

    my $res = $ac->get_lvl(\%expired_dates, $now);
    is($res, undef);
};

subtest 'get_lvl (one level in past)' => sub {
    my %expired_dates = (
        test1 => increase_date($now, '10 minutes'),
        2 => increase_date($now, '-1 seconds'),
        9 => increase_date($now, '4 days'),
    );

    my $res = $ac->get_lvl(\%expired_dates, $now);
    cmp_ok($res, 'eq' , '2');
};

subtest 'get_lvl (multiple levels in past)' => sub {
    my %expired_dates = (
        test1 => increase_date($now, '10 minutes'),
        2 => increase_date($now, '-1 seconds'),
        9 => increase_date($now, '-4 days'),
        0 => increase_date($now, '-2 minutes'),
    );

    my $res = $ac->get_lvl(\%expired_dates, $now);
    cmp_ok($res, 'eq' , '2');
};

undef $m;

done_testing();