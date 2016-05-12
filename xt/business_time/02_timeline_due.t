use 5.010;
use strict;
use warnings;

use RT::Extension::EscalationSets::Test
    testing => 'RT::Action::EscalationSets',
    config => $ENV{RT_ADD_CONFIG} || '',
    tests => undef;
require RT::Extension::EscalationSets::MockTransaction;
use RT::Extension::EscalationSets::TestFunc;

use RT::Extension::EscalationSets
    qw/ str_to_dm  load_config /;
use_ok('RT::Action::EscalationSets');
use_ok('Date::Manip::Date');

use constant DATE_FORMAT => '%Y-%m-%d %T';
use constant NOT_SET => '1970-01-01 00:00:00';

# Date::Manip objects
my $now = str_to_dm(Val => 'now', ToTz => 'UTC');
my $not_set = str_to_dm(Val => NOT_SET, FromTz => 'UTC');
my $dm_config = {
    WorkDayBeg => '08:00:00',
    WorkDayEnd => '17:00:00'
};
my $now_business = str_to_dm(Val => 'now', ToTz => 'UTC', Config => $dm_config);

my $ac = new RT::Action::EscalationSets;

my ( $baseurl, $m ) = RT::Test->started_ok();

subtest 'Fall on business day, Due was unset, Ticket was before Due' => sub {
    my $ticket = new_ticket();

    my $oldtxnval = '2016-05-12 01:15:00';  #Out of business time
    my $txncreated = '2016-05-12 00:00:00'; #
    my $out_of_business = str_to_dm(Val => '2016-05-12 00:05:00', FromTz => 'UTC', Config => $dm_config);
    $out_of_business->next_business_day(0, 1);
    my $check = increase_date($out_of_business, '1 hour 15 minutes');
    # On txn creation moment Due was a 30 minutes in the future
    my $txn = do_set_unset_due($ticket, $oldtxnval);
    $txn->SetCreated($txncreated);
    
    my $res = $ac->timeline_due(['Created', '5 minutes'], $dm_config, $txn, $out_of_business, $ticket);
    isnt($res, undef, 'return not undef');
    ok(is_configured($res, $dm_config), 'configured Date::Manip obj');
    cmp_ok( $res->printf(DATE_FORMAT), 'eq', $check->printf(DATE_FORMAT), 'return NOW+(txn_val-txn_created)');
};

subtest 'Fall on business day, Due was unset, Ticket was Overdue' => sub {
    my $ticket = new_ticket();
    
    my $oldtxnval = '2016-05-12 00:00:00';  #Out of business time
    my $txncreated = '2016-05-12 01:15:00'; #
    my $out_of_business = str_to_dm(Val => '2016-05-12 00:05:00', FromTz => 'UTC', Config => $dm_config);
    $out_of_business->next_business_day(0, 1);
    # On txn creation moment Due was in the past
    my $txn = do_set_unset_due($ticket, $oldtxnval);
    $txn->SetCreated($txncreated);
    
    my $res = $ac->timeline_due(['Created', '5 minutes'], $dm_config, $txn, $now, $ticket);
    isnt($res, undef, 'return not undef');
    ok(is_configured($res, $dm_config), 'configured Date::Manip obj');
    cmp_ok( $res->printf(DATE_FORMAT), 'eq', $oldtxnval, 'return txn_val');
};

subtest 'Fall on business day, Due was not unset' => sub {
    my $ticket = new_ticket();
    my $starts = str_to_dm(Val => '2016-05-12 17:00:00', FromTz => 'UTC', Config => $dm_config);
    $ticket->SetStarts($starts->printf(DATE_FORMAT));
    my $check = '2016-05-13 10:00:00';
    my $txn = undef;
    
    my $res = $ac->timeline_due(['Starts', '2 business hours'], $dm_config, $txn, $now, $ticket);
    isnt($res, undef, 'return not undef');
    ok(is_configured($res, $dm_config), 'configured Date::Manip obj');
    cmp_ok( $res->printf(DATE_FORMAT), 'eq', $check, 'return ticket_start_date+config_due');
};

undef $m;

done_testing();